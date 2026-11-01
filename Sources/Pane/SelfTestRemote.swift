import AppKit
import PaneKit

/// Self-test: servers (S-060 to S-067). Today: browsing a server like a folder. A server in memory
/// stands in for a real one, so nothing touches a network.
extension SelfTest {
    static func remote(_ c: Context) async {
        let model = c.model
        @MainActor func settle() async { await Wait.settle(c.model) }

        // S-060 Browse a remote place like a folder
        let nas = InMemoryRemote(serverKey: "sftp://nas")
        nas.add(folder: "/Docs"); nas.add(folder: "/archive")
        nas.add(file: "/file10.txt", size: 2048); nas.add(file: "/file2.txt"); nas.add(file: "/Docs/plan.txt")
        model.connected(nas)
        check("a connected server shows under Connections", model.places.connectionRoots.map(\.name) == ["nas (SFTP)"], "\(model.places.connectionRoots.map(\.name))")
        let top = URL(string: "sftp://nas/")!
        check("a server's row has no folders under it, and never lists this Mac's", model.places.connectionRoots.first?.children == nil)
        model.tab.go(to: top)
        await settle()
        check("a server's folder lists folders first, in natural order, like a local one",
              model.tab.items.map(\.name) == ["archive", "Docs", "file2.txt", "file10.txt"], "\(model.tab.items.map(\.name))")
        check("items carry their server address", model.tab.items.first?.url.absoluteString == "sftp://nas/archive")
        check("a server's top is named for the server", model.tab.currentName == "nas")
        check("the tree selects the server's row", model.places.navSelection == "conn:sftp://nas/", model.places.navSelection ?? "nil")
        check("a server tab does not watch or poll", model.tab.isRemote && model.tab.pollInterval == nil)
        let docs = model.tab.items.first { $0.name == "Docs" }!.url
        model.tab.open([docs])
        await settle()
        check("opening a server folder shows it", model.tab.currentFolder.absoluteString == "sftp://nas/Docs" && model.tab.items.map(\.name) == ["plan.txt"])
        check("the breadcrumbs run from the server down", Breadcrumbs.chain(for: model.tab.currentFolder).map { Locations.displayName(for: $0) } == ["nas", "Docs"])
        check("Go up works on a server", model.tab.canGoUp)
        model.tab.goUp()
        await settle()
        check("and returns to the server's top", model.tab.currentFolder.absoluteString == "sftp://nas/")

        model.beginEditingAddress()
        check("the Address bar shows a server address", model.addressText == "sftp://nas/", model.addressText)
        model.addressText = "sftp://other/x"
        model.commitAddress()
        check("a server that is not connected is refused with a way forward",
              model.addressError == "Not connected to that server. Use Go > Connect to Server.", model.addressError ?? "nil")
        model.addressText = "sftp://nas/archive"
        model.commitAddress()
        await settle()
        check("a typed server address goes there", model.tab.currentFolder.absoluteString == "sftp://nas/archive")
        model.cancelEditingAddress()

        model.tab.go(to: URL(string: "sftp://ghost/")!)
        await settle()
        check("a server with no open connection says so", model.tab.loadProblem == .notConnected && model.tab.loadError == "Not connected to this server.")

        nas.slowDown(by: .seconds(3))
        model.tab.go(to: docs)
        await Wait.until(2) { model.tab.isSlow }
        check("going into a server's folder is not undone by the tree's selection", model.tab.currentFolder == docs, model.tab.currentFolder.absoluteString)
        check("a slow folder shows Loading… after half a second", model.tab.isSlow)
                model.tab.cancelLoad()
        nas.slowDown(by: .zero)
        await settle()
        check("Cancel stops waiting and goes back, and the slow answer is ignored",
              !model.tab.isLoading && model.tab.currentFolder != docs && !model.tab.items.contains { $0.name == "plan.txt" },
              "\(model.tab.currentFolder.absoluteString) \(model.tab.items.map(\.name))")

        model.tab.go(to: top)
        await settle()
        nas.dropConnection()
        model.tab.reload()
        await settle()
        check("a dropped connection says so and keeps the last list, dimmed",
              model.tab.loadProblem == .connectionLost && model.tab.loadError == "Connection lost." && model.tab.isStale && !model.tab.items.isEmpty)
        model.tab.reconnect()
        await Wait.until { !model.tab.isStale }
        await settle()
        check("Reconnect brings the list back", !model.tab.isStale && model.tab.loadProblem == nil && model.tab.items.count == 4)

        model.tab.selection = Set(model.tab.items.prefix(1).map(\.url))
        model.actions.trashSelection()
        check("changing files on a server is blocked, with a message", model.actions.alertMessage?.contains("later step") == true)
        model.actions.alertMessage = nil
        model.actions.newFolder()
        check("so is New Folder", model.actions.alertMessage?.contains("later step") == true)
        model.actions.alertMessage = nil
        model.actions.drop([c.docs.appending(path: "Notes.txt")], into: top, option: false, command: false)
        check("so is dropping a local file onto a server", model.actions.alertMessage?.contains("later step") == true)
        model.actions.alertMessage = nil
        check("no local file was touched by any of that", FileManager.default.fileExists(atPath: c.docs.appending(path: "Notes.txt").path))

        model.disconnect(serverKey: "sftp://nas")
        await settle()
        check("Eject on a server closes it and removes its row", model.router.serverKeys.isEmpty && model.places.connectionRoots.isEmpty)
        check("a tab that was on it goes home", !model.tab.isRemote)
        model.tab.go(to: c.docs)
        await settle()

        // S-063 Connect to an S3 account (a stub stands in for the network and the Keychain)
        let s3Log = S3Log()
        model.connections.makeS3 = { endpoint, region, credentials in
            S3FileSystem(endpoint: endpoint, region: region, credentials: credentials, transport: StubS3(goodKey: "GOODKEY"))
        }
        model.connections.saveSecret = { _, server, account in s3Log.saved.append("\(server)/\(account)") }
        model.connections.savedSecret = { _, account in account == "GOODKEY" ? "stored-secret" : nil }
        model.connections.openConnectSheet()
        model.connections.connectS3(accessKey: "", secretKey: "x", region: "us-east-1", endpoint: "", remember: false)
        check("S3 asks for the access key", model.connections.connectError == "Type the access key.")
        model.connections.connectS3(accessKey: "GOODKEY", secretKey: "", region: "us-east-1", endpoint: "", remember: false)
        await Wait.until { !model.connections.isConnecting && !model.connections.showConnectSheet }
        check("a secret saved earlier is used when the field is empty", model.router.serverKeys == ["s3://s3.us-east-1.amazonaws.com"], "\(model.router.serverKeys)")
        model.disconnect(serverKey: "s3://s3.us-east-1.amazonaws.com")
        model.connections.openConnectSheet()
        model.connections.connectS3(accessKey: "WRONG", secretKey: "nope", region: "us-east-1", endpoint: "", remember: true)
        await Wait.until { !model.connections.isConnecting }
        check("a wrong key says Access denied. and keeps the sheet open",
              model.connections.connectError == "Access denied." && model.connections.showConnectSheet && model.router.serverKeys.isEmpty,
              model.connections.connectError ?? "nil")
        check("a wrong key is not saved to the Keychain", s3Log.saved.isEmpty)
        model.connections.connectS3(accessKey: "GOODKEY", secretKey: "secret", region: "eu-west-1", endpoint: "https://minio.local:9000/", remember: true)
        await Wait.until { !model.connections.isConnecting && !model.connections.showConnectSheet }
        await settle()
        check("a good key closes the sheet and shows the buckets as folders",
              !model.connections.showConnectSheet && model.tab.isRemote && model.tab.items.map(\.name) == ["photos"] && model.tab.items.first?.isFolder == true,
              "\(model.tab.currentFolder) \(model.tab.items.map(\.name))")
        check("the endpoint decides the server", model.router.serverKeys == ["s3://minio.local:9000"], "\(model.router.serverKeys)")
        check("Remember saves the secret under the endpoint and key", s3Log.saved == ["minio.local:9000/GOODKEY"], "\(s3Log.saved)")
        model.disconnect(serverKey: "s3://minio.local:9000")
        await settle()

        // S-062 Connect to an SFTP server (a script stands in for sftp, ssh-keyscan, and the Keychain)
        let known = c.home.appending(path: "sftp-known-hosts")
        try? FileManager.default.removeItem(at: known)
        let sftpLog = S3Log()
        model.connections.makeSFTP = { host, port, user, login in
            SFTPFileSystem(host: host, port: port, user: user, login: login, knownHosts: known,
                           workFolder: URL(fileURLWithPath: "/tmp/pane-ssh-selftest"), runner: ScriptedSFTP(known: known))
        }
        model.connections.saveSSHSecret = { _, server, account in sftpLog.saved.append("\(server)/\(account)") }
        model.connections.savedSSHSecret = { _, _ in nil }
        model.connections.openConnectSheet()
        model.connections.connectSFTP(host: "", port: "", user: "me", useKey: false, keyPath: "", secret: "pw", remember: false)
        check("SFTP asks for the server name", model.connections.connectError == "Type the server name, like nas.local.")
        model.connections.connectSFTP(host: "nas.local", port: "99999", user: "me", useKey: false, keyPath: "", secret: "pw", remember: false)
        check("SFTP checks the port", model.connections.connectError == "The port is a number from 1 to 65535.")
        model.connections.connectSFTP(host: "nas.local", port: "", user: "", useKey: false, keyPath: "", secret: "pw", remember: false)
        check("SFTP asks for the user name", model.connections.connectError == "Type the user name.")
        model.connections.connectSFTP(host: "nas.local", port: "", user: "me", useKey: true, keyPath: "", secret: "", remember: false)
        check("SFTP with a key asks for the key file", model.connections.connectError == "Choose a key file.")
        model.connections.connectSFTP(host: "nas.local", port: "", user: "me", useKey: false, keyPath: "", secret: "", remember: false)
        check("SFTP with a password asks for it", model.connections.connectError == "Type the password.")

        model.connections.connectSFTP(host: "nas.local", port: "", user: "me", useKey: false, keyPath: "", secret: "pw", remember: true)
        await Wait.until { !model.connections.isConnecting }
        check("a server not seen before asks Trust this server? with its fingerprint",
              model.connections.pendingTrust?.fingerprint == "SHA256:fp123" && model.connections.showConnectSheet && model.router.serverKeys.isEmpty,
              "\(String(describing: model.connections.pendingTrust))")
        check("nothing is saved or trusted until the person says so",
              sftpLog.saved.isEmpty && !FileManager.default.fileExists(atPath: known.path))
        model.connections.declinePendingServer()
        check("Don't Trust closes the question and connects to nothing", model.connections.pendingTrust == nil && model.router.serverKeys.isEmpty)

        model.connections.connectSFTP(host: "nas.local", port: "", user: "me", useKey: false, keyPath: "", secret: "pw", remember: true)
        await Wait.until { model.connections.pendingTrust != nil }
        model.connections.trustPendingServer()
        await Wait.until { !model.connections.isConnecting && !model.connections.showConnectSheet }
        await settle()
        check("Trust remembers the key, connects, and opens the server's starting folder",
              model.router.serverKeys == ["sftp://nas.local"] && model.tab.currentFolder.path == "/home/me",
              "\(model.router.serverKeys) \(model.tab.currentFolder)")
        check("the folder lists folders and files from the server", model.tab.items.map(\.name) == ["My Docs", "notes.txt"], "\(model.tab.items.map(\.name))")
        check("the key is in Pane's own list, not ~/.ssh", ((try? String(contentsOf: known, encoding: .utf8)) ?? "").contains("ssh-ed25519 AAAAed"))
        check("Remember saves the password under the server and user", sftpLog.saved == ["nas.local/me"], "\(sftpLog.saved)")
        model.disconnect(serverKey: "sftp://nas.local")
        await settle()

        model.connections.openConnectSheet()
        model.connections.connectSFTP(host: "changed.local", port: "", user: "me", useKey: false, keyPath: "", secret: "pw", remember: true)
        await Wait.until { !model.connections.isConnecting }
        check("a changed key stops with a warning and offers no way past it",
              model.connections.connectError?.contains("key changed") == true && model.connections.pendingTrust == nil && model.router.serverKeys.isEmpty,
              model.connections.connectError ?? "nil")
        model.connections.connectSFTP(host: "deny.local", port: "", user: "me", useKey: false, keyPath: "", secret: "wrong", remember: true)
        await Wait.until { !model.connections.isConnecting }
        check("a wrong password says Access denied. and saves nothing", model.connections.connectError == "Access denied." && sftpLog.saved == ["nas.local/me"])
        model.connections.closeConnectSheet()
        model.tab.go(to: c.docs)
        await settle()
    }
}

/// Answers like `sftp`, `ssh-keyscan`, and `ssh-keygen` for three pretend servers.
private struct ScriptedSFTP: ProcessRunner {
    let known: URL
    func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) async throws -> ProcessResult {
        switch executable {
        case "/usr/bin/ssh-keyscan":
            return ProcessResult(stdout: "nas.local ssh-ed25519 AAAAed\n", stderr: "", status: 0)
        case "/usr/bin/ssh-keygen":
            return ProcessResult(stdout: "256 SHA256:fp123 nas.local (ED25519)\n", stderr: "", status: 0)
        case "/usr/bin/ssh":
            return ProcessResult(stdout: "", stderr: "", status: 0)
        default:
            let target = arguments.last ?? ""
            if target.hasSuffix("@changed.local") {
                return ProcessResult(stdout: "", stderr: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\nHost key verification failed.\n", status: 255)
            }
            if target.hasSuffix("@deny.local") {
                return ProcessResult(stdout: "", stderr: "me@deny.local: Permission denied (password).\n", status: 255)
            }
            let trusted = ((try? String(contentsOf: known, encoding: .utf8)) ?? "").contains("nas.local ssh-ed25519")
            guard trusted else {
                return ProcessResult(stdout: "", stderr: "No ED25519 host key is known for nas.local and you have requested strict checking.\nHost key verification failed.\n", status: 255)
            }
            if input.hasPrefix("pwd") { return ProcessResult(stdout: "Remote working directory: /home/me\n", stderr: "", status: 0) }
            return ProcessResult(stdout: "sftp> ls\ndrwxr-xr-x 2 1 1 4096 Oct 30 09:15 My Docs\n-rw-r--r-- 1 1 1 5 Oct 30 09:15 notes.txt\n", stderr: "", status: 0)
        }
    }
}

private final class S3Log {
    var saved: [String] = []
}

/// Answers like S3 does: buckets for the good key, "InvalidAccessKeyId" for any other.
private struct StubS3: S3Transport {
    let goodKey: String
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let ok = auth.contains("Credential=\(goodKey)/")
        let body = ok
            ? "<ListAllMyBucketsResult><Buckets><Bucket><Name>photos</Name><CreationDate>2026-01-01T00:00:00.000Z</CreationDate></Bucket></Buckets></ListAllMyBucketsResult>"
            : "<Error><Code>InvalidAccessKeyId</Code><Message>The access key does not exist.</Message></Error>"
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: ok ? 200 : 403, httpVersion: nil, headerFields: nil)!)
    }
}
