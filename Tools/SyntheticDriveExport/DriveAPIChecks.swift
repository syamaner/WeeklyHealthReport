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
            precondition(request.httpMethod == "GET")
            precondition(request.url?.path == "/drive/v3/files/generateIds")
            precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(URLQueryItem(name: "count", value: "1")) == true)
            return (200, Data(#"{"ids":["file-1"],"space":"drive","kind":"drive#generatedIds"}"#.utf8))
        }
        let generatedID = try await api.generateFileID(accessToken: "private-token")
        precondition(generatedID == "file-1")

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

        let fixture = try SyntheticPayload.data(1)
        let descriptor = DriveUploadDescriptor(
            id: generatedID,
            name: SyntheticPayload.filename,
            parentID: "folder-1",
            appProperties: [CanonicalMetadataKeys.owner: CanonicalMetadataKeys.ownerValue]
        )
        MockURLProtocol.handler = { request in
            precondition(request.httpMethod == "POST")
            precondition(request.url?.path == "/upload/drive/v3/files")
            precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(URLQueryItem(name: "uploadType", value: "multipart")) == true)
            let body = try requestBody(request)
            let bodyText = String(decoding: body, as: UTF8.self)
            precondition(bodyText.contains(#""id":"file-1""#))
            precondition(bodyText.contains(#""parents":["folder-1"]"#))
            precondition(body.range(of: fixture) != nil)
            return (200, fileResponse)
        }
        try await api.createFile(descriptor, content: fixture, accessToken: "private-token")

        let evening = try SyntheticPayload.data(2)
        MockURLProtocol.handler = { request in
            precondition(request.httpMethod == "PATCH")
            precondition(request.url?.path == "/upload/drive/v3/files/file-1")
            let body = try requestBody(request)
            let bodyText = String(decoding: body, as: UTF8.self)
            precondition(!bodyText.contains(#""parents""#), "Update must not move the file")
            precondition(body.range(of: evening) != nil)
            return (200, fileResponse)
        }
        try await api.updateFile(descriptor, content: evening, accessToken: "private-token")

        MockURLProtocol.handler = { request in
            precondition(request.httpMethod == "GET")
            precondition(request.url?.path == "/drive/v3/files/file-1")
            precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(where: { $0.name == "fields" }) == true)
            return (200, fileResponse)
        }
        let metadata = try await api.fileMetadata(id: generatedID, accessToken: "private-token")
        precondition(metadata.id == generatedID)
        precondition(metadata.parents == ["folder-1"])
        precondition(metadata.canEdit)

        MockURLProtocol.handler = { request in
            precondition(request.httpMethod == "GET")
            precondition(request.url?.path == "/drive/v3/files/file-1")
            precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(URLQueryItem(name: "alt", value: "media")) == true)
            return (200, evening)
        }
        let downloaded = try await api.fileContent(id: generatedID, accessToken: "private-token")
        precondition(downloaded == evening)

        MockURLProtocol.handler = { _ in
            (403, Data(#"{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}"#.utf8))
        }
        do {
            _ = try await api.fileContent(id: generatedID, accessToken: "private-token")
            preconditionFailure("Structured Drive errors must be retained without logging response bodies")
        } catch DriveAPI.Failure.httpStatus(403, "storageQuotaExceeded") {}

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
        print("PASS: account/folder decoding, generated ID, multipart create/update, remote readback, structured errors, unrelated denial and revocation")
    }

    private static let folderResponse = Data(#"{"id":"folder-1","name":"WeeklyHealthReport Exports","mimeType":"application/vnd.google-apps.folder","trashed":false,"isAppAuthorized":true,"capabilities":{"canAddChildren":true}}"#.utf8)
    private static let fileResponse = Data(#"{"id":"file-1","name":"health-daily-2026-09-06.json","mimeType":"application/json","parents":["folder-1"],"trashed":false,"isAppAuthorized":true,"capabilities":{"canEdit":true},"appProperties":{"whrSyntheticCanonical":"v1"}}"#.utf8)

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
