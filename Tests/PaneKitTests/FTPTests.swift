import Foundation
import Testing
@testable import PaneKit

// MARK: FTP (S-061)

@Test func ftpListingReadsUnixAndWindowsFormats() {
    let unix = """
    total 12
    drwxr-xr-x   2 ftp      ftp          4096 Oct 30 09:15 Año nuevo
    -rw-r--r--   1 ftp      ftp        118000 Mar  3  2024 Budget 2026.xlsx
    """
    let iis = """
    10-30-26  09:15AM       <DIR>          Public Files
    03-03-2024  12:05PM              118000 Budget 2026.xlsx
    11-01-26  12:00AM                 204 notes.txt
    """
    let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
    let a = FTPText.parseListing(unix, folder: URL(string: "ftp://h/")!, now: now)
    #expect(a.map(\.name) == ["Año nuevo", "Budget 2026.xlsx"] && a[0].isFolder && a[1].size == 118000)
    let b = FTPText.parseListing(iis, folder: URL(string: "ftp://h/")!, now: now)
    #expect(b.map(\.name) == ["Public Files", "Budget 2026.xlsx", "notes.txt"])
    #expect(b[0].isFolder && b[1].size == 118000 && b[2].size == 204)
    let calendar = Calendar(identifier: .gregorian)
    #expect(calendar.component(.hour, from: b[1].modified!) == 12 && calendar.component(.hour, from: b[2].modified!) == 0)
    #expect(calendar.component(.year, from: b[1].modified!) == 2024)
}

@Test func ftpFailuresBecomeWordsAPersonCanUse() {
    #expect(FTPText.classify(status: 67, stderr: "curl: (67) Access denied: 530") == .denied("Access denied."))
    #expect(FTPText.classify(status: 7, stderr: "Failed to connect") == .connectionLost)
    #expect(FTPText.classify(status: 60, stderr: "") == .other("Unable to verify this server's certificate."))
    #expect(FTPText.classify(status: 64, stderr: "").message.contains("does not support TLS"))
}

@Test func ftpSendsTheLoginOnStdinAndAsksForTLSWhenToldTo() async throws {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "drwxr-xr-x 2 a b 4096 Oct 30 09:15 Docs\n", stderr: "", status: 0) }
    let tls = FTPFileSystem(host: "FTP.Example.com", port: 2121, user: "me", password: "p\"w\\x", secure: true, runner: runner)
    #expect(tls.serverKey == "ftps://ftp.example.com:2121")
    let items = try await tls.list(URL(string: "ftps://ftp.example.com:2121/My%20Files")!)
    #expect(items.map(\.name) == ["Docs"])
    let call = try #require(runner.calls.first)
    #expect(call.exe == "/usr/bin/curl" && call.args.contains("--ssl-reqd") && !call.args.joined().contains("p\"w"))
    #expect(call.input.contains("url = \"ftps://ftp.example.com:2121/My%20Files/\""))
    #expect(call.input.contains("user = \"me:p\\\"w\\\\x\""))
    let plain = FTPFileSystem(host: "h", user: "me", password: "pw", secure: false, runner: runner)
    _ = try await plain.list(URL(string: "ftp://h/")!)
    #expect(!(runner.calls.last?.args.contains("--ssl-reqd") ?? true))
}

@Test func ftpWrongPasswordIsAccessDenied() async {
    let runner = ScriptedRunner { _, _, _ in ProcessResult(stdout: "", stderr: "curl: (67) Access denied: 530", status: 67) }
    await #expect(throws: RemoteError.denied("Access denied.")) {
        try await FTPFileSystem(host: "h", user: "me", password: "bad", secure: false, runner: runner).start()
    }
}
