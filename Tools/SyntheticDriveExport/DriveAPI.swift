import Foundation

struct DriveAccount: Codable, Equatable {
    let id: String
    let displayName: String
    let emailAddress: String
}

struct DriveAPI {
    enum Failure: Error {
        case invalidResponse
        case httpStatus(Int)
        case unexpectedAccess
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
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
        throw Failure.httpStatus(http.statusCode)
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
        guard (200..<300).contains(http.statusCode) else { throw Failure.httpStatus(http.statusCode) }
        return data
    }
}
