import Foundation
import Testing
@testable import PaneKit

// MARK: Saved connections (S-067)

@Test func savedConnectionsKeepSettingsOnlyAndNoSecret() throws {
    var list = SavedConnections()
    list.save(SavedConnection(kind: .sftp, host: "NAS.local", port: 2222, user: "me", useKey: true, keyPath: "/Users/me/.ssh/id_ed25519"))
    list.save(SavedConnection(kind: .s3, host: "minio.local", port: 9000, user: "AKIAEXAMPLE", region: "eu-west-1"))
    list.save(SavedConnection(kind: .ftps, host: "ftp.example.com", user: "web"))
    let text = String(decoding: list.data, as: UTF8.self)
    #expect(text.contains("nas.local") && text.contains("AKIAEXAMPLE") && text.contains("eu-west-1"))
    #expect(!text.lowercased().contains("password") && !text.lowercased().contains("secret"), "the saved list has no field for a secret")
    #expect(SavedConnections(data: list.data) == list)
    #expect(SavedConnections(data: Data("not json".utf8)).items.isEmpty && SavedConnections(data: nil).items.isEmpty)
}

@Test func savedConnectionsNameTheirServerAndUpdateInsteadOfDuplicating() {
    var list = SavedConnections()
    let sftp = SavedConnection(kind: .sftp, host: "nas.local", user: "me")
    list.save(sftp)
    #expect(sftp.serverKey == "sftp://nas.local" && sftp.displayName == "nas.local (SFTP)" && sftp.detail == "me@nas.local")
    #expect(SavedConnection(kind: .s3, host: "minio.local", port: 9000, user: "k").serverKey == "s3://minio.local:9000")
    #expect(SavedConnection(kind: .ftps, host: "h", user: "u").serverKey == "ftps://h" && SavedConnection(kind: .ftps, host: "h", user: "u").address.absoluteString == "ftps://h/")
    list.save(SavedConnection(kind: .sftp, host: "nas.local", user: "me", useKey: true, keyPath: "/k"))
    #expect(list.items.count == 1 && list.items[0].id == sftp.id && list.items[0].useKey, "the same server and user updates the entry")
    list.save(SavedConnection(kind: .sftp, host: "other.local", user: "me"), replacing: sftp.id)
    #expect(list.items.map(\.host) == ["other.local"] && list.items[0].id == sftp.id, "editing replaces the entry being edited, and keeps its id")
    let removed = list.remove(list.items[0].id)
    #expect(removed?.host == "other.local" && list.items.isEmpty)
    #expect(list.connection(forServerKey: "sftp://other.local") == nil)
}
