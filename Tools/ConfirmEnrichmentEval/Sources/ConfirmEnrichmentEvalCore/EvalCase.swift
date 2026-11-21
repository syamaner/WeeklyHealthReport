import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// One evaluation case (docs/confirm-enrichment-openrouter-v1-phase.md section 9), held in the owner's
/// private folder and never committed. An Open Food Facts case names a product record file from the
/// owner's hand-downloaded public export (relative to the private folder) and whether it is built as the
/// barcode or the search candidate; a bundled-row case names a table, the search text and the row's
/// `recordID`. For B, `hidden` lists the known values hidden for this case (CE1 section 12).
public struct EvalCase: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case openFoodFacts = "open_food_facts", bundledRow = "bundled_row" }
    public enum Shape: String, Codable, Sendable { case barcode, search }
    public enum Table: String, Codable, Sendable, CaseIterable { case cofid, usda, tfda, ciqual }

    public let kind: Kind
    /// Open Food Facts: the record file and how its candidate is built.
    public let record: String?
    public let shape: Shape?
    /// Bundled rows: the table, the search text and the row.
    public let table: Table?
    public let search: String?
    public let recordID: String?
    /// When the record was retrieved or the row searched, RFC 3339 UTC.
    public let retrievedAt: String
    /// Known nutrient keys hidden for B in this case; empty for A.
    public let hidden: [String]

    enum CodingKeys: String, CodingKey {
        case kind, record, shape, table, search, hidden
        case recordID = "record_id"
        case retrievedAt = "retrieved_at"
    }

    public init(kind: Kind, record: String? = nil, shape: Shape? = nil, table: Table? = nil, search: String? = nil,
                recordID: String? = nil, retrievedAt: String, hidden: [NutrientKey] = []) {
        self.kind = kind; self.record = record; self.shape = shape; self.table = table; self.search = search
        self.recordID = recordID; self.retrievedAt = retrievedAt; self.hidden = hidden.map(\.rawValue).sorted()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(record, forKey: .record)
        try c.encode(shape, forKey: .shape)
        try c.encode(table, forKey: .table)
        try c.encode(search, forKey: .search)
        try c.encode(recordID, forKey: .recordID)
        try c.encode(retrievedAt, forKey: .retrievedAt)
        try c.encode(hidden, forKey: .hidden)
    }

    public var hiddenKeys: Set<NutrientKey> { Set(hidden.compactMap(NutrientKey.init(rawValue:))) }

    public var retrievalDate: Date? { ISO8601DateFormatter().date(from: retrievedAt) }

    /// Whether the case is complete for its kind.
    public var isWellFormed: Bool {
        guard retrievalDate != nil, hidden.allSatisfy({ NutrientKey(rawValue: $0) != nil }) else { return false }
        switch kind {
        case .openFoodFacts: return record?.isEmpty == false && shape != nil && table == nil && recordID == nil
        case .bundledRow: return table != nil && search?.isEmpty == false && recordID?.isEmpty == false && record == nil && shape == nil
        }
    }
}

/// `confirm-enrichment-eval-cases-v1`: one set's case list.
public struct EvalCaseList: Codable, Equatable, Sendable {
    public static let schema = "confirm-enrichment-eval-cases-v1"
    public let schema: String
    public let cases: [EvalCase]

    public init(cases: [EvalCase]) { schema = Self.schema; self.cases = cases }

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case unreadable, unknownSchema, malformedCase(index: Int)
        public var description: String {
            switch self {
            case .unreadable: "the case list cannot be read"
            case .unknownSchema: "the case list has an unknown schema"
            case let .malformedCase(index): "case number \(index + 1) is incomplete for its kind"
            }
        }
    }

    public static func decode(_ data: Data) throws -> EvalCaseList {
        guard let list = try? JSONDecoder().decode(EvalCaseList.self, from: data) else { throw Problem.unreadable }
        guard list.schema == schema else { throw Problem.unknownSchema }
        if let index = list.cases.firstIndex(where: { !$0.isWellFormed }) { throw Problem.malformedCase(index: index) }
        return list
    }
}

/// Case hashes and set manifests: the only names a case ever has outside the private folder (G11).
public enum EvalHashes {
    /// The SHA-256 of a case's canonical JSON.
    public static func hash(_ evalCase: EvalCase, encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
                            digester: any Digesting = SHA256Digester()) throws -> String {
        try digester.sha256(encoder.encode(evalCase)).value
    }

    /// The committed manifest of a set: its case count and the SHA-256 of its canonical case list.
    public struct Manifest: Equatable, Sendable {
        public let count: Int
        public let sha256: String
    }

    public static func manifest(_ list: EvalCaseList, encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(),
                                digester: any Digesting = SHA256Digester()) throws -> Manifest {
        Manifest(count: list.cases.count, sha256: try digester.sha256(encoder.encode(list)).value)
    }

    /// The short form printed on the console.
    public static func short(_ hash: String) -> String { String(hash.prefix(12)) }
}
