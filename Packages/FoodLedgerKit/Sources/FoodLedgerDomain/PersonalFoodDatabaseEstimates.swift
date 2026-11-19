import Foundation

// Labelled estimates on catalogue v2 (docs/personal-food-catalogue-estimates-v2-proposal.md sections
// 2 and 3.3; estimates v1 sections 2.1 and 2.2): the typed form of `estimated_nutrients` and
// `estimate_evidence`. An estimate is never a label value and never measured.

public enum PersonalFoodDatabaseEstimateSourceType: String, CaseIterable, Codable, Sendable {
    case nationalComposition = "national_composition", manufacturerPage = "manufacturer_page", aggregator
    /// A value read from an Open Food Facts nutrition panel photo (label photo estimates v1).
    case productDatasetPhoto = "product_dataset_photo"

    /// The closed list before label photo estimates: every catalogue, export and stored version
    /// that predates them keeps exactly this list.
    public static let estimatesV2List: [Self] = [.nationalComposition, .manufacturerPage, .aggregator]

    /// The closed list of one catalogue schema (phase gate section 1): never `allCases`, so a new
    /// case cannot widen an older version.
    public static func allowed(catalogue schema: PersonalFoodDatabaseSchema) -> [Self] {
        schema == .estimatesV3 ? estimatesV2List + [.productDatasetPhoto] : estimatesV2List
    }
}

public enum PersonalFoodDatabaseEstimatePageAccess: String, CaseIterable, Codable, Sendable {
    case directRead = "direct_read", indexedCopy = "indexed_copy"
}

public enum PersonalFoodDatabaseEstimateStateBasis: String, CaseIterable, Codable, Sendable {
    case sourceStatesIt = "source_states_it", statedAssumption = "stated_assumption", unknown
}

public enum PersonalFoodDatabaseEstimateMethod: String, CaseIterable, Codable, Sendable {
    case direct, derived
    case carriedFromSameFood = "carried_from_same_food", carriedFromSimilarFood = "carried_from_similar_food"
}

/// How strong an estimate's evidence is (contract section 3.3). It describes the evidence, never the
/// food: it has no health meaning and sets no target.
public enum PersonalFoodDatabaseEstimateQuality: String, CaseIterable, Codable, Sendable {
    case high, medium, low

    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}

/// The one transform of a `derived` estimate, with the printed value it was computed from.
public struct PersonalFoodDatabaseEstimateDerivation: Equatable, Sendable {
    public let transformID: String
    public let version: String
    public let sourceValue: Double
    public let sourceUnit: String

    public init(transformID: String, version: String, sourceValue: Double, sourceUnit: String) {
        self.transformID = transformID; self.version = version; self.sourceValue = sourceValue; self.sourceUnit = sourceUnit
    }
}

/// One record of `estimate_evidence`, bound to exactly one value of one entry.
public struct PersonalFoodDatabaseEstimateEvidence: Equatable, Sendable {
    /// `pfe:` and 16 lower-case hex digits; opaque.
    public let id: String
    public let entryID: String
    public let nutrient: NutrientKey
    public let sourceType: PersonalFoodDatabaseEstimateSourceType
    /// Set exactly for `national_composition`.
    public let compositionSource: PersonalFoodDatabaseGenericSource?
    /// A bundled record ID for `national_composition`; otherwise a public HTTPS page URL.
    public let sourceReference: String
    /// Set exactly for the page types.
    public let pageAccess: PersonalFoodDatabaseEstimatePageAccess?
    public let sourceDigest: String?
    public let retrievedOn: PersonalFoodDatabaseDate?
    public let sourceState: String
    public let targetState: String
    public let stateBasis: PersonalFoodDatabaseEstimateStateBasis
    public let method: PersonalFoodDatabaseEstimateMethod
    public let assumption: String
    public let derivation: PersonalFoodDatabaseEstimateDerivation?
    public let quality: PersonalFoodDatabaseEstimateQuality

    public init(id: String, entryID: String, nutrient: NutrientKey, sourceType: PersonalFoodDatabaseEstimateSourceType,
                compositionSource: PersonalFoodDatabaseGenericSource?, sourceReference: String,
                pageAccess: PersonalFoodDatabaseEstimatePageAccess?, sourceDigest: String?,
                retrievedOn: PersonalFoodDatabaseDate?, sourceState: String, targetState: String,
                stateBasis: PersonalFoodDatabaseEstimateStateBasis, method: PersonalFoodDatabaseEstimateMethod,
                assumption: String, derivation: PersonalFoodDatabaseEstimateDerivation?,
                quality: PersonalFoodDatabaseEstimateQuality) {
        self.id = id; self.entryID = entryID; self.nutrient = nutrient; self.sourceType = sourceType
        self.compositionSource = compositionSource; self.sourceReference = sourceReference; self.pageAccess = pageAccess
        self.sourceDigest = sourceDigest; self.retrievedOn = retrievedOn; self.sourceState = sourceState
        self.targetState = targetState; self.stateBasis = stateBasis; self.method = method; self.assumption = assumption
        self.derivation = derivation; self.quality = quality
    }
}

/// One approved estimate under its nutrient key, with its evidence record. The basis is the
/// entry's: there is no per-value basis, so a value on another basis cannot be written.
public struct PersonalFoodDatabaseEstimate: Equatable, Sendable {
    public let key: NutrientKey
    public let value: Double
    public let unit: NutrientUnit
    public let evidence: PersonalFoodDatabaseEstimateEvidence

    public init(key: NutrientKey, value: Double, unit: NutrientUnit, evidence: PersonalFoodDatabaseEstimateEvidence) {
        self.key = key; self.value = value; self.unit = unit; self.evidence = evidence
    }
}

extension PersonalFoodDatabaseEntry {
    /// True when `estimate` cites this entry's own generic reference, whatever its role.
    public func isOwnRecord(_ evidence: PersonalFoodDatabaseEstimateEvidence) -> Bool {
        guard evidence.sourceType == .nationalComposition, let reference = genericReference else { return false }
        return reference.source == evidence.compositionSource && reference.recordID == evidence.sourceReference
    }
}

/// The estimate rules of the codec: the inherited checks of estimates v1 section 2.3 in the R2
/// tool's order with its code strings, then the table of contract section 3.1. It mirrors the
/// skill's `estimates_v2.check` rule for rule, so both give the same codes in the same order.
struct PersonalFoodDatabaseEstimateChecker {
    typealias R = PersonalFoodDatabaseRules
    private(set) var codes: [PersonalFoodDatabaseRuleCode] = []

    static let evidenceKeys = R.set(["id", "entry_id", "nutrient", "approved_as_estimate", "source_type",
        "composition_source", "source_reference", "page_access", "source_digest", "retrieved_on", "source_state",
        "target_state", "state_basis", "method", "assumption", "derivation", "quality"])
    static let estimateKeys = R.set(["value", "unit", "evidence_id"])
    static let derivationKeys = R.set(["transform_id", "version", "source_value"])
    static func sourceTypes(_ schema: PersonalFoodDatabaseSchema) -> Set<PFDText> {
        R.set(PersonalFoodDatabaseEstimateSourceType.allowed(catalogue: schema).map(\.rawValue))
    }
    static let pageAccess = R.set(PersonalFoodDatabaseEstimatePageAccess.allCases.map(\.rawValue))
    static let stateBases = R.set(PersonalFoodDatabaseEstimateStateBasis.allCases.map(\.rawValue))
    static let methods = R.set(PersonalFoodDatabaseEstimateMethod.allCases.map(\.rawValue))
    static let qualities = R.set(PersonalFoodDatabaseEstimateQuality.allCases.map(\.rawValue))
    static let nationalComposition = PFDText("national_composition")
    static let derived = PFDText("derived")
    static let urlLimit = 2048

    private mutating func err(_ code: PersonalFoodDatabaseRuleCode) { codes.append(code) }

    /// `pfe:` and 16 lower-case hex digits.
    static func isEvidenceID(_ t: PFDText) -> Bool {
        let b = t.bytes
        return b.count == 20 && b.starts(with: Array("pfe:".utf8)) && b.dropFirst(4).allSatisfy(R.isLowerHex)
    }

    /// Amendment G8 (docs/personal-food-catalogue-tables-composites-amendment-v1.md): the closed list of
    /// composition-table record addresses that need a query string, each with its one exact parameter.
    /// Returns the address without that query when it matches, the address unchanged when it has no
    /// query, and nil for any other query. Hand-written over bytes, as `estimates_v2.table_query_base`.
    static func tableQueryBase(_ b: [UInt8]) -> [UInt8]? {
        guard let q = b.firstIndex(of: UInt8(ascii: "?")) else { return b }
        let base = Array(b[..<q]), query = Array(b[(q + 1)...])
        func digits(_ s: ArraySlice<UInt8>, _ range: ClosedRange<Int>) -> Bool {
            range.contains(s.count) && s.allSatisfy(R.isDigit)
        }
        if base == Array("https://fooddb.mext.go.jp/details/details.pl".utf8) {
            let key = Array("ITEM_NO=".utf8)
            guard query.starts(with: key) else { return nil }
            let parts = query.dropFirst(key.count).split(separator: UInt8(ascii: "_"), omittingEmptySubsequences: false)
            guard parts.count == 3, digits(parts[0], 1...2), digits(parts[1], 5...5), digits(parts[2], 1...2) else { return nil }
            return base
        }
        let site = Array("https://www.nutritionvalue.org/".utf8), page = Array("_nutritional_value.html".utf8)
        if base.starts(with: site), base.count > site.count + page.count, Array(base.suffix(page.count)) == page,
           query == Array("size=100+g".utf8) {
            // The record name: letters, digits, `_` and `-`, and the encoded comma `%2C` only.
            let name = Array(base.dropFirst(site.count).dropLast(page.count))
            var i = 0, ok = true
            while i < name.count, ok {
                let c = name[i]
                if R.isDigit(c) || (0x41...0x5a).contains(c) || (0x61...0x7a).contains(c) || c == UInt8(ascii: "_") || c == UInt8(ascii: "-") {
                    i += 1
                } else if c == UInt8(ascii: "%"), i + 2 < name.count, name[i + 1] == UInt8(ascii: "2"), name[i + 2] == UInt8(ascii: "C") {
                    i += 3
                } else { ok = false }
            }
            return ok ? base : nil
        }
        return nil
    }

    /// The host of a page URL under the phase gate's grammar (section 3.1 item 7), lower-cased and
    /// without a trailing dot, or nil. Hand-written over bytes, as `estimates_v2.page_host`. A query
    /// string is refused except the closed table addresses of amendment G8 (`tableQueryBase`).
    static func pageHost(_ t: PFDText) -> [UInt8]? {
        let prefix = Array("https://".utf8)
        guard t.bytes.count <= urlLimit, let b = tableQueryBase(t.bytes) else { return nil }
        guard b.starts(with: prefix), b.allSatisfy({ (0x21...0x7e).contains($0) }),
              !b.contains(UInt8(ascii: "?")), !b.contains(UInt8(ascii: "#")) else { return nil }
        let authority = Array(b.dropFirst(prefix.count).prefix { $0 != UInt8(ascii: "/") })
        guard !authority.contains(UInt8(ascii: "@")) else { return nil }
        var host = authority
        if let colon = authority.firstIndex(of: UInt8(ascii: ":")) {
            host = Array(authority[..<colon])
            let port = authority[(colon + 1)...]
            guard (1...5).contains(port.count), port.allSatisfy(R.isDigit) else { return nil }
            let number = port.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
            guard (1...65535).contains(number) else { return nil }
        }
        if host.last == UInt8(ascii: ".") { host.removeLast() }
        let labels = host.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        func isLabelByte(_ c: UInt8) -> Bool {
            R.isDigit(c) || c == UInt8(ascii: "-") || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(c)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(c)
        }
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isLabelByte) }) else { return nil }
        let lower = host.map { (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) ? $0 + 32 : $0 }
        let last = Array(lower.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false).last ?? [])
        guard !last.allSatisfy(R.isDigit), !last.starts(with: Array("0x".utf8)),
              !PFDText(bytes: lower).hasSuffix(Array(".localhost".utf8)) else { return nil }
        return lower
    }

    static func isOpenFoodFactsHost(_ host: [UInt8]) -> Bool {
        host == Array("openfoodfacts.org".utf8) || PFDText(bytes: host).hasSuffix(Array(".openfoodfacts.org".utf8))
    }

    /// `estimates_v2.text_ok`: a string that is not blank, at most `limit` Unicode scalars, and
    /// holds no C0 or C1 control character.
    static func isFreeText(_ v: PFDValue?, limit: Int) -> Bool {
        guard let t = v?.text, !R.isBlank(t) else { return false }
        let scalars = t.string.unicodeScalars
        return scalars.count <= limit && !scalars.contains(where: isControl)
    }

    static func isControl(_ s: Unicode.Scalar) -> Bool { s.value <= 0x1f || (0x7f...0x9f).contains(s.value) }

    static func isDate(_ v: PFDValue?) -> Bool { v?.text.flatMap { PersonalFoodDatabaseDate(ascii: $0.bytes) } != nil }

    /// `estimates_v2.derivation_shape_ok`.
    static func derivation(_ d: PFDValue?) -> (id: PFDText, version: PFDText, value: Double, unit: PFDText)? {
        guard let d, d.keys == derivationKeys, let id = d["transform_id"]?.text, !id.bytes.isEmpty,
              let version = d["version"]?.text, !version.bytes.isEmpty, let sv = d["source_value"],
              sv.keys == R.sourceValueKeys, let value = sv["value"]?.nutrientNumber, let unit = sv["unit"]?.text,
              !unit.bytes.isEmpty else { return nil }
        return (id, version, value, unit)
    }

    /// `estimates_v2.transform_matches`: the estimate equals its declared transform of the printed
    /// value, within the inherited tolerance; outside the closed list or its scope it never matches.
    static func transformMatches(_ d: PFDValue?, key: NutrientKey, value: Double?) -> Bool {
        guard let parts = derivation(d), let rule = R.transform(id: parts.id, version: parts.version),
              rule.sourceUnit == parts.unit, rule.nutrient == key, let value else { return false }
        return !R.transformArithmeticFails(expected: rule.apply(parts.value), value: value)
    }

    /// `estimates_v2.check_record`; in a v3 file a photo record takes the photo rules in place of
    /// the page-type checks.
    private mutating func checkRecord(_ rec: PFDValue, corpora: Set<PFDText>, schema: PersonalFoodDatabaseSchema) {
        guard rec.keys == Self.evidenceKeys else { return err(.evidenceKeys) }
        if case .bool(true)? = rec["approved_as_estimate"] {} else { err(.notApproved) }
        guard let sourceType = rec["source_type"]?.text, Self.sourceTypes(schema).contains(sourceType),
              let stateBasis = rec["state_basis"]?.text, Self.stateBases.contains(stateBasis),
              let method = rec["method"]?.text, Self.methods.contains(method),
              let quality = rec["quality"]?.text, Self.qualities.contains(quality) else { return err(.token) }
        if sourceType == PersonalFoodDatabasePhotoRules.token {
            if PersonalFoodDatabasePhotoRules.recordFails(rec) { err(.photoFields) }
        } else if sourceType == Self.nationalComposition {
            let source = rec["composition_source"]?.text
            if let source, R.genericSources.contains(source), rec["page_access"]?.isNull == true {
                if !corpora.contains(source) { err(.corpusUndeclared) }
            } else {
                err(.typeFields)
            }
            if let reference = rec["source_reference"]?.text, !reference.bytes.isEmpty,
               !reference.string.unicodeScalars.contains(where: Self.isControl),
               (source == R.tfda) == reference.hasPrefix(R.tfdaPrefix) {} else { err(.sourceReference) }
            if rec["retrieved_on"]?.isNull != true, !Self.isDate(rec["retrieved_on"]) { err(.date) }
        } else {
            if rec["composition_source"]?.isNull != true
                || !(rec["page_access"]?.text.map(Self.pageAccess.contains) ?? false) { err(.typeFields) }
            if let host = rec["source_reference"]?.text.flatMap(Self.pageHost) {
                if Self.isOpenFoodFactsHost(host) { err(.openFoodFactsHost) }
            } else {
                err(.sourceReference)
            }
            if !Self.isDate(rec["retrieved_on"]) { err(.date) }
        }
        if rec["source_digest"]?.isNull != true, !(rec["source_digest"]?.text.map { R.isHex64($0.bytes) } ?? false) { err(.digest) }
        if !(Self.isFreeText(rec["source_state"], limit: 200) && Self.isFreeText(rec["target_state"], limit: 200)
             && Self.isFreeText(rec["assumption"], limit: 500)) { err(.freeText) }
        if method == Self.derived {
            if rec["derivation"]?.isNull == true {
                err(.derivationMissing)
            } else if Self.derivation(rec["derivation"]) == nil {
                err(.derivationShape)
            }
        } else if rec["derivation"]?.isNull != true {
            err(.derivationUnexpected)
        }
    }

    /// The highest tier the codec accepts for a record (contract section 3.3). A national estimate on a
    /// packaged composite dish is a generic recipe, never this product's: at most `low` (gap estimates
    /// amendment G1, docs/personal-food-catalogue-gap-estimates-v1-amendment.md). An estimate from the
    /// entry's own `merge` record (which the app did not merge) is at most `medium`: the record does not
    /// say it describes the entry's state (amendment G4, docs/personal-food-catalogue-own-merge-amendment-v1.md).
    /// A web page value (`aggregator` or `manufacturer_page`) carried from a similar food onto a packaged
    /// composite dish is a generic recipe too: at most `low` (amendment G5,
    /// docs/personal-food-catalogue-composite-web-amendment-v1.md). A page about this product, and a label
    /// photo, keep their ceilings.
    static func ceiling(method: PFDText, stateBasis: PFDText, pageAccess: PFDText?, national: Bool, own: Bool,
                        photo: Bool = false, composite: Bool = false, ownMerge: Bool = false,
                        webSimilar: Bool = false) -> PersonalFoodDatabaseEstimateQuality {
        if stateBasis == PFDText("unknown") { return .low }
        if composite, national || webSimilar { return .low }
        if photo || ownMerge { return .medium }
        if method == PFDText("carried_from_same_food") || method == PFDText("direct"),
           stateBasis == PFDText("source_states_it"), pageAccess != PFDText("indexed_copy"), !national || own {
            return .high
        }
        return .medium
    }

    /// `estimates_v2.table_codes`: the rows of contract section 3.1 a bound, valid record matches,
    /// in table order. Every field read here was validated before the call.
    static func tableCodes(record rec: PFDValue, item: PFDValue) -> [PersonalFoodDatabaseRuleCode] {
        guard let sourceType = rec["source_type"]?.text, let method = rec["method"]?.text,
              let stateBasis = rec["state_basis"]?.text,
              let quality = rec["quality"]?.text.flatMap({ PersonalFoodDatabaseEstimateQuality(rawValue: $0.string) })
        else { return [] }
        let national = sourceType == nationalComposition
        let ref = item["generic_reference"]
        let own = national && ref?.isNull == false && ref?["source"]?.text == rec["composition_source"]?.text
            && ref?["source"]?.text != nil && ref?["record_id"]?.text == rec["source_reference"]?.text
        let role = ref?["role"]?.text, match = ref?["match"]?.text
        let candidate = own && role == PFDText("candidate")
        // Amendment G4: `estimate-own-merge` is an importer rule (only the record shows whether the app
        // merges it); an own `merge` record is otherwise judged as an own same-food record, never held.
        let ownMerge = own && role == R.merge
        let sameFood = match == PFDText("same_food_same_state")
        var codes: [PersonalFoodDatabaseRuleCode] = []
        if candidate || ownMerge,
           method != (sameFood ? PFDText("carried_from_same_food") : PFDText("carried_from_similar_food")) {
            codes.append(.estimateOwnMethod)
        }
        if candidate || ownMerge, stateBasis == PFDText("unknown") { codes.append(.estimateOwnState) }
        if candidate, sameFood, item["state"]?.text == PFDText("raw") || item["state"]?.text == PFDText("cooked") {
            codes.append(.estimateOwnHeld)
        }
        let photo = sourceType == PersonalFoodDatabasePhotoRules.token
        // Amendment G5: a web page carried from a similar food (never a photo, never a page about this product).
        let webSimilar = (sourceType == PFDText("aggregator") || sourceType == PFDText("manufacturer_page"))
            && method == PFDText("carried_from_similar_food")
        if quality.rank > ceiling(method: method, stateBasis: stateBasis, pageAccess: rec["page_access"]?.text,
                                  national: national, own: own, photo: photo,
                                  composite: item["product_type"]?.text == PFDText("packaged_composite"),
                                  ownMerge: ownMerge, webSimilar: webSimilar).rank {
            codes.append(.estimateQuality)
        }
        // `estimate-basis` is an importer rule since amendment G2: only the record shows whether a per
        // 100 ml entry's value is from a per 100 ml record or a quantified zero.
        if photo { codes += PersonalFoodDatabasePhotoRules.relationCodes(record: rec, item: item) }
        return codes
    }

    /// `estimates_v2.check`. `failedItems` are the indexes of entries that raised a code in the v2
    /// part and `duplicateIDs` the entry IDs that occur more than once: their records get no table row.
    mutating func check(_ doc: PFDValue, failedItems: Set<Int>, duplicateIDs: Set<PFDText>,
                        schema: PersonalFoodDatabaseSchema = .estimatesV2) {
        guard let evidence = doc["estimate_evidence"]?.items, let items = doc["items"]?.items else { return }
        let itemKeys = R.itemKeys.union([PFDText("estimated_nutrients")])
        var corpora = Set<PFDText>()
        for c in doc["generic_corpora"]?.items ?? [] {
            if let source = c["source"]?.text { corpora.insert(source) }
        }
        var records: [PFDText: PFDValue] = [:]
        var order: [PFDText] = []
        var faulty = Set<PFDText>()
        var previous = PFDText(bytes: [])
        for rec in evidence {
            guard let rid = rec["id"]?.text, Self.isEvidenceID(rid) else {
                err(.evidenceID)
                continue
            }
            let before = codes.count
            if records[rid] != nil {
                err(.evidenceDuplicate)
            } else if rid <= previous {
                err(.evidenceOrder)
            }
            previous = max(previous, rid)
            if records[rid] == nil { order.append(rid) }
            records[rid] = rec
            checkRecord(rec, corpora: corpora, schema: schema)
            if codes.count > before { faulty.insert(rid) }
        }
        var used: [PFDText: Int] = [:]
        var citedBy: [PFDText: Int] = [:]
        for (n, item) in items.enumerated() {
            guard item.keys == itemKeys else { continue }  // item-keys was raised once, in the v2 part
            guard let estimates = item["estimated_nutrients"]?.members else {
                err(.estimatedNutrients)
                continue
            }
            let labels = item["label_nutrients"]?.keys
            let entryID = item["id"]?.text
            for (key, v) in estimates {
                guard let canonical = R.canonicalUnits[key] else {
                    err(.unknownNutrient)
                    continue
                }
                guard v.keys == Self.estimateKeys else {
                    err(.estimateKeys)
                    continue
                }
                let before = codes.count
                if v["unit"]?.text != PFDText(bytes: Array(canonical.unit.rawValue.utf8)) { err(.unit) }
                let number = v["value"]?.nutrientNumber
                if number == nil { err(.value) }
                if labels?.contains(key) == true { err(.labelAndEstimate) }
                guard let rid = v["evidence_id"]?.text, let rec = records[rid] else {
                    err(.evidenceDangling)
                    continue
                }
                used[rid, default: 0] += 1
                citedBy[rid] = n
                if entryID == nil || rec["entry_id"]?.text != entryID || rec["nutrient"]?.text != key { err(.evidenceMismatch) }
                if rec["method"]?.text == Self.derived, let d = rec["derivation"], !d.isNull,
                   !Self.transformMatches(d, key: canonical.key, value: number) { err(.derivation) }
                if codes.count > before { faulty.insert(rid) }
            }
        }
        for rid in order where used[rid, default: 0] != 1 {
            err(.evidenceUnusedOrShared)
            faulty.insert(rid)
        }
        var seen = Set<PFDText>()
        for rec in evidence {
            guard let rid = rec["id"]?.text, records[rid] != nil, !faulty.contains(rid), !seen.contains(rid),
                  let n = citedBy[rid] else { continue }
            seen.insert(rid)
            let item = items[n]
            if failedItems.contains(n) { continue }
            if let id = item["id"]?.text, duplicateIDs.contains(id) { continue }
            codes += Self.tableCodes(record: rec, item: item)
        }
        if schema == .estimatesV3, !PersonalFoodDatabasePhotoRules.hasPhotoEstimate(doc) { err(.photoMissing) }
    }
}

extension PersonalFoodDatabaseBuilder {
    /// The entry's estimates from a tree the checker accepted, in file order.
    static func estimates(_ item: PFDValue, records: [PFDText: PFDValue]) -> [PersonalFoodDatabaseEstimate]? {
        guard let members = item["estimated_nutrients"]?.members else { return [] }
        var out: [PersonalFoodDatabaseEstimate] = []
        for (key, v) in members {
            guard let canonical = R.canonicalUnits[key], let value = v["value"]?.nutrientNumber,
                  let rid = v["evidence_id"]?.text, let rec = records[rid],
                  let evidence = estimateEvidence(rec, id: rid, nutrient: canonical.key) else { return nil }
            out.append(PersonalFoodDatabaseEstimate(key: canonical.key, value: value, unit: canonical.unit, evidence: evidence))
        }
        return out
    }

    static func estimateEvidence(_ rec: PFDValue, id: PFDText, nutrient: NutrientKey) -> PersonalFoodDatabaseEstimateEvidence? {
        guard let entryID = rec["entry_id"]?.text?.string,
              let sourceType = rec["source_type"]?.text.flatMap({ PersonalFoodDatabaseEstimateSourceType(rawValue: $0.string) }),
              let reference = rec["source_reference"]?.text?.string,
              let sourceState = rec["source_state"]?.text?.string, let targetState = rec["target_state"]?.text?.string,
              let stateBasis = rec["state_basis"]?.text.flatMap({ PersonalFoodDatabaseEstimateStateBasis(rawValue: $0.string) }),
              let method = rec["method"]?.text.flatMap({ PersonalFoodDatabaseEstimateMethod(rawValue: $0.string) }),
              let assumption = rec["assumption"]?.text?.string,
              let quality = rec["quality"]?.text.flatMap({ PersonalFoodDatabaseEstimateQuality(rawValue: $0.string) })
        else { return nil }
        let composition = rec["composition_source"]?.text.flatMap { PersonalFoodDatabaseGenericSource(rawValue: $0.string) }
        let access = rec["page_access"]?.text.flatMap { PersonalFoodDatabaseEstimatePageAccess(rawValue: $0.string) }
        guard (sourceType == .nationalComposition) == (composition != nil), (sourceType == .nationalComposition) == (access == nil)
        else { return nil }
        var derivation: PersonalFoodDatabaseEstimateDerivation?
        if method == .derived {
            guard let parts = PersonalFoodDatabaseEstimateChecker.derivation(rec["derivation"]) else { return nil }
            derivation = PersonalFoodDatabaseEstimateDerivation(transformID: parts.id.string, version: parts.version.string,
                                                                sourceValue: parts.value, sourceUnit: parts.unit.string)
        }
        return PersonalFoodDatabaseEstimateEvidence(
            id: id.string, entryID: entryID, nutrient: nutrient, sourceType: sourceType, compositionSource: composition,
            sourceReference: reference, pageAccess: access, sourceDigest: rec["source_digest"]?.text?.string,
            retrievedOn: rec["retrieved_on"]?.text.flatMap { PersonalFoodDatabaseDate(ascii: $0.bytes) },
            sourceState: sourceState, targetState: targetState, stateBasis: stateBasis, method: method,
            assumption: assumption, derivation: derivation, quality: quality)
    }
}

/// What an estimate check needs from one bundled composition record (contract section 7): its
/// nutrients as the adapter stores them, its decisive identity and its edible quantity.
public struct GenericRecordFacts: Equatable, Sendable {
    public let nutrients: NutrientSet
    public let identity: DecisiveIdentity
    public let edibleQuantity: EdibleQuantityIdentity

    public init(nutrients: NutrientSet, identity: DecisiveIdentity, edibleQuantity: EdibleQuantityIdentity) {
        self.nutrients = nutrients; self.identity = identity; self.edibleQuantity = edibleQuantity
    }

    /// The record's quantified value for `key` in the key's canonical unit, or nil when the record
    /// has none (missing, trace, bounded or unquantified): a file value can never stand in for it.
    public func quantified(_ key: NutrientKey) -> Double? {
        guard let entry = nutrients.entries.first(where: { $0.key == key }), entry.status == .resolved else { return nil }
        switch entry.value {
        case let .measured(value), let .augmented(value): return value.unit == key.canonicalUnit ? value.amount : nil
        case .bounded, .unknown: return nil
        }
    }

    /// Per 100 ml with a known 100 ml quantity (gap estimates amendment G2b).
    public var isPer100Millilitres: Bool {
        guard identity.servingBasis == .per100Millilitres, case let .known(quantity, conversion) = edibleQuantity,
              conversion == nil else { return false }
        return quantity.unit == .millilitres && quantity.value == 100
    }

    /// Per 100 g with a known 100 g edible quantity, as a merge needs.
    public var isPer100GramsEdible: Bool {
        guard identity.servingBasis == .per100Grams, case let .known(quantity, conversion) = edibleQuantity,
              conversion == nil else { return false }
        return quantity.unit == .grams && quantity.value == 100
    }
}

/// The per-facet comparison for approved estimates (contract section 3.2): the equality
/// `IdentityCompatibility` uses, except that a facet unknown on either side does not contradict,
/// and `as_sold` and `raw` are compatible in both directions (owner decision, 16 November 2026).
/// It covers the same decisive facets as `IdentityCompatibility`; serving basis and edible quantity
/// are separate rules of the estimate policy.
public enum EstimateIdentityComparison {
    /// The decisive facets both comparisons cover.
    public static let facets: [IdentityContradiction] = [.preparation, .bone, .skin, .drained, .packingMedium, .fortification]

    public static func preparationContradicts(_ a: PreparationState, _ b: PreparationState) -> Bool {
        if a.kind == .unknown || b.kind == .unknown { return false }
        let pair: Set<PreparationKind> = [a.kind, b.kind]
        if pair == [.asSold, .raw] { return false }
        return a != b
    }

    /// The facets known on both sides and different.
    public static func contradictions(record: DecisiveIdentity, confirmed: DecisiveIdentity) -> [IdentityContradiction] {
        var result: [IdentityContradiction] = []
        if preparationContradicts(record.preparation, confirmed.preparation) { result.append(.preparation) }
        if record.bone != .unknown, confirmed.bone != .unknown, record.bone != confirmed.bone { result.append(.bone) }
        if record.skin != .unknown, confirmed.skin != .unknown, record.skin != confirmed.skin { result.append(.skin) }
        if record.drained != .unknown, confirmed.drained != .unknown, record.drained != confirmed.drained { result.append(.drained) }
        if record.packingMedium != .unknown, confirmed.packingMedium != .unknown, record.packingMedium != confirmed.packingMedium {
            result.append(.packingMedium)
        }
        if record.fortification != .unknown, confirmed.fortification != .unknown, record.fortification != confirmed.fortification {
            result.append(.fortification)
        }
        return result
    }
}
