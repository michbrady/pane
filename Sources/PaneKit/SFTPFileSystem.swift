import Foundation

/// A server reached with the system `sftp`. One shared connection (ssh's ControlMaster) serves every
/// request, so the password or passphrase is asked of the server once. Browsing only until S-065.
public final class SFTPFileSystem: RemoteFileSystem, @unchecked Sendable {
    public enum Login: Sendable {
        /// Sign in with a password.
        case password(String)
        /// Sign in with a key file. `passphrase` is empty for a key with none, or one the agent holds.
        case key(path: String, passphrase: String)
    }

    public let serverKey: String
    private let host: String
    private let port: Int?
    private let user: String
    private let login: Login
    private let knownHosts: URL
    private let workFolder: URL
    private let runner: ProcessRunner
    private let now: @Sendable () -> Date

    /// `knownHosts` is Pane's own list of trusted servers, never `~/.ssh/known_hosts`.
    /// `workFolder` holds the shared-connection socket and the password helper. Keep its path short.
    public init(host: String, port: Int? = nil, user: String, login: Login, knownHosts: URL, workFolder: URL,
                runner: ProcessRunner = SystemProcessRunner(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.host = host.lowercased()
        self.port = port
        self.user = user
        self.login = login
        self.knownHosts = knownHosts
        self.workFolder = workFolder
        self.runner = runner
        self.now = now
        serverKey = "sftp://" + self.host + (port.map { ":\($0)" } ?? "")
    }

    // MARK: Connecting

    /// Signs in and returns the folder the server starts in. Throws `unknownHostKey` for a new server
    /// and `hostKeyChanged` when the key differs from the one trusted.
    public func start() async throws -> String {
        let result = try await sftp("pwd")
        if let line = result.stdout.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("Remote working directory:") }) {
            return String(line.dropFirst("Remote working directory:".count)).trimmingCharacters(in: .whitespaces)
        }
        return "/"
    }

    /// Remembers a server's key, after the person agreed to trust it.
    public func trust(keyLine: String) throws {
        try FileManager.default.createDirectory(at: knownHosts.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: knownHosts, encoding: .utf8)) ?? ""
        let prefix = existing.isEmpty || existing.hasSuffix("\n") ? existing : existing + "\n"
        try (prefix + keyLine + "\n").write(to: knownHosts, atomically: true, encoding: .utf8)
    }

    public func reconnect() async throws { _ = try await start() }

    public func disconnect() async {
        _ = try? await runner.run("/usr/bin/ssh", ["-O", "exit"] + connectionOptions + [target], input: "", environment: [:])
    }

    // MARK: FileSystem

    public func exists(_ url: URL) async -> Bool { await RemoteTree.exists(url, in: self) }

    public func list(_ folder: URL) async throws -> [FolderItem] {
        let path = RemoteURL.canonical(folder).path
        let result = try await sftp("ls -ln \(SFTPText.quote(path))")
        return SFTPText.parseListing(result.stdout, folder: folder, now: now())
    }

    public func copy(_ source: URL, to destination: URL) async throws { throw RemoteError.other("not supported") }
    public func move(_ source: URL, to destination: URL) async throws {
        _ = try await sftp("rename \(SFTPText.quote(path(source))) \(SFTPText.quote(path(destination)))")
    }
    public func trash(_ url: URL) async throws -> URL? { throw RemoteError.other("not supported") }

    public func makeFolder(_ url: URL) async throws {
        _ = try await sftp("mkdir \(SFTPText.quote(path(url)))")
    }

    /// A file, or a folder with everything in it (`sftp` only removes empty folders, so it is emptied first).
    public func remove(_ url: URL) async throws {
        try await RemoteTree.remove(url, in: self,
                                    file: { _ = try await self.sftp("rm \(SFTPText.quote(self.path($0)))") },
                                    emptyFolder: { _ = try await self.sftp("rmdir \(SFTPText.quote(self.path($0)))") })
    }

    public func download(_ remote: URL, to local: URL, progress: @escaping ByteProgress) async throws {
        let watcher = FileGrowth.watch(local, progress: progress)
        defer { watcher.cancel() }
        _ = try await sftp("get \(SFTPText.quote(path(remote))) \(SFTPText.quote(local.path))")
    }

    /// Sends to a hidden name, then renames it into place, so the real name only ever holds a whole file.
    /// A failure or a cancel removes the hidden file. `sftp` does not report progress, so it shows at the end.
    public func upload(_ local: URL, to remote: URL, replacing: Bool, progress: @escaping ByteProgress) async throws {
        let final = path(remote)
        let folder = path(RemoteURL.parent(of: remote) ?? remote)
        let part = (folder == "/" ? "" : folder) + "/.\(RemoteURL.name(of: remote)).pane-part-\(UUID().uuidString)"
        var commands = ["put \(SFTPText.quote(local.path)) \(SFTPText.quote(part))"]
        // A leading "-" lets a command fail without stopping the rest.
        if replacing { commands.append("-rm \(SFTPText.quote(final))") }
        commands.append("rename \(SFTPText.quote(part)) \(SFTPText.quote(final))")
        do {
            _ = try await sftp(commands.joined(separator: "\n"))
        } catch {
            // A cancelled task cannot run more work, so the clean-up runs on its own.
            await Task.detached { _ = try? await self.sftp("-rm \(SFTPText.quote(part))") }.value
            throw error
        }
        progress((try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0)
    }

    private func path(_ url: URL) -> String { RemoteURL.canonical(url).path }

    // MARK: Running sftp

    private var target: String { "\(user)@\(host)" }

    private var connectionOptions: [String] {
        let socket = workFolder.appending(path: "%C").path
        var options = ["-o", "ControlMaster=auto", "-o", "ControlPath=\(socket)", "-o", "ControlPersist=120"]
        if let port { options += ["-p", String(port)] }
        return options
    }

    private var secret: String {
        switch login {
        case .password(let text): text
        case .key(_, let passphrase): passphrase
        }
    }

    private func sftp(_ command: String) async throws -> ProcessResult {
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let helper = workFolder.appending(path: "askpass.sh")
        try "#!/bin/sh\nprintf '%s\\n' \"$PANE_SFTP_SECRET\"\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

        var options = ["-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\(knownHosts.path)",
                       "-o", "GlobalKnownHostsFile=/dev/null", "-o", "ConnectTimeout=15"] + connectionOptions
        switch login {
        case .password:
            options += ["-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "PubkeyAuthentication=no"]
        case .key(let path, _):
            options += ["-i", path, "-o", "IdentitiesOnly=yes", "-o", "PreferredAuthentications=publickey"]
        }
        // With no secret to give, never wait for a prompt nobody will answer.
        if secret.isEmpty { options += ["-o", "BatchMode=yes"] }
        // The secret travels in the environment of this one child, never in its arguments.
        let environment = ["SSH_ASKPASS": helper.path, "SSH_ASKPASS_REQUIRE": "force", "DISPLAY": ":0", "PANE_SFTP_SECRET": secret]
        let result = try await runner.run("/usr/bin/sftp", options + ["-b", "-", target], input: command + "\n", environment: environment)
        guard result.status == 0 else { throw try await failure(result.stderr) }
        return result
    }

    /// An unknown host becomes a question for the person, with the key's fingerprint to compare.
    private func failure(_ stderr: String) async throws -> RemoteError {
        let error = SFTPText.classify(stderr: stderr)
        guard error == .other("host key unknown") else { return error }
        var scan = ["-T", "10"]
        if let port { scan += ["-p", String(port)] }
        let keys = try await runner.run("/usr/bin/ssh-keyscan", scan + [host], input: "", environment: [:])
        guard let line = SFTPText.preferredKeyLine(fromKeyscan: keys.stdout) else { return .connectionLost }
        let printed = try await runner.run("/usr/bin/ssh-keygen", ["-lf", "-"], input: line + "\n", environment: [:])
        return .unknownHostKey(fingerprint: SFTPText.fingerprint(fromKeygen: printed.stdout) ?? "unknown", keyLine: line)
    }
}
