import Foundation
import Testing
@testable import PaneKit

// MARK: SFTP (S-062)

@Test func sftpListingReadsSpacesNonASCIIAndLinks() {
    let output = """
    sftp> ls -ln "/srv/My Docs"
    drwxr-xr-x    2 1000     1000         4096 Oct 30 09:15 Año nuevo
    -rw-r--r--    1 1000     1000       118000 Mar  3  2024 Budget 2026.xlsx
    -rw-r--r--    1 1000     1000          204 Dec 25 08:00 notes.txt
    lrwxrwxrwx    1 0        0              11 Jan  1 10:00 www -> /var/www
    drwxr-xr-x    5 1000     1000         4096 Oct 30 09:15 .
    """
    let items = SFTPText.parseListing(output, folder: URL(string: "sftp://nas/srv/My%20Docs")!,
                                      now: ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!)
    #expect(items.map(\.name) == ["Año nuevo", "Budget 2026.xlsx", "notes.txt", "www"])
    #expect(items[0].isFolder && items[0].size == nil)
    #expect(items[1].size == 118000 && !items[1].isFolder)
    #expect(items[0].url.path == "/srv/My Docs/Año nuevo" && RemoteURL.name(of: items[0].url) == "Año nuevo")
    let year = { (item: FolderItem) in Calendar(identifier: .gregorian).component(.year, from: item.modified!) }
    #expect(year(items[1]) == 2024 && year(items[2]) == 2025)   // Dec 25 is in the future this year, so last year
}

@Test func sftpQuotingKeepsOddPathsInOnePiece() {
    #expect(SFTPText.quote("/a b/é") == "\"/a b/é\"")
    #expect(SFTPText.quote("/say \"hi\"\\") == "\"/say \\\"hi\\\"\\\\\"")
}

@Test func sshFailuresBecomeWordsAPersonCanUse() {
    #expect(SFTPText.classify(stderr: "me@nas: Permission denied (publickey,password).") == .denied("Access denied."))
    #expect(SFTPText.classify(stderr: "@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@\nHost key verification failed.") == .hostKeyChanged)
    #expect(SFTPText.classify(stderr: "ssh: connect to host nas port 22: Connection refused") == .connectionLost)
    #expect(SFTPText.fingerprint(fromKeygen: "256 SHA256:abcDEF nas (ED25519)") == "SHA256:abcDEF")
}

@Test func sftpListsThroughOneBatchAndKeepsTheSecretOutOfArguments() async throws {
    let runner = ScriptedRunner { _, _, _ in
        ProcessResult(stdout: "drwxr-xr-x 2 1 1 4096 Oct 30 09:15 Photos\n-rw-r--r-- 1 1 1 5 Oct 30 09:15 a.txt\n", stderr: "", status: 0)
    }
    let system = sftpSystem(runner)
    #expect(system.serverKey == "sftp://nas.local")
    let items = try await system.list(URL(string: "sftp://nas.local/srv/My%20Docs")!)
    #expect(items.map(\.name) == ["Photos", "a.txt"])
    let call = try #require(runner.calls.first)
    #expect(call.exe == "/usr/bin/sftp" && call.input == "ls -ln \"/srv/My Docs\"\n")
    #expect(call.env["PANE_SFTP_SECRET"] == "pw" && !call.args.joined().contains("pw"))
    #expect(call.args.contains("StrictHostKeyChecking=yes") && call.args.contains("me@nas.local") && !call.args.contains("BatchMode=yes"))
}

@Test func sftpKeyLoginNamesTheKeyAndNeverPromptsWithoutAPassphrase() async throws {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "Remote working directory: /home/me\n", stderr: "", status: 0) }
    let home = try await sftpSystem(runner, login: .key(path: "/Users/me/.ssh/id_ed25519", passphrase: "")).start()
    #expect(home == "/home/me")
    let args = try #require(runner.calls.first).args
    #expect(args.contains("/Users/me/.ssh/id_ed25519") && args.contains("BatchMode=yes") && args.contains("IdentitiesOnly=yes"))
}

@Test func sftpAsksBeforeTrustingANewServerThenRemembersIt() async throws {
    let known = FileManager.default.temporaryDirectory.appending(path: "pane-kh-\(UUID().uuidString)")
    let trusted = Box()
    let runner = ScriptedRunner { exe, _, _ in
        switch exe {
        case "/usr/bin/ssh-keyscan": return ProcessResult(stdout: "# nas.local\nnas.local ssh-rsa AAAArsa\nnas.local ssh-ed25519 AAAAed\n", stderr: "", status: 0)
        case "/usr/bin/ssh-keygen": return ProcessResult(stdout: "256 SHA256:fp123 nas.local (ED25519)\n", stderr: "", status: 0)
        default:
            return trusted.value
                ? ProcessResult(stdout: "Remote working directory: /\n", stderr: "", status: 0)
                : ProcessResult(stdout: "", stderr: "No ED25519 host key is known for nas.local and you have requested strict checking.\nHost key verification failed.\n", status: 255)
        }
    }
    let system = sftpSystem(runner, known: known)
    await #expect(throws: RemoteError.unknownHostKey(fingerprint: "SHA256:fp123", keyLine: "nas.local ssh-ed25519 AAAAed")) { try await system.start() }
    try system.trust(keyLine: "nas.local ssh-ed25519 AAAAed")
    trusted.value = true
    #expect(try await system.start() == "/")
    #expect(try String(contentsOf: known, encoding: .utf8) == "nas.local ssh-ed25519 AAAAed\n")
}

@Test func sftpStopsWhenAKnownServersKeyChanges() async {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "", stderr: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\nHost key verification failed.\n", status: 255) }
    await #expect(throws: RemoteError.hostKeyChanged) { try await sftpSystem(runner).start() }
    #expect(runner.calls.allSatisfy { $0.exe == "/usr/bin/sftp" })   // it never looks for a key to trust
}

final class Box: @unchecked Sendable { var value = false }
