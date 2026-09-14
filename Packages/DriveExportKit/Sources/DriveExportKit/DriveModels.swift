import Foundation

public struct DailyDriveAccount: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let emailAddress: String

    public init(id: String, displayName: String, emailAddress: String) {
        self.id = id
        self.displayName = displayName
        self.emailAddress = emailAddress
    }
}

public struct DailyDriveFolder: Codable, Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let name: String
    public let mimeType: String
    public let trashed: Bool
    public let driveID: String?
    public let isAppAuthorized: Bool
    public let canAddChildren: Bool

    public init(
        id: String,
        accountID: String,
        name: String,
        mimeType: String,
        trashed: Bool,
        driveID: String?,
        isAppAuthorized: Bool,
        canAddChildren: Bool
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.mimeType = mimeType
        self.trashed = trashed
        self.driveID = driveID
        self.isAppAuthorized = isAppAuthorized
        self.canAddChildren = canAddChildren
    }
}

public struct DailyDriveFileMetadata: Equatable, Sendable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let parents: [String]
    public let trashed: Bool
    public let driveID: String?
    public let isAppAuthorized: Bool
    public let canEdit: Bool
    public let appProperties: [String: String]

    public init(
        id: String,
        name: String,
        mimeType: String,
        parents: [String],
        trashed: Bool,
        driveID: String?,
        isAppAuthorized: Bool,
        canEdit: Bool,
        appProperties: [String: String]
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.parents = parents
        self.trashed = trashed
        self.driveID = driveID
        self.isAppAuthorized = isAppAuthorized
        self.canEdit = canEdit
        self.appProperties = appProperties
    }
}

public struct DailyDriveUploadDescriptor: Equatable, Sendable {
    public let id: String
    public let name: String
    public let parentID: String
    public let appProperties: [String: String]

    public init(id: String, name: String, parentID: String, appProperties: [String: String]) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.appProperties = appProperties
    }
}
