import Foundation
import Testing
@testable import PaneKit

// MARK: S3 (S-063)

struct StubTransport: S3Transport {
    let answer: @Sendable (URLRequest) -> (Int, String)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = answer(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func s3SignatureMatchesTheAWSDocsExample() {
    // "Example: GET Object" from the AWS Signature Version 4 docs.
    let date = ISO8601DateFormatter().date(from: "2013-05-24T00:00:00Z")!
    let headers = S3Signer.sign(
        method: "GET", url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!, headers: ["Range": "bytes=0-9"],
        credentials: .init(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"),
        region: "us-east-1", date: date)
    #expect(headers["Authorization"] == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
}

@Test func s3ListingTurnsPrefixesIntoFoldersAndKeysIntoFiles() throws {
    let xml = """
    <?xml version="1.0"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>b</Name><Prefix>docs/</Prefix>
    <IsTruncated>true</IsTruncated><NextContinuationToken>tok+1/=</NextContinuationToken>
    <Contents><Key>docs/a b.txt</Key><LastModified>2026-10-01T12:30:00.000Z</LastModified><Size>42</Size></Contents>
    <CommonPrefixes><Prefix>docs/sub/</Prefix></CommonPrefixes></ListBucketResult>
    """
    let page = try #require(S3Listing.parsePage(Data(xml.utf8)))
    #expect(page.folders == ["docs/sub/"])
    #expect(page.files.map(\.key) == ["docs/a b.txt"] && page.files.first?.size == 42 && page.files.first?.modified != nil)
    #expect(page.nextToken == "tok+1/=")
}

@Test func s3FollowsContinuationTokensAndOpensBucketsAsFolders() async throws {
    let calls = CallCounter()
    let transport = StubTransport { request in
        let query = request.url?.query ?? ""
        if request.url?.path == "/" {
            return (200, "<ListAllMyBucketsResult><Buckets><Bucket><Name>photos</Name><CreationDate>2026-01-01T00:00:00.000Z</CreationDate></Bucket></Buckets></ListAllMyBucketsResult>")
        }
        calls.add()
        if query.contains("continuation-token=next%2B1") {
            return (200, "<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>docs/two.txt</Key><Size>2</Size></Contents></ListBucketResult>")
        }
        return (200, "<ListBucketResult><IsTruncated>true</IsTruncated><NextContinuationToken>next+1</NextContinuationToken><Contents><Key>docs/</Key><Size>0</Size></Contents><Contents><Key>docs/one.txt</Key><Size>1</Size></Contents><CommonPrefixes><Prefix>docs/sub/</Prefix></CommonPrefixes></ListBucketResult>")
    }
    let s3 = S3FileSystem(endpoint: "s3.example.com:9000", region: "us-east-1", credentials: .init(accessKey: "k", secretKey: "s"), transport: transport)
    #expect(s3.serverKey == "s3://s3.example.com:9000")
    let top = try await s3.list(RemoteURL.make(scheme: "s3", host: "s3.example.com", port: 9000))
    #expect(top.map(\.name) == ["photos"] && top[0].isFolder)
    let docs = try await s3.list(RemoteURL.make(scheme: "s3", host: "s3.example.com", port: 9000, path: "/photos/docs"))
    #expect(Set(docs.map(\.name)) == ["sub", "one.txt", "two.txt"])
    #expect(calls.value == 2)
    #expect(docs.first { $0.name == "sub" }?.url.path == "/photos/docs/sub")
}

@Test func s3WrongKeyIsAccessDenied() async {
    let transport = StubTransport { _ in (403, "<Error><Code>InvalidAccessKeyId</Code><Message>The AWS Access Key Id you provided does not exist.</Message></Error>") }
    let s3 = S3FileSystem(endpoint: "s3.amazonaws.com", region: "us-east-1", credentials: .init(accessKey: "bad", secretKey: "bad"), transport: transport)
    await #expect(throws: RemoteError.denied("Access denied.")) { try await s3.list(URL(string: "s3://s3.amazonaws.com/")!) }
}
