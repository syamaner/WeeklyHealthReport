import Foundation

struct DriveAccount: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let emailAddress: String
}

struct DriveAPI: DriveTransporting, @unchecked Sendable {
    enum Failure: Error, Equatable, Sendable {
        case invalidResponse
        case httpStatus(Int, String?)
        case unexpectedAccess
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func account(accessToken: String) async throws -> DriveAccount {
        let url = URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(permissionId%2CdisplayName%2CemailAddress)")!
        let data = try await request(url: url, accessToken: accessToken)
        struct Response: Decodable {
            struct User: Decodable {
                let permissionId: String
                let displayName: String?
                let emailAddress: String?
            }
            let user: User
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return DriveAccount(
            id: response.user.permissionId,
            displayName: response.user.displayName ?? "Google account",
            emailAddress: response.user.emailAddress ?? "Address unavailable"
        )
    }

    func createFolder(accessToken: String, accountID: String) async throws -> DriveFolderMetadata {
        let fields = "id,name,mimeType,trashed,driveId,isAppAuthorized,capabilities(canAddChildren)"
        let url = URL(string: "https://www.googleapis.com/drive/v3/files?fields=\(fields.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)")!
        let body = try JSONSerialization.data(withJSONObject: [
            "name": "WeeklyHealthReport Exports",
            "mimeType": DriveConsentPolicy.folderMIMEType
        ])
        return try await folderRequest(url: url, method: "POST", body: body, accessToken: accessToken, accountID: accountID)
    }

    func generateFileID(accessToken: String) async throws -> String {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/generateIds?count=1&space=drive&type=files")!
        let data = try await request(url: url, accessToken: accessToken)
        struct Response: Decodable { let ids: [String] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.ids.count == 1, let id = response.ids.first, !id.isEmpty else {
            throw Failure.invalidResponse
        }
        return id
    }

    func createFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        let fields = Self.fileFields.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=\(fields)")!
        let metadata: [String: Any] = [
            "id": descriptor.id,
            "name": descriptor.name,
            "mimeType": "application/json",
            "parents": [descriptor.parentID],
            "appProperties": descriptor.appProperties
        ]
        _ = try await uploadRequest(
            url: url,
            method: "POST",
            metadata: metadata,
            content: content,
            accessToken: accessToken
        )
    }

    func updateFile(
        _ descriptor: DriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        let encodedID = descriptor.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let fields = Self.fileFields.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(encodedID)?uploadType=multipart&fields=\(fields)")!
        let metadata: [String: Any] = [
            "name": descriptor.name,
            "mimeType": "application/json",
            "appProperties": descriptor.appProperties
        ]
        _ = try await uploadRequest(
            url: url,
            method: "PATCH",
            metadata: metadata,
            content: content,
            accessToken: accessToken
        )
    }

    func fileMetadata(id: String, accessToken: String) async throws -> DriveFileMetadata {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let fields = Self.fileFields.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(encodedID)?fields=\(fields)")!
        let data = try await request(url: url, accessToken: accessToken)
        return try decodeFile(data)
    }

    func fileContent(id: String, accessToken: String) async throws -> Data {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(encodedID)?alt=media")!
        return try await request(url: url, accessToken: accessToken)
    }

    func folder(id: String, accessToken: String, accountID: String) async throws -> DriveFolderMetadata {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let fields = "id,name,mimeType,trashed,driveId,isAppAuthorized,capabilities(canAddChildren)"
        let encodedFields = fields.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(encodedID)?fields=\(encodedFields)")!
        return try await folderRequest(url: url, method: "GET", body: nil, accessToken: accessToken, accountID: accountID)
    }

    func confirmUnrelatedFileDenied(id: String, accessToken: String) async throws {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(encodedID)?fields=id")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if http.statusCode == 403 || http.statusCode == 404 { return }
        if (200..<300).contains(http.statusCode) { throw Failure.unexpectedAccess }
        throw Self.httpFailure(statusCode: http.statusCode, data: Data())
    }

    func revoke(token: String) async throws -> Int {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        return http.statusCode
    }

    private func folderRequest(
        url: URL,
        method: String,
        body: Data?,
        accessToken: String,
        accountID: String
    ) async throws -> DriveFolderMetadata {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data = try await self.request(request)
        struct File: Decodable {
            struct Capabilities: Decodable { let canAddChildren: Bool? }
            let id: String
            let name: String?
            let mimeType: String
            let trashed: Bool?
            let driveId: String?
            let isAppAuthorized: Bool?
            let capabilities: Capabilities?
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        return DriveFolderMetadata(
            id: file.id,
            accountID: accountID,
            name: file.name ?? "Unnamed folder",
            mimeType: file.mimeType,
            trashed: file.trashed ?? false,
            driveID: file.driveId,
            isAppAuthorized: file.isAppAuthorized ?? false,
            canAddChildren: file.capabilities?.canAddChildren ?? false
        )
    }

    private func request(url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await self.request(request)
    }

    private func request(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.httpFailure(statusCode: http.statusCode, data: data)
        }
        return data
    }

    private func uploadRequest(
        url: URL,
        method: String,
        metadata: [String: Any],
        content: Data,
        accessToken: String
    ) async throws -> Data {
        let boundary = "whr-\(UUID().uuidString)"
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(metadataData)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(content)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try await self.request(request)
    }

    private func decodeFile(_ data: Data) throws -> DriveFileMetadata {
        struct File: Decodable {
            struct Capabilities: Decodable { let canEdit: Bool? }
            let id: String
            let name: String?
            let mimeType: String
            let parents: [String]?
            let trashed: Bool?
            let driveId: String?
            let isAppAuthorized: Bool?
            let capabilities: Capabilities?
            let appProperties: [String: String]?
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        return DriveFileMetadata(
            id: file.id,
            name: file.name ?? "",
            mimeType: file.mimeType,
            parents: file.parents ?? [],
            trashed: file.trashed ?? false,
            driveID: file.driveId,
            isAppAuthorized: file.isAppAuthorized ?? false,
            canEdit: file.capabilities?.canEdit ?? false,
            appProperties: file.appProperties ?? [:]
        )
    }

    private static func httpFailure(statusCode: Int, data: Data) -> Failure {
        struct Envelope: Decodable {
            struct Body: Decodable {
                struct Detail: Decodable { let reason: String? }
                let errors: [Detail]?
            }
            let error: Body
        }
        let reason = (try? JSONDecoder().decode(Envelope.self, from: data))?
            .error.errors?.first?.reason
        return .httpStatus(statusCode, reason)
    }

    private static let fileFields = "id,name,mimeType,parents,trashed,driveId,isAppAuthorized,capabilities(canEdit),appProperties"
}
