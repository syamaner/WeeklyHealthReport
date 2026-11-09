import FoodLedgerDomain

/// Source-row details a bundled reference source keeps outside its candidates, for Developer
/// tools only (docs/ciqual-2025-admission-v1.md section 7): the name in the source's language
/// and each value's published literal, confidence code and source code. They are never searched,
/// never part of a candidate, a saved record, an archive or an export, and never change ranking,
/// compatibility or provenance. `minimum` and `maximum` are the published literals (A7): never
/// parsed and never bounds.
public struct GenericSourceRecordDetails: Equatable, Sendable {
    public struct Value: Equatable, Sendable {
        public let key: NutrientKey
        public let constituentCode: String
        public let literal: String
        /// Nil only for a published "-" (no value), which carries no code.
        public let confidence: String?
        public let sourceCode: String?
        public let minimum: String?
        public let maximum: String?

        public init(key: NutrientKey, constituentCode: String, literal: String, confidence: String?, sourceCode: String?,
                    minimum: String?, maximum: String?) {
            self.key = key; self.constituentCode = constituentCode; self.literal = literal
            self.confidence = confidence; self.sourceCode = sourceCode; self.minimum = minimum; self.maximum = maximum
        }
    }

    /// The source's short name, for example "Ciqual".
    public let sourceName: String
    /// The language of `originalName`, for example "French".
    public let originalNameLanguage: String
    public let originalName: String
    /// Catalogue order; only keys with a source row.
    public let values: [Value]

    public init(sourceName: String, originalNameLanguage: String, originalName: String, values: [Value]) {
        self.sourceName = sourceName; self.originalNameLanguage = originalNameLanguage
        self.originalName = originalName; self.values = values
    }
}

/// Looks up a candidate's Developer tools details by record ID; nil for any other source.
public protocol GenericSourceRecordDetailing: Sendable {
    func details(recordID: ExternalIdentifier) -> GenericSourceRecordDetails?
}
