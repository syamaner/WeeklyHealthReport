import FoodLedgerApplication
import Foundation

/// The OpenRouter key for `send --live` (T4: "loaded into the environment only and never printed").
/// It is read once from `OPENROUTER_API_KEY` into memory and handed only to the shipped attempt,
/// which puts it in the POST's Authorization header. Saving and deleting do nothing, so it is never
/// cached or written, and its description, debug description and mirror never show it.
public struct EnvironmentKey: FoodWebKeyStoring, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let variable = "OPENROUTER_API_KEY"

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case missing, malformed
        public var description: String {
            switch self {
            case .missing: "\(EnvironmentKey.variable) is not set or is empty; --live reads the key from the environment only"
            case .malformed: "\(EnvironmentKey.variable) is not a well-formed key (its value is not shown)"
            }
        }
    }

    private let key: String

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard let value = environment[Self.variable], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Problem.missing
        }
        guard FoodWebKeySyntax.isValid(value) else { throw Problem.malformed }
        key = value
    }

    public func load() throws -> String? { key }
    public func save(_ key: String) throws {}
    public func delete() throws {}

    public var description: String { "EnvironmentKey(\(Self.variable), redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// How `send` connects: exactly one of `--fake-transport DIR` and `--live` (A3). Checked before
/// anything is reserved or sent; a live run needs a well-formed key in the environment.
public enum SendTransportChoice: Sendable {
    case fake(directory: String)
    case live(EnvironmentKey)

    public struct UsageError: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public static func choose(fakeTransport: String?, live: Bool,
                              environment: [String: String] = ProcessInfo.processInfo.environment) throws -> SendTransportChoice {
        switch (fakeTransport, live) {
        case (.some, true): throw UsageError(description: "send takes --fake-transport DIR or --live, not both")
        case (nil, false): throw UsageError(description: "send needs exactly one of --fake-transport DIR and --live")
        case let (directory?, false): return .fake(directory: directory)
        case (nil, true):
            do { return .live(try EnvironmentKey(environment: environment)) } catch let problem as EnvironmentKey.Problem {
                throw UsageError(description: "send --live: \(problem)")
            }
        }
    }
}
