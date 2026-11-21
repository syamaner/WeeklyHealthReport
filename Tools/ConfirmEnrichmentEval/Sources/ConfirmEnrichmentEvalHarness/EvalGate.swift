import FoodLedgerApplication
import Foundation

/// The tool-local gate (docs/confirm-enrichment-openrouter-v1-phase.md section 4, the last row): the
/// evaluation runs outside the app, so it does not ask Settings › OpenRouter; it permits the four Confirm
/// enrichment uses only, and every other OpenRouter use is refused.
public struct EvalGate: OpenRouterEgressPermitting {
    public static let uses: Set<OpenRouterUse> = [
        .confirmEnrichmentDetails, .confirmEnrichmentNutrients,
        .confirmEnrichmentDetailsCatalogueCheck, .confirmEnrichmentNutrientsCatalogueCheck,
    ]
    public init() {}
    public func permits(_ use: OpenRouterUse) -> Bool { Self.uses.contains(use) }
}

/// The OpenRouter key, read once from `OPENROUTER_API_KEY` into memory (11.1a: "read into memory only
/// and never printed or stored"). Saving and deleting do nothing, and its descriptions never show it.
public struct EnvironmentKey: FoodWebKeyStoring, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let variable = "OPENROUTER_API_KEY"

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case missing, malformed
        public var description: String {
            switch self {
            case .missing: "key_missing"
            case .malformed: "key_malformed"
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
