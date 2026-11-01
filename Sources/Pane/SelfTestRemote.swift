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
        check("Delete on a server asks first, and has deleted nothing", model.actions.pendingDelete?.count == 1 && model.tab.items.count == 4)
        model.actions.pendingDelete = nil
        check("no local file was touched by any of that", FileManager.default.fileExists(atPath: c.docs.appending(path: "Notes.txt").path))

        model.disconnect(serverKey: "sftp://nas")
        await settle()
        check("Eject on a server closes it and removes its row", model.router.serverKeys.isEmpty && model.places.connectionRoots.isEmpty)
        check("a tab that was on it goes home", !model.tab.isRemote)
        model.tab.go(to: c.docs)
        await settle()

        // S-063 Connect to an S3 account (a stub stands in for the network and the Keychain)
        // One stand-in for the network and one for the Keychain serve every connect check below.
        let known = c.home.appending(path: "sftp-known-hosts")
        try? FileManager.default.removeItem(at: known)
        let secrets = InMemorySecretStore()
        secrets.preload("stored-secret", forKey: "s3://s3.us-east-1.amazonaws.com/GOODKEY")
        secrets.preload("stored-secret", forKey: "s3://minio2.local:9000/GOODKEY")
        secrets.preload("stored-secret", forKey: "s3://down.local/GOODKEY")
        model.connections.secrets = secrets
        model.connections.makeServer = { valid in
            let connection = valid.connection
            switch connection.kind {
            case .s3:
                return S3FileSystem(endpoint: valid.endpoint, region: connection.region ?? "us-east-1",
                                    credentials: .init(accessKey: connection.user, secretKey: valid.secret),
                                    transport: StubS3(goodKey: "GOODKEY", down: connection.host.hasPrefix("down")))
            case .sftp:
                return SFTPFileSystem(host: connection.host, port: connection.port, user: connection.user,
                                      login: connection.useKey ? .key(path: connection.keyPath ?? "", passphrase: valid.secret) : .password(valid.secret),
                                      knownHosts: known, workFolder: URL(fileURLWithPath: "/tmp/pane-ssh-selftest"), runner: ScriptedSFTP(known: known))
            case .ftp, .ftps:
                return FTPFileSystem(host: connection.host, port: connection.port, user: connection.user, password: valid.secret,
                                     secure: connection.kind == .ftps, runner: ScriptedFTP(goodPassword: "ftp-pw"))
            }
        }
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
        check("a wrong key is not saved to the Keychain", secrets.savedKeys.isEmpty)
        model.connections.connectS3(accessKey: "GOODKEY", secretKey: "secret", region: "eu-west-1", endpoint: "https://minio.local:9000/", remember: true)
        await Wait.until { !model.connections.isConnecting && !model.connections.showConnectSheet }
        await settle()
        check("a good key closes the sheet and shows the buckets as folders",
              !model.connections.showConnectSheet && model.tab.isRemote && model.tab.items.map(\.name) == ["photos"] && model.tab.items.first?.isFolder == true,
              "\(model.tab.currentFolder) \(model.tab.items.map(\.name))")
        check("the endpoint decides the server", model.router.serverKeys == ["s3://minio.local:9000"], "\(model.router.serverKeys)")
        check("Remember saves the secret under the endpoint and key", secrets.savedKeys == ["s3://minio.local:9000/GOODKEY"], "\(secrets.savedKeys)")
        model.disconnect(serverKey: "s3://minio.local:9000")
        await settle()

        // S-062 Connect to an SFTP server (a script stands in for sftp, ssh-keyscan, and the Keychain)
        let sftpBase = secrets.savedKeys.count
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
              secrets.savedKeys.count == sftpBase && !FileManager.default.fileExists(atPath: known.path))
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
        check("Remember saves the password under the server and user", Array(secrets.savedKeys.dropFirst(sftpBase)) == ["sftp://nas.local/me"], "\(secrets.savedKeys)")
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
        check("a wrong password says Access denied. and saves nothing", model.connections.connectError == "Access denied." && Array(secrets.savedKeys.dropFirst(sftpBase)) == ["sftp://nas.local/me"])
        model.connections.closeConnectSheet()

        // S-061 Connect to an FTP server (a script stands in for curl and the Keychain)
        let ftpBase = secrets.savedKeys.count
        check("FTP with TLS is the first choice", Connections.FTPProtocol.allCases.first == .tls && model.connections.ftpProtocol == .tls)
        check("plain FTP says it sends the password without encryption", Connections.FTPProtocol.plain.note == "FTP sends your password without encryption.")
        check("FTP with TLS shows no such note", Connections.FTPProtocol.tls.note == nil)
        model.connections.openConnectSheet()
        model.connections.connectFTP(host: "ftp.example.com", port: "", user: "me", password: "wrong", protocol: .tls, remember: true)
        await Wait.until { !model.connections.isConnecting }
        check("a wrong FTP password says Access denied. and saves nothing", model.connections.connectError == "Access denied." && secrets.savedKeys.count == ftpBase)
        model.connections.connectFTP(host: "ftp.example.com", port: "", user: "me", password: "", protocol: .tls, remember: false)
        check("FTP asks for the password", model.connections.connectError == "Type the password.")
        model.connections.connectFTP(host: "ftp.example.com", port: "2121", user: "me", password: "ftp-pw", protocol: .tls, remember: true)
        await Wait.until { !model.connections.isConnecting && !model.connections.showConnectSheet }
        await settle()
        check("FTP with TLS connects, lists the top folder, and keeps the address", model.router.serverKeys == ["ftps://ftp.example.com:2121"] && model.tab.items.map(\.name) == ["Public", "readme.txt"],
              "\(model.router.serverKeys) \(model.tab.items.map(\.name))")
        check("Remember saves the password under the server and user", Array(secrets.savedKeys.dropFirst(ftpBase)) == ["ftps://ftp.example.com:2121/me"], "\(secrets.savedKeys)")
        model.disconnect(serverKey: "ftps://ftp.example.com:2121")
        await settle()

        // S-064 Copy between this Mac and a server (a server in memory, with real bytes)
        let box = InMemoryRemote(serverKey: "sftp://xfer")
        let payload = Data((0..<4000).map { UInt8($0 % 241) })
        box.add(folder: "/Inbox"); box.add(folder: "/Outbox"); box.add(file: "/Inbox/report.pdf", contents: payload)
        model.connected(box)
        let mine = c.home.appending(path: "Transfers", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: mine)
        try? FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        let photo = mine.appending(path: "photo.jpg")
        try? payload.write(to: photo)
        @MainActor func idle() async { await Wait.until { !model.actions.isBusy }; await settle() }
        @MainActor func place(_ path: String) -> URL { RemoteURL.make(scheme: "sftp", host: "xfer", path: path) }

        // this Mac to a server, through Copy and Paste
        model.tab.go(to: mine); await settle()
        model.tab.selection = [photo]
        model.actions.copySelection()
        model.tab.go(to: place("/Outbox")); await settle()
        check("Paste lights up for files from this Mac in a server's folder", model.actions.canPaste)
        model.actions.paste()
        await idle()
        check("a file pasted into a server arrives and matches byte for byte", box.data(at: "/Outbox/photo.jpg") == payload)
        check("the server's folder lists it", model.tab.items.map(\.name) == ["photo.jpg"], "\(model.tab.items.map(\.name))")
        check("the original stays after a copy", FileManager.default.fileExists(atPath: photo.path))

        // the same name again asks the same question
        model.tab.selection = []
        model.tab.go(to: mine); await settle()
        model.tab.selection = [photo]
        model.actions.copySelection()
        model.tab.go(to: place("/Outbox")); await settle()
        model.actions.paste()
        await Wait.until { model.actions.pendingConflict != nil }
        check("a name already on the server opens the Replace, Skip, Keep Both sheet with the server's file shown",
              model.actions.pendingConflict?.existing?.size == 4000 && model.actions.pendingConflict?.conflict.existing.path == "/Outbox/photo.jpg")
        model.actions.resolveConflict(.keepBoth, applyToAll: false)
        await idle()
        check("Keep Both adds a numbered copy beside it", Set(box.paths()).isSuperset(of: ["/Outbox/photo.jpg", "/Outbox/photo (2).jpg"]), "\(box.paths())")

        // a server to this Mac, through a drop
        let inbox = mine.appending(path: "Inbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        model.actions.drop([place("/Inbox/report.pdf")], into: inbox, option: false, command: false)
        await idle()
        check("a file dropped from a server arrives and matches byte for byte", (try? Data(contentsOf: inbox.appending(path: "report.pdf"))) == payload)
        check("no part file is left beside it", ((try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []) == ["report.pdf"])
        check("a server's folder is never pinned to Quick access", { model.places.pin(place("/Inbox")); return !model.places.quickRoots.contains { $0.url.scheme == "sftp" } }())

        // Cut from a server removes the original only after the copy
        model.tab.go(to: place("/Inbox")); await settle()
        model.tab.selection = [place("/Inbox/report.pdf")]
        model.actions.cutSelection()
        check("an item cut on a server shows as cut", model.actions.isCut(place("/Inbox/report.pdf")))
        let desk = mine.appending(path: "Moved", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: desk, withIntermediateDirectories: true)
        model.tab.go(to: desk); await settle()
        model.actions.paste()
        await idle()
        check("Cut then Paste moves it here and removes it from the server",
              (try? Data(contentsOf: desk.appending(path: "report.pdf"))) == payload && box.data(at: "/Inbox/report.pdf") == nil)

        // a failed copy keeps its original, and a failed Cut keeps it too
        box.add(file: "/Inbox/flaky.bin", contents: Data(repeating: 3, count: 3000))
        box.failTransfers(of: ["/Inbox/flaky.bin"])
        model.actions.drop([place("/Inbox/flaky.bin")], into: desk, option: false, command: true)
        await idle()
        check("a copy that fails midway leaves no half file and keeps the original on the server",
              box.data(at: "/Inbox/flaky.bin") != nil && !FileManager.default.fileExists(atPath: desk.appending(path: "flaky.bin").path)
              && ((try? FileManager.default.contentsOfDirectory(atPath: desk.path)) ?? []).sorted() == ["report.pdf"],
              "\(String(describing: try? FileManager.default.contentsOfDirectory(atPath: desk.path)))")
        check("and says what went wrong", model.actions.alertMessage?.contains("Unable to reach the server") == true, model.actions.alertMessage ?? "nil")
        model.actions.alertMessage = nil
        box.failTransfers(of: [])

        // a long copy shows the file, bytes, speed and time left, and Cancel stops it with nothing left behind
        box.add(file: "/Inbox/big.bin", contents: Data(repeating: 5, count: 60_000))
        box.slowTransfers(by: .milliseconds(25))
        model.actions.drop([place("/Inbox/big.bin")], into: desk, option: true, command: false)
        await Wait.until(5) { model.actions.progress?.bytesDone ?? 0 > 4_000 }
        check("a long copy reports the file and its bytes", model.actions.progress?.current == "big.bin" && (model.actions.progress?.bytesTotal ?? 0) == 60_000,
              "\(String(describing: model.actions.progress))")
        await Wait.until(5) { model.actions.progressDetail.contains("/s") }
        check("and the speed and time left", model.actions.progressDetail.contains(" of ") && model.actions.progressDetail.contains("/s") && model.actions.progressDetail.contains("left"),
              model.actions.progressDetail)
        model.actions.cancelOperation()
        await idle()
        check("Cancel stops it and leaves no half file", !FileManager.default.fileExists(atPath: desk.appending(path: "big.bin").path)
              && ((try? FileManager.default.contentsOfDirectory(atPath: desk.path)) ?? []).sorted() == ["report.pdf"])
        box.slowTransfers(by: .zero)

        // S-065 Change files on a server: New Folder, rename, and delete
        model.tab.go(to: place("/Inbox")); await settle()
        model.actions.newFolder()
        await idle()
        check("New Folder on a server makes the folder and starts naming it",
              box.paths().contains("/Inbox/New folder") && model.actions.renamingURL?.path == "/Inbox/New folder", "\(box.paths()) \(String(describing: model.actions.renamingURL))")
        model.actions.renameText = "Reports"
        model.actions.commitRename()
        await idle()
        check("renaming it renames it on the server", box.paths().contains("/Inbox/Reports") && !box.paths().contains("/Inbox/New folder"), "\(box.paths())")
        model.tab.selection = [place("/Inbox/flaky.bin")]
        check("F2 is available on a server's item", model.actions.canRename)
        model.actions.beginRename()
        model.actions.renameText = "keep.bin"
        model.actions.commitRename()
        await idle()
        check("renaming a file keeps its bytes", box.data(at: "/Inbox/keep.bin") == Data(repeating: 3, count: 3000) && box.data(at: "/Inbox/flaky.bin") == nil)
        model.tab.selection = [place("/Inbox/keep.bin")]
        model.actions.beginRename()
        model.actions.renameText = "big.bin"
        model.actions.commitRename()
        await Wait.until { model.actions.renameError != nil }
        check("a name already taken on the server says so", model.actions.renameError == "An item with this name already exists.", model.actions.renameError ?? "nil")
        model.actions.cancelRename()
        await settle()
        NSApp.keyWindow?.makeFirstResponder(nil)   // a cancelled rename field can keep focus, and Delete steps aside for a field

        model.tab.selection = [place("/Inbox/keep.bin"), place("/Inbox/big.bin"), place("/Inbox/Reports")]
        model.actions.trashSelection()
        check("Delete asks Delete 3 items from the server? with Delete and Cancel, and has deleted nothing",
              model.actions.deleteTitle == "Delete 3 items from xfer?" && model.actions.deleteButtonTitle == "Delete" && box.data(at: "/Inbox/big.bin") != nil,
              model.actions.deleteTitle)
        model.actions.pendingDelete = nil
        check("Cancel keeps everything", box.data(at: "/Inbox/big.bin") != nil && box.paths().contains("/Inbox/Reports"))
        model.actions.trashSelection()
        model.actions.deleteImmediately()
        await idle()
        check("Delete removes them from the server", box.data(at: "/Inbox/big.bin") == nil && box.data(at: "/Inbox/keep.bin") == nil && !box.paths().contains("/Inbox/Reports"), "\(box.paths())")
        check("the list updates", model.tab.items.isEmpty, "\(model.tab.items.map(\.name))")

        // S-066 Open and edit a file on a server (the app that opens it is faked)
        box.add(file: "/Inbox/Notes.txt", contents: Data("first draft".utf8))
        model.tab.go(to: place("/Inbox")); await settle()
        let opened = Opened()
        model.actions.openRemoteFile(place("/Inbox/Notes.txt"), open: { url in opened.url = url; return true })
        await Wait.until(5) { opened.url != nil }
        await idle()
        let copy = opened.url
        check("Return on a server file downloads it to a temporary folder and opens it",
              copy?.lastPathComponent == "Notes.txt" && (try? String(contentsOf: copy!, encoding: .utf8)) == "first draft" && copy?.path.contains("Pane-remote-") == true,
              "\(String(describing: copy))")
        check("the temporary copy is not in a folder the person browses", !(copy?.path.hasPrefix(c.home.path) ?? true))
        await model.actions.syncRemoteEdits()
        check("nothing is sent before a save", box.data(at: "/Inbox/Notes.txt") == Data("first draft".utf8) && model.actions.statusMessage == nil)
        if let copy {
            try? Data("second draft".utf8).write(to: copy)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: copy.path)
        }
        await model.actions.syncRemoteEdits()
        check("saving in the app sends the change to the server", box.data(at: "/Inbox/Notes.txt") == Data("second draft".utf8))
        check("and the Status bar says Uploaded Notes.txt", model.actions.statusMessage == "Uploaded Notes.txt", model.actions.statusMessage ?? "nil")

        box.add(file: "/Inbox/Notes.txt", contents: Data("edited by someone else".utf8))
        if let copy {
            try? Data("my third draft".utf8).write(to: copy)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: copy.path)
        }
        await model.actions.syncRemoteEdits()
        check("a file that changed on the server asks before it overwrites it",
              model.actions.pendingEditConflict?.name == "Notes.txt" && box.data(at: "/Inbox/Notes.txt") == Data("edited by someone else".utf8))
        model.actions.resolveEditConflict(replace: false)
        await model.actions.syncRemoteEdits()
        check("Not Now leaves both, and does not ask again until the next save",
              model.actions.pendingEditConflict == nil && box.data(at: "/Inbox/Notes.txt") == Data("edited by someone else".utf8))
        if let copy {
            try? Data("my fourth draft".utf8).write(to: copy)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(15)], ofItemAtPath: copy.path)
        }
        await model.actions.syncRemoteEdits()
        check("the next save asks again", model.actions.pendingEditConflict != nil)
        model.actions.resolveEditConflict(replace: true)
        await idle()
        check("Replace puts the person's version on the server", box.data(at: "/Inbox/Notes.txt") == Data("my fourth draft".utf8), String(describing: box.data(at: "/Inbox/Notes.txt").map { String(decoding: $0, as: UTF8.self) }))

        let folderOfCopy = copy?.deletingLastPathComponent().deletingLastPathComponent()
        model.actions.discardRemoteEditsForTest()
        check("the temporary copies are deleted", folderOfCopy.map { !FileManager.default.fileExists(atPath: $0.path) } ?? false && !model.actions.remoteEditCopiesExist)
        model.actions.openRemoteFile(place("/Inbox/missing.txt"), open: { _ in true })
        await idle()
        check("a file that is gone says so, and opens nothing", model.actions.alertMessage != nil)
        model.actions.alertMessage = nil

        // S-067 Save connections (stubs stand in for the network and the Keychain)
        let keptBase = secrets.savedKeys.count
        model.connections.openConnectSheet()
        model.connections.connectS3(accessKey: "GOODKEY", secretKey: "hunter2-secret-value", region: "eu-west-1", endpoint: "minio.local:9000", remember: true, save: true)
        await Wait.until { !model.connections.isConnecting && !model.connections.showConnectSheet }
        await settle()
        let minio = model.connections.saved.items.first
        check("Save this connection adds it to the list", model.connections.saved.items.count == 1 && minio?.serverKey == "s3://minio.local:9000" && minio?.region == "eu-west-1",
              "\(model.connections.saved.items)")
        let stored = String(decoding: Prefs.defaults.data(forKey: "pane.savedConnections") ?? Data(), as: UTF8.self)
        check("Settings hold the host, user name, and protocol, and no secret",
              stored.contains("minio.local") && stored.contains("GOODKEY") && stored.contains("s3") && !stored.contains("hunter2"))
        check("the secret went to the Keychain, under the server and key", Array(secrets.savedKeys.dropFirst(keptBase)) == ["s3://minio.local:9000/GOODKEY"], "\(secrets.savedKeys)")
        check("Connections lists it with its protocol icon, not dimmed while connected",
              model.places.connectionRoots.first?.savedID == minio?.id && model.places.connectionRoots.first?.symbol == "shippingbox" && model.places.connectionRoots.first?.isOffline == false)

        model.disconnect(serverKey: "s3://minio.local:9000")
        await settle()
        check("a saved server stays in the list, dimmed, when it is not connected",
              model.places.connectionRoots.first { $0.savedID == minio?.id }?.isOffline == true && !model.router.serverKeys.contains("s3://minio.local:9000"))
        model.connections.openSaved(serverKey: "s3://minio.local:9000")
        await Wait.until { model.router.serverKeys.contains("s3://minio.local:9000") }
        await settle()
        check("clicking it connects with the saved settings and the Keychain's secret, and shows it",
              model.router.serverKeys.contains("s3://minio.local:9000") && model.tab.isRemote && model.places.connectionRoots.first { $0.savedID == minio?.id }?.isOffline == false)

        model.connections.record(SavedConnection(kind: .s3, host: "down.local", user: "GOODKEY", region: "us-east-1"), replacing: nil)
        model.connections.openSaved(serverKey: "s3://down.local")
        await Wait.until { model.connections.unableToConnect != nil }
        check("a saved server that is offline says Unable to connect, and stays dimmed",
              model.connections.unableToConnect?.name == "down.local (S3)" && model.connections.unableToConnect?.reason == "Unable to reach the server."
              && model.places.connectionRoots.first { $0.name == "down.local (S3)" }?.isOffline == true, "\(String(describing: model.connections.unableToConnect))")
        model.connections.unableToConnect = nil
        model.connections.record(SavedConnection(kind: .sftp, host: "nopass.local", user: "me"), replacing: nil)
        model.connections.openSaved(serverKey: "sftp://nopass.local")
        await Wait.until { model.connections.unableToConnect != nil }
        check("a saved server with no password in the Keychain says so", model.connections.unableToConnect?.reason == "Type the password.", "\(String(describing: model.connections.unableToConnect))")
        model.connections.unableToConnect = nil

        model.connections.openManageSheet()
        check("Manage Connections opens its own view", model.connections.showManageSheet && !model.connections.showConnectSheet)
        model.disconnect(serverKey: "s3://minio.local:9000")
        if let minio {
            model.connections.openEdit(minio)
            check("Edit opens the sheet filled in from the saved settings",
                  model.connections.showConnectSheet && !model.connections.showManageSheet && model.connections.kind == .s3
                  && model.connections.prefill?.id == minio.id && model.connections.editingID == minio.id)
            model.connections.connectS3(accessKey: "GOODKEY", secretKey: "", region: "eu-west-1", endpoint: "minio2.local:9000", remember: false, save: true, savedID: minio.id)
            await Wait.until { !model.connections.isConnecting && !model.connections.showConnectSheet }
            await settle()
            check("saving an edit changes that entry and keeps its place",
                  model.connections.saved.items.count == 3 && model.connections.saved.items.first?.id == minio.id && model.connections.saved.items.first?.host == "minio2.local",
                  "\(model.connections.saved.items.map(\.host))")
            model.removeSavedConnection(minio.id)
            await settle()
            check("Remove deletes the saved entry, closes its connection, and deletes its Keychain item",
                  model.connections.saved.items.count == 2 && !model.router.serverKeys.contains("s3://minio2.local:9000") && secrets.deletedKeys == ["s3://minio2.local:9000/GOODKEY"],
                  "\(model.connections.saved.items.count) \(model.router.serverKeys) \(secrets.deletedKeys)")
            let after = String(decoding: Prefs.defaults.data(forKey: "pane.savedConnections") ?? Data(), as: UTF8.self)
            check("and the list in Settings no longer names it", !after.contains("minio2.local") && after.contains("down.local"))
        }
        for item in model.connections.saved.items { model.removeSavedConnection(item.id) }
        check("removing the rest empties Connections", model.connections.saved.items.isEmpty && model.places.connectionRoots.map(\.name) == ["xfer (SFTP)"], "\(model.places.connectionRoots.map(\.name))")
        model.connections.closeConnectSheet()
        model.connections.showManageSheet = false

        model.disconnect(serverKey: "sftp://xfer")
        await settle()
        model.tab.go(to: c.docs)
        await settle()
    }
}

/// Answers like curl does for one pretend FTP server, with a Windows-style listing.
private struct ScriptedFTP: ProcessRunner {
    let goodPassword: String
    func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) async throws -> ProcessResult {
        guard input.contains(":\(goodPassword)\"") else { return ProcessResult(stdout: "", stderr: "curl: (67) Access denied: 530", status: 67) }
        return ProcessResult(stdout: "10-30-26  09:15AM       <DIR>          Public\n10-30-26  09:15AM                 204 readme.txt\n", stderr: "", status: 0)
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

private final class Opened {
    var url: URL?
}

/// Answers like S3 does: buckets for the good key, "InvalidAccessKeyId" for any other.
private struct StubS3: S3Transport {
    let goodKey: String
    /// A server that cannot be reached.
    var down = false
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if down { throw RemoteError.connectionLost }
        let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let ok = auth.contains("Credential=\(goodKey)/")
        let body = ok
            ? "<ListAllMyBucketsResult><Buckets><Bucket><Name>photos</Name><CreationDate>2026-01-01T00:00:00.000Z</CreationDate></Bucket></Buckets></ListAllMyBucketsResult>"
            : "<Error><Code>InvalidAccessKeyId</Code><Message>The access key does not exist.</Message></Error>"
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: ok ? 200 : 403, httpVersion: nil, headerFields: nil)!)
    }
}
