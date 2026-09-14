import Foundation

public struct DailyDestinationBinding: Codable, Equatable, Sendable {
    public enum Origin: String, Codable, Sendable { case pendingCreate, created, picker }

    public let accountID: String
    public let folderID: String
    public let folderName: String
    public let origin: Origin

    public init(accountID: String, folderID: String, folderName: String, origin: Origin) {
        self.accountID = accountID
        self.folderID = folderID
        self.folderName = folderName
        self.origin = origin
    }
}

public struct DailyDestinationPartitions: Codable, Equatable, Sendable {
    public private(set) var values: [String: DailyDestinationBinding] = [:]

    public init() {}

    public mutating func bind(_ destination: DailyDestinationBinding) {
        values[destination.accountID] = destination
    }

    public func destination(for accountID: String) -> DailyDestinationBinding? {
        values[accountID]
    }

    @discardableResult
    public mutating func unbind(accountID: String, folderID: String) -> Bool {
        guard values[accountID]?.folderID == folderID else { return false }
        values.removeValue(forKey: accountID)
        return true
    }
}

public enum DailyDisconnectTransition: Equatable {
    case keepCredentialsAndReportFailure
    case clearCredentialsPreserveDestinations

    public static func afterRevocation(statusCode: Int) -> DailyDisconnectTransition {
        statusCode == 200 ? .clearCredentialsPreserveDestinations : .keepCredentialsAndReportFailure
    }
}
