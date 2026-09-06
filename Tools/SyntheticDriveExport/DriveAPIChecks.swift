import Foundation

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@main
enum DriveAPIChecks {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let api = DriveAPI(session: URLSession(configuration: configuration))

        MockURLProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-token")
            precondition(request.url?.path == "/drive/v3/about")
            return (200, Data(#"{"user":{"permissionId":"account-a","displayName":"Synthetic User","emailAddress":"synthetic@example.invalid"}}"#.utf8))
        }
        let account = try await api.account(accessToken: "private-token")
        precondition(account.id == "account-a")

        MockURLProtocol.handler = { request in
            precondition(request.httpMethod == "POST")
            precondition(request.url?.path == "/drive/v3/files")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-token")
            let bodyData = try requestBody(request)
            let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: String]
            precondition(body["name"] == "WeeklyHealthReport Exports")
            precondition(body["mimeType"] == DriveConsentPolicy.folderMIMEType)
            return (200, folderResponse)
        }
        let created = try await api.createFolder(accessToken: "private-token", accountID: account.id)
        try DriveConsentPolicy.validate(folder: created, expectedAccountID: account.id)

        MockURLProtocol.handler = { request in
            precondition(request.httpMethod == "GET")
            precondition(request.url?.path == "/drive/v3/files/folder-1")
            return (200, folderResponse)
        }
        let selected = try await api.folder(id: "folder-1", accessToken: "private-token", accountID: account.id)
        try DriveConsentPolicy.validate(folder: selected, expectedAccountID: account.id)

        MockURLProtocol.handler = { _ in (404, Data()) }
        try await api.confirmUnrelatedFileDenied(id: "unrelated", accessToken: "private-token")
        MockURLProtocol.handler = { _ in (200, Data(#"{"id":"unrelated"}"#.utf8)) }
        do {
            try await api.confirmUnrelatedFileDenied(id: "unrelated", accessToken: "private-token")
            preconditionFailure("An accessible unrelated file must fail the least-privilege check")
        } catch DriveAPI.Failure.unexpectedAccess {}

        MockURLProtocol.handler = { request in
            precondition(request.httpMethod == "POST")
            precondition(request.url?.path == "/revoke")
            let body = try requestBody(request)
            precondition(String(data: body, encoding: .utf8) == "token=private-token")
            return (200, Data())
        }
        let revokeStatus = try await api.revoke(token: "private-token")
        precondition(revokeStatus == 200)
        print("PASS: account/folder decoding, authenticated create/get, unrelated denial and revocation request")
    }

    private static let folderResponse = Data(#"{"id":"folder-1","name":"WeeklyHealthReport Exports","mimeType":"application/vnd.google-apps.folder","trashed":false,"isAppAuthorized":true,"capabilities":{"canAddChildren":true}}"#.utf8)

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.cannotDecodeContentData) }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}
