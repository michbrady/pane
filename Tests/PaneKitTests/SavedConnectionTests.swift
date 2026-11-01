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

// MARK: Checking the connect form

private func message(_ form: ConnectionForm, _ store: SecretStore = InMemorySecretStore()) -> String? {
    if case .failure(let error) = form.validated(store: store) { return error.message }
    return nil
}

@Test func theFormSaysWhatIsMissingInTheOrderTheFieldsAppear() {
    var sftp = ConnectionForm(kind: .sftp)
    #expect(message(sftp) == "Type the server name, like nas.local.")
    sftp.host = "nas.local"; sftp.port = "99999"
    #expect(message(sftp) == "The port is a number from 1 to 65535.")
    sftp.port = ""
    #expect(message(sftp) == "Type the user name.")
    sftp.user = "me"; sftp.useKey = true
    #expect(message(sftp) == "Choose a key file.")
    sftp.useKey = false
    #expect(message(sftp) == "Type the password.")
    #expect(message(ConnectionForm(kind: .ftps)) == "Type the server name, like ftp.example.com.")
    var s3 = ConnectionForm(kind: .s3)
    #expect(message(s3) == "Type the access key.")
    s3.user = "AKIA"
    #expect(message(s3) == "Type the region, like us-east-1.")
    s3.region = "us-east-1"
    #expect(message(s3) == "Type the secret key.")
}

@Test func theFormUsesTheStoredSecretAndBuildsTheConnection() throws {
    let store = InMemorySecretStore()
    store.preload("kept", forKey: "s3://minio.local:9000/AKIA")
    var s3 = ConnectionForm(kind: .s3)
    s3.user = " AKIA "; s3.region = "EU-West-1"; s3.endpoint = "https://minio.local:9000/"
    let valid = try s3.validated(store: store).get()
    #expect(valid.secret == "kept" && valid.endpoint == "minio.local:9000" && valid.connection.region == "eu-west-1" && valid.connection.user == "AKIA")
    s3.endpoint = ""
    #expect(try s3.validated(store: InMemorySecretStore().self).failureMessage == "Type the secret key.")
    var typed = s3; typed.secret = "typed"
    #expect(try typed.validated(store: InMemorySecretStore()).get().connection.host == "s3.eu-west-1.amazonaws.com")
    var key = ConnectionForm(kind: .sftp)
    key.host = "NAS.local"; key.user = "me"; key.useKey = true; key.keyPath = "/k"
    let withKey = try key.validated(store: store).get()
    #expect(withKey.secret.isEmpty && withKey.connection.useKey && withKey.connection.keyPath == "/k" && withKey.connection.serverKey == "sftp://nas.local")
}

private extension Result where Failure == ConnectionForm.FormError {
    var failureMessage: String? { if case .failure(let error) = self { error.message } else { nil } }
}
