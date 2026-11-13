import Foundation

/// Every rule code of import v1 section 4.2 and import v2 section 3. The raw values are the codes of
/// the skill's `export_v1.check_bytes`, so the two checkers report the same code for each shared
/// fixture (`docs/fixtures/personal-food-database-v2/manifest.json` lists the full set and the v1
/// manifest the v1 subset; a test keeps them equal).
public enum PersonalFoodDatabaseRuleCode: String, CaseIterable, Error, Sendable {
    case size, bom, encoding, json
    case duplicateKey = "duplicate-key"
    /// Python's last-resort code for an unanticipated type. The Swift checker never emits it.
    case malformed
    case topKeys = "top-keys", schema, generated, sources
    case sourceFields = "source-fields", sourceForm = "source-form", sourceHash = "source-hash"
    case sourceDate = "source-date", sourcePins = "source-pins", sourceDuplicate = "source-duplicate"
    case corpus, items, count
    case itemKeys = "item-keys", title
    case idForm = "id-form", idDuplicate = "id-duplicate", idOrder = "id-order"
    case itemTypes = "item-types", vocabulary, reference
    case referenceCorpus = "reference-corpus", mergeCondition = "merge-condition", tfdaRecordID = "tfda-record-id"
    case labelNutrients = "label-nutrients", unknownNutrient = "unknown-nutrient", valueShape = "value-shape"
    case valueKeys = "value-keys", unit, value
    case kindMatch = "kind-match", recordID = "record-id"
    case undeclaredRelease = "undeclared-release", releaseKind = "release-kind"
    case sourceValue = "source-value", transformShape = "transform-shape", transformUnknown = "transform-unknown"
    case transformScope = "transform-scope", transformArithmetic = "transform-arithmetic"
    /// Import v2 only: a scaled value above any food's content per 100, or one entry's values from
    /// one release disagreeing on the serving size.
    case servingImplausible = "serving-implausible", servingMismatch = "serving-mismatch"

    /// The codes a `personal-food-catalogue-v1` file can never get.
    public static let v2Only: Set<Self> = [.servingImplausible, .servingMismatch]
}

/// The file schemas the importer accepts. v1 files keep the v1 rules exactly; v2 adds Open Food
/// Facts projection v6 (docs/personal-food-catalogue-import-v2.md).
public enum PersonalFoodDatabaseSchema: String, CaseIterable, Sendable {
    case v1 = "personal-food-catalogue-v1"
    case v2 = "personal-food-catalogue-v2"
}

/// A rejected file: the rule codes in the order found. It never carries an entry ID, title or
/// value, so no message built from it can show file content.
public struct PersonalFoodDatabaseRejection: Error, Equatable, Sendable {
    public let codes: [PersonalFoodDatabaseRuleCode]
}

/// A real proleptic Gregorian date (years 1 to 9999), as Python's `date.fromisoformat` accepts.
public struct PersonalFoodDatabaseDate: Equatable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        default: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        }
    }

    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strict `YYYY-MM-DD` in ASCII digits only.
    public init?(ascii bytes: some Collection<UInt8>) {
        let b = Array(bytes)
        guard b.count == 10, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var v = 0
            for i in range {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b[i]) else { return nil }
                v = v * 10 + Int(b[i] - UInt8(ascii: "0"))
            }
            return v
        }
        guard let y = number(0..<4), let m = number(5..<7), let d = number(8..<10) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The `YYYY-MM-DD` form, as the file writes it.
    public var text: String {
        func pad(_ v: Int, _ n: Int) -> String { String(repeating: "0", count: max(0, n - String(v).count)) + String(v) }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// 00:00:00Z on this date, by day arithmetic (never the process calendar or time zone).
    public var utcMidnight: Date {
        // Days from 1970-01-01 in the proleptic Gregorian calendar (Hinnant's days_from_civil).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        return Date(timeIntervalSince1970: TimeInterval(days) * 86_400)
    }
}

public enum PersonalFoodDatabaseCategory: String, CaseIterable, Sendable {
    case fruit, vegetable, dairy, egg, meat, fish, bakery, legume, snack, confectionery, beverage, alcohol, other
    case herbSpice = "herb_spice", grainCereal = "grain_cereal", nutSeed = "nut_seed", oilFat = "oil_fat"
    case condimentSauce = "condiment_sauce", readyMeal = "ready_meal"
}

public enum PersonalFoodDatabaseProductType: String, CaseIterable, Sendable {
    case freshWhole = "fresh_whole", packagedSingleIngredient = "packaged_single_ingredient"
    case packagedComposite = "packaged_composite", unknown
}

public enum PersonalFoodDatabaseState: String, CaseIterable, Sendable {
    case raw, cooked, canned, frozen, dried, smoked, unknown
}

public enum PersonalFoodDatabaseBasis: String, CaseIterable, Sendable {
    case per100Grams = "per_100_g", per100MillilitresAsLabelled = "per_100_ml_as_labelled"
}

public enum PersonalFoodDatabaseGenericSource: String, CaseIterable, Sendable {
    case cofid, usda, tfda
}

public enum PersonalFoodDatabaseReferenceMatch: String, CaseIterable, Sendable {
    case sameFoodSameState = "same_food_same_state", close
}

public enum PersonalFoodDatabaseReferenceRole: String, CaseIterable, Sendable {
    case merge, candidate
}

public struct PersonalFoodDatabaseGenericReference: Equatable, Sendable {
    public let source: PersonalFoodDatabaseGenericSource
    public let corpusSHA256: String
    public let recordID: String
    public let match: PersonalFoodDatabaseReferenceMatch
    public let role: PersonalFoodDatabaseReferenceRole
}

/// One `{transform_id, version}` pair, in file order.
public struct PersonalFoodDatabaseTransformStep: Equatable, Sendable {
    public let transformID: String
    public let version: String
}

/// The transforms of one value (import v1 section 4; import v2 section 3), with the printed value
/// they were computed from. v1 holds exactly one step and no serving. v2 also allows the
/// `off-serving-to-100` step, alone or after `mass-g-to-mg`, and then `serving` is the panel's own
/// serving size (grams or millilitres): the source value is per that serving, not per 100.
public struct PersonalFoodDatabaseTransform: Equatable, Sendable {
    public let steps: [PersonalFoodDatabaseTransformStep]
    public let sourceValue: Double
    public let sourceUnit: String
    public let serving: PositiveQuantity?

    /// True when the value was scaled from a per-serving panel.
    public var isServingScaled: Bool { serving != nil }
}

public enum PersonalFoodDatabaseValueSource: Equatable, Sendable {
    /// Owner-typed or owner-confirmed label value; `match` `owner`, no record ID.
    case manualDeclaration(sourceRelease: String)
    /// The product's own Open Food Facts record; `match` `probable`, `off:gtin:` and 14 digits.
    case exactProductDataset(sourceRelease: String, recordID: String)

    public var sourceRelease: String {
        switch self {
        case let .manualDeclaration(release), let .exactProductDataset(release, _): release
        }
    }
}

public struct PersonalFoodDatabaseLabelValue: Equatable, Sendable {
    public let value: Double
    public let unit: NutrientUnit
    public let source: PersonalFoodDatabaseValueSource
    public let transform: PersonalFoodDatabaseTransform?
}

public struct PersonalFoodDatabaseEntry: Equatable, Sendable {
    /// Opaque `pfc:` and 12 hex digits; never recomputed.
    public let id: String
    public let brand: String?
    public let title: String
    public let titles: [String]
    public let aliases: [String]
    public let concept: String?
    public let variety: String?
    public let fallbackChain: [String]
    public let category: PersonalFoodDatabaseCategory
    public let productType: PersonalFoodDatabaseProductType
    public let state: PersonalFoodDatabaseState
    public let basis: PersonalFoodDatabaseBasis
    /// In file order; possibly empty.
    public let labelNutrients: [PersonalFoodDatabaseLabelNutrient]
    public let genericReference: PersonalFoodDatabaseGenericReference?
}

/// One label value under its nutrient key, kept in file order. A struct (not a tuple) so the
/// entry's equality is synthesised over every field.
public struct PersonalFoodDatabaseLabelNutrient: Equatable, Sendable {
    public let key: NutrientKey
    public let value: PersonalFoodDatabaseLabelValue
}

public enum PersonalFoodDatabaseSourceID: String, CaseIterable, Sendable {
    case openFoodFacts = "open-food-facts", owner
}

/// A release that a label value cites (import v1 section 4, `sources`).
public struct PersonalFoodDatabaseDeclaredSource: Equatable, Sendable {
    public let sourceReleaseID: String
    public let sourceID: PersonalFoodDatabaseSourceID
    public let releasedAt: PersonalFoodDatabaseDate
    public let artifactSHA256: String
    public let schemaVersion: String
    public let pipelineVersion: String
    public let licence: String
    public let attribution: String
    public let manifestSHA256: String

    /// The ledger's `SourceRelease` for this declared release: a pure function of its fields, so the
    /// same ID always gives the same record (release immutability, import v1 section 4).
    public func sourceRelease() throws -> SourceRelease {
        SourceRelease(
            sourceReleaseID: try ExternalIdentifier(sourceReleaseID, field: "source release"),
            sourceID: try ExternalIdentifier(sourceID.rawValue, field: "source"),
            releasedAt: releasedAt.utcMidnight,
            artifactHash: try SHA256Digest(artifactSHA256),
            schemaVersion: try LedgerText(schemaVersion),
            pipelineVersion: try LedgerText(pipelineVersion),
            licence: try LedgerText(licence),
            attribution: try LedgerText(attribution),
            manifestHash: try SHA256Digest(manifestSHA256)
        )
    }
}

/// An accepted `personal-food-catalogue-v1` or `-v2` file.
public struct PersonalFoodDatabaseFile: Equatable, Sendable {
    /// The file's own schema; it becomes the database release's `schemaVersion`.
    public let schema: PersonalFoodDatabaseSchema
    public let generated: PersonalFoodDatabaseDate
    public let sources: [PersonalFoodDatabaseDeclaredSource]
    /// Each referenced corpus once, with the hash the file was built against.
    public let genericCorpora: [PersonalFoodDatabaseGenericSource: String]
    public let entries: [PersonalFoodDatabaseEntry]
}

/// The database release itself (import v1 section 4): every field a pure function of the file's
/// SHA-256, its `generated` date and its schema, all inside the hashed bytes. The caller computes
/// the digest through `Digesting`.
public enum PersonalFoodDatabaseRelease {
    public static let sourceID = "personal-food-database"
    public static let pipelineVersion = "pfc-resolution-v1"
    public static let licence = "private"
    public static let attribution = "Your food database, built by the owner"

    public static func releaseID(fileSHA256: SHA256Digest) -> String { "pfc:sha256:\(fileSHA256.value)" }

    public static func sourceRelease(fileSHA256: SHA256Digest, generated: PersonalFoodDatabaseDate,
                                     schema: PersonalFoodDatabaseSchema) throws -> SourceRelease {
        SourceRelease(
            sourceReleaseID: try ExternalIdentifier(releaseID(fileSHA256: fileSHA256), field: "source release"),
            sourceID: try ExternalIdentifier(sourceID, field: "source"),
            releasedAt: generated.utcMidnight,
            artifactHash: fileSHA256,
            schemaVersion: try LedgerText(schema.rawValue),
            pipelineVersion: try LedgerText(pipelineVersion),
            licence: try LedgerText(licence),
            attribution: try LedgerText(attribution),
            manifestHash: fileSHA256
        )
    }
}
