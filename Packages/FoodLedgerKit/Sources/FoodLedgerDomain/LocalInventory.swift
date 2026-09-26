import Foundation

public enum InventoryProductTag: Sendable {}
public typealias InventoryProductID = LedgerID<InventoryProductTag>
public enum InventorySourceKind: String, Codable, Sendable { case receipt, catalogue }
public enum InventoryReviewDisposition: String, Codable, Sendable { case accepted, deferred, declined }

public struct InventoryAmount: Codable, Equatable, Sendable {
    public let value: Double
    public let unit: QuantityUnit

    public init(value: Double, unit: QuantityUnit) throws {
        self.value = value
        self.unit = unit
        try validate()
    }

    public func validate() throws {
        guard value.isFinite, value >= 0 else { throw FoodLedgerValidationError.negative("inventory amount") }
    }
}

/// A dated user assertion, not a live stock guarantee or a derived balance.
public struct InventoryRemainingAssertion: Codable, Equatable, Sendable {
    public let amount: InventoryAmount
    public let assertedAt: Date

    public init(amount: InventoryAmount, assertedAt: Date) throws {
        self.amount = amount
        self.assertedAt = assertedAt
        try validate()
    }

    public func validate() throws {
        try amount.validate()
        guard assertedAt.timeIntervalSince1970.isFinite else { throw FoodLedgerValidationError.nonFinite("assertion date") }
    }
}

public struct InventoryProductVersion: Codable, Equatable, Sendable {
    public let productID: InventoryProductID
    public let version: Int
    public let name: String
    public let category: String
    public let aliases: [String]
    public let packDescription: String
    public let remaining: InventoryRemainingAssertion?
    public let notes: String
    public let updatedAt: Date
    public let favourite: Bool?
    public let usualPortion: InventoryAmount?
    public var isFavourite: Bool { favourite == true }

    public init(
        productID: InventoryProductID, version: Int, name: String, category: String = "",
        aliases: [String] = [], packDescription: String = "",
        remaining: InventoryRemainingAssertion? = nil, notes: String = "", updatedAt: Date,
        favourite: Bool? = nil, usualPortion: InventoryAmount? = nil
    ) throws {
        self.productID = productID
        self.version = version
        self.name = name
        self.category = category
        self.aliases = aliases
        self.packDescription = packDescription
        self.remaining = remaining
        self.notes = notes
        self.updatedAt = updatedAt
        self.favourite = favourite
        self.usualPortion = usualPortion
        try validate()
    }

    public func validate() throws {
        _ = try InventoryProductID(productID.rawValue)
        guard version > 0 else { throw FoodLedgerValidationError.invalidOrdinal }
        _ = try LedgerText(name)
        guard updatedAt.timeIntervalSince1970.isFinite else { throw FoodLedgerValidationError.nonFinite("product date") }
        try remaining?.validate()
        try usualPortion?.validate()
        if let usualPortion, usualPortion.value <= 0 { throw FoodLedgerValidationError.nonPositive("usual portion") }
        if let remaining, remaining.assertedAt > updatedAt { throw FoodLedgerValidationError.invalidProvenance }
    }
}

public struct InventorySource: Codable, Equatable, Sendable {
    public let contentID: SHA256Digest
    public let kind: InventorySourceKind
    public let displayName: String
    public let originalBytes: Data
    public let extractedText: String
    public let extractionVersion: String
    public let parserVersion: String
    public let importedAt: Date
    public let lines: [ReceiptLineProposal]

    public init(
        contentID: SHA256Digest, kind: InventorySourceKind, displayName: String,
        originalBytes: Data, extractedText: String, extractionVersion: String, importedAt: Date
    ) throws {
        self.contentID = contentID
        self.kind = kind
        self.displayName = displayName
        self.originalBytes = originalBytes
        self.extractedText = extractedText
        self.extractionVersion = extractionVersion
        parserVersion = ReceiptParser.version
        self.importedAt = importedAt
        lines = try ReceiptParser.parse(extractedText)
        try validate()
    }

    public func validate() throws {
        _ = try SHA256Digest(contentID.value)
        guard !originalBytes.isEmpty, originalBytes.count <= 5_000_000 else { throw ReceiptParser.ParseError.tooLarge }
        guard importedAt.timeIntervalSince1970.isFinite else { throw FoodLedgerValidationError.nonFinite("import date") }
        _ = try LedgerText(extractionVersion)
        guard parserVersion == ReceiptParser.version else { throw FoodLedgerValidationError.invalidProvenance }
        // Persist the parser output and require exact v1 reconstruction on restore.
        guard lines == (try ReceiptParser.parse(extractedText)) else { throw FoodLedgerValidationError.invalidProvenance }
    }

    public func lineKey(_ lineNumber: Int) -> String { "\(contentID.value):\(lineNumber)" }
}

/// Appended review history. Received acquisition is distinct from remaining stock.
public struct InventoryReviewRevision: Codable, Equatable, Sendable {
    public let sourceID: SHA256Digest
    public let lineNumber: Int
    public let version: Int
    public let disposition: InventoryReviewDisposition
    public let productID: InventoryProductID?
    public let productVersion: Int?
    public let correctedDescription: String
    public let purchaseCount: Double?
    public let unitsPerPack: Double?
    public let packAmount: InventoryAmount?
    public let received: Bool
    public let acquisitionCorrection: String
    public let note: String
    public let reviewedAt: Date

    public var lineKey: String { "\(sourceID.value):\(lineNumber)" }

    public init(
        sourceID: SHA256Digest, lineNumber: Int, version: Int,
        disposition: InventoryReviewDisposition, productID: InventoryProductID? = nil,
        productVersion: Int? = nil, correctedDescription: String = "",
        purchaseCount: Double? = nil, unitsPerPack: Double? = nil,
        packAmount: InventoryAmount? = nil, received: Bool = false,
        acquisitionCorrection: String = "",
        note: String = "", reviewedAt: Date
    ) throws {
        self.sourceID = sourceID
        self.lineNumber = lineNumber
        self.version = version
        self.disposition = disposition
        self.productID = productID
        self.productVersion = productVersion
        self.correctedDescription = correctedDescription
        self.purchaseCount = purchaseCount
        self.unitsPerPack = unitsPerPack
        self.packAmount = packAmount
        self.received = received
        self.acquisitionCorrection = acquisitionCorrection
        self.note = note
        self.reviewedAt = reviewedAt
        try validate()
    }

    public func validate() throws {
        _ = try SHA256Digest(sourceID.value)
        guard lineNumber > 0, version > 0 else { throw FoodLedgerValidationError.invalidOrdinal }
        for value in [purchaseCount, unitsPerPack].compactMap({ $0 }) {
            guard value.isFinite, value > 0 else { throw FoodLedgerValidationError.nonPositive("purchase or pack count") }
        }
        try packAmount?.validate()
        if let packAmount, packAmount.value == 0 { throw FoodLedgerValidationError.nonPositive("pack amount") }
        guard reviewedAt.timeIntervalSince1970.isFinite else { throw FoodLedgerValidationError.nonFinite("review date") }
        if disposition == .accepted {
            guard let productID, let productVersion, productVersion > 0 else { throw FoodLedgerValidationError.missingProvenance }
            _ = try InventoryProductID(productID.rawValue)
            _ = try LedgerText(correctedDescription)
        } else if productID != nil || productVersion != nil || received || purchaseCount != nil || unitsPerPack != nil || packAmount != nil || !acquisitionCorrection.isEmpty {
            throw FoodLedgerValidationError.invalidProvenance
        }
    }
}

public struct InventoryMatch: Equatable, Sendable {
    public let product: InventoryProductVersion
    public let exactNameOrAlias: Bool
    public let differences: [String]
}

public enum InventoryMatcher {
    /// Deterministic ranking only. Even a unique exact alias needs user selection.
    public static func matches(_ query: String, products: [InventoryProductVersion]) -> [InventoryMatch] {
        let normal = normalized(query)
        guard !normal.isEmpty else { return [] }
        let tokens = Set(normal.split(separator: " "))
        return products.compactMap { product -> (Int, InventoryMatch)? in
            let names = [product.name] + product.aliases
            let exact = names.contains { normalized($0) == normal }
            let candidate = Set(normalized((names + [product.category]).joined(separator: " ")).split(separator: " "))
            let overlap = tokens.intersection(candidate).count
            guard exact || overlap > 0 else { return nil }
            return (exact ? 10_000 : overlap, InventoryMatch(
                product: product, exactNameOrAlias: exact,
                differences: exact ? ["Exact local name/alias only; verify variant and pack."]
                    : ["Name/category overlap only; brand, variant and pack may differ."]
            ))
        }.sorted {
            $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.product.productID.rawValue < $1.1.product.productID.rawValue
        }.map(\.1)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
