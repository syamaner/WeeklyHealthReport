import Foundation

/// The pure decoder for `personal-food-catalogue-v1` (import v1 sections 4 to 4.2) and `-v2` (import
/// v2 section 3: v1 plus Open Food Facts projection v6). A v1 file gets exactly the v1 rules. It
/// applies the rules of the skill's `export_v1._check` in the same order with the same codes,
/// collecting every failure rather than stopping at the first, and builds the typed file only when
/// none fails. It never traps on a malformed file: every unexpected type is a rule failure.
///
/// The phase 2 estimates decoder reuses the module-internal checks below
/// (`PersonalFoodDatabaseRules`), so the two schemas cannot drift.
public enum PersonalFoodDatabaseCodec {
    public static let limitItems = 20_000
    /// The file size limit of import v1 section 4, for a caller's check before reading a picked file.
    public static let limitBytes = PersonalFoodDatabaseJSON.limitBytes

    public static func decode(_ data: Data) -> Result<PersonalFoodDatabaseFile, PersonalFoodDatabaseRejection> {
        let root: PersonalFoodDatabaseJSONValue
        switch PersonalFoodDatabaseJSON.read(data) {
        case let .failure(code): return .failure(PersonalFoodDatabaseRejection(codes: [code]))
        case let .success(value): root = value
        }
        var checker = PersonalFoodDatabaseChecker()
        checker.check(root)
        guard checker.codes.isEmpty else { return .failure(PersonalFoodDatabaseRejection(codes: checker.codes)) }
        guard let file = PersonalFoodDatabaseBuilder.file(root) else {
            // Unreachable when the checks above are complete; refused rather than trapped.
            return .failure(PersonalFoodDatabaseRejection(codes: [.malformed]))
        }
        return .success(file)
    }
}

typealias PFDText = PersonalFoodDatabaseText
typealias PFDValue = PersonalFoodDatabaseJSONValue

extension PersonalFoodDatabaseJSONValue {
    var members: [(key: PFDText, value: PFDValue)]? {
        if case let .object(m) = self { m } else { nil }
    }

    var items: [PFDValue]? {
        if case let .array(a) = self { a } else { nil }
    }

    var text: PFDText? {
        if case let .string(s) = self { s } else { nil }
    }

    var isNull: Bool {
        if case .null = self { true } else { false }
    }

    var keys: Set<PFDText>? { members.map { Set($0.map(\.key)) } }

    /// The member for `key`; keys are unique once the reader has accepted the file.
    subscript(_ key: StaticString) -> PFDValue? {
        let k = PFDText(key)
        return members?.first { $0.key == k }?.value
    }

    /// `export_v1._num`: a finite, non-negative number below 1e15, never a boolean.
    var nutrientNumber: Double? {
        guard case let .number(d) = self, d.isFinite, d >= 0, abs(d) < 1e15 else { return nil }
        return d + 0.0  // normalises -0 to 0
    }

    func isString(_ literal: PFDText) -> Bool { text == literal }
}

/// Shared rule tables and predicates (import v1 section 4), keyed by exact bytes.
enum PersonalFoodDatabaseRules {
    static func set(_ values: [String]) -> Set<PFDText> { Set(values.map { PFDText(bytes: Array($0.utf8)) }) }

    static let topKeys = set(["schema", "generated", "sources", "generic_corpora", "items"])
    static let itemKeys = set(["id", "brand", "title", "titles", "aliases", "concept", "variety", "fallback_chain",
                               "category", "product_type", "state", "basis", "label_nutrients", "generic_reference"])
    static let valueKeys = set(["value", "unit", "source_kind", "source_release", "record_id", "match"])
    static let valueOptional = set(["transforms", "source_value"])
    static let referenceKeys = set(["source", "corpus_sha256", "record_id", "match", "role"])
    static let sourceKeys = set(["source_release_id", "source_id", "released_at", "artifact_sha256", "schema_version",
                                 "pipeline_version", "licence", "attribution", "manifest_sha256"])
    static let corpusKeys = set(["source", "corpus_sha256"])
    static let transformKeys = set(["transform_id", "version"])
    static let sourceValueKeys = set(["value", "unit"])
    static let sourceValueKeysWithServing = set(["value", "unit", "serving"])
    static let servingKeys = set(["quantity", "unit"])

    static let categories = set(PersonalFoodDatabaseCategory.allCases.map(\.rawValue))
    static let productTypes = set(PersonalFoodDatabaseProductType.allCases.map(\.rawValue))
    static let states = set(PersonalFoodDatabaseState.allCases.map(\.rawValue))
    static let bases = set(PersonalFoodDatabaseBasis.allCases.map(\.rawValue))
    static let genericSources = set(PersonalFoodDatabaseGenericSource.allCases.map(\.rawValue))
    static let genericMatches = set(PersonalFoodDatabaseReferenceMatch.allCases.map(\.rawValue))
    static let roles = set(PersonalFoodDatabaseReferenceRole.allCases.map(\.rawValue))

    /// Canonical units by nutrient key, from `NutrientKey` (a test pins it to `export_v1.CANON_UNITS`).
    static let canonicalUnits: [PFDText: (key: NutrientKey, unit: NutrientUnit)] = Dictionary(
        uniqueKeysWithValues: NutrientKey.allCases.map { (PFDText(bytes: Array($0.rawValue.utf8)), ($0, $0.canonicalUnit)) })

    static let manualDeclaration = PFDText("manual_declaration")
    static let exactProductDataset = PFDText("exact_product_dataset")
    static let owner = PFDText("owner")
    static let probable = PFDText("probable")
    static let openFoodFacts = PFDText("open-food-facts")
    static let merge = PFDText("merge")
    static let tfda = PFDText("tfda")
    static let tfdaPrefix = PFDText("tfda:")

    /// Transforms of import v1 section 4 for this schema only, each limited to one nutrient, source
    /// unit and source kind. Kept apart from `NutrientDerivation.calculatedTransforms`, which lists
    /// calculations only (`mass-g-to-mg` is a unit conversion). The arithmetic is `export_v1`'s.
    struct Transform {
        let nutrient: NutrientKey
        let sourceUnit: PFDText
        let sourceKind: PFDText
        let apply: @Sendable (Double) -> Double
    }

    static let transforms: [[UInt8]: Transform] = [
        Array("salt_to_sodium_v1|pasted-label-conversions-v1".utf8):
            Transform(nutrient: .sodium, sourceUnit: PFDText("g"), sourceKind: manualDeclaration) { $0 / 2.5 * 1000 },
        Array("kj_to_kcal_v1|pasted-label-conversions-v1".utf8):
            Transform(nutrient: .energyConsumed, sourceUnit: PFDText("kJ"), sourceKind: manualDeclaration) { $0 / 4.184 },
        Array("mass-g-to-mg|v1".utf8):
            Transform(nutrient: .sodium, sourceUnit: PFDText("g"), sourceKind: exactProductDataset) { $0 * 1000 },
    ]

    static func transform(id: PFDText, version: PFDText) -> Transform? {
        transforms[id.bytes + [UInt8(ascii: "|")] + version.bytes]
    }

    // Import v2 section 3: the app's per-serving scaling (`OpenFoodFactsServingRule`).
    static let massGToMG = (id: PFDText("mass-g-to-mg"), version: PFDText("v1"))
    static let servingToHundred = (id: PFDText(bytes: Array(OpenFoodFactsServingRule.transformID.utf8)),
                                   version: PFDText(bytes: Array(OpenFoodFactsServingRule.transformVersion.utf8)))
    /// The eight Open Food Facts fields `OpenFoodFactsLookup.project` admits.
    static let servingNutrients: Set<NutrientKey> = [.energyConsumed, .protein, .carbohydrates, .fatTotal, .fatSaturated,
                                                     .fiber, .sugar, .sodium]
    static let offV6 = PFDText(bytes: Array(OpenFoodFactsServingRule.projectionVersion.utf8))
    static let servingUnits: [PFDText: PFDText] = [PFDText("per_100_g"): PFDText("g"),
                                                   PFDText("per_100_ml_as_labelled"): PFDText("ml")]

    /// `export_v1._serving_quantity_ok`: a finite number above 0 and below 1e15, never a boolean.
    static func servingQuantity(_ v: PFDValue?) -> Double? {
        guard case let .number(d)? = v, d.isFinite, d > 0, d < 1e15 else { return nil }
        return d
    }

    static let tolerance = 0.005

    /// `export_v1`: refused when `abs(f(sv) - v) > 0.005 * abs(f(sv)) + 1e-9`.
    static func transformArithmeticFails(expected: Double, value: Double) -> Bool {
        abs(expected - value) > tolerance * abs(expected) + 1e-9
    }

    static func isDigit(_ b: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b) }
    static func isLowerHex(_ b: UInt8) -> Bool { isDigit(b) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(b) }

    static func isHex64(_ bytes: some Collection<UInt8>) -> Bool { bytes.count == 64 && bytes.allSatisfy(isLowerHex) }

    /// `pfc:` and 12 lower-case hex digits.
    static func isEntryID(_ t: PFDText) -> Bool {
        let b = t.bytes
        return b.count == 16 && b.starts(with: Array("pfc:".utf8)) && b.dropFirst(4).allSatisfy(isLowerHex)
    }

    /// `off:gtin:` and 14 ASCII digits.
    static func isGTINRecordID(_ t: PFDText) -> Bool {
        let b = t.bytes
        return b.count == 23 && b.starts(with: Array("off:gtin:".utf8)) && b.dropFirst(9).allSatisfy(isDigit)
    }

    /// `YYYY-MM-DDT00:00:00Z` on a real date.
    static func utcDate(_ t: PFDText) -> PersonalFoodDatabaseDate? {
        let b = t.bytes
        guard b.count == 20, Array(b[10...]) == Array("T00:00:00Z".utf8) else { return nil }
        return PersonalFoodDatabaseDate(ascii: b[0..<10])
    }

    /// The release ID forms of import v1 section 4 (and v2, which adds projection v6); returns the
    /// hash in the ID.
    static func releaseHash(_ t: PFDText, sourceID: PFDText, v2: Bool) -> [UInt8]? {
        let b = t.bytes
        if sourceID == openFoodFacts {
            // pfc-off:sha256:<64 hex>:projection:off-product-projection-v[45] (v2: v[456]):retrieved:DDDD-DD-DD
            let head = Array("pfc-off:sha256:".utf8), mid = Array(":projection:off-product-projection-v".utf8)
            let tail = Array(":retrieved:".utf8)
            let total = head.count + 64 + mid.count + 1 + tail.count + 10
            guard b.count == total, b.starts(with: head) else { return nil }
            let hash = Array(b[head.count..<head.count + 64])
            var i = head.count + 64
            guard isHex64(hash), Array(b[i..<i + mid.count]) == mid else { return nil }
            i += mid.count
            guard b[i] == UInt8(ascii: "4") || b[i] == UInt8(ascii: "5") || (v2 && b[i] == UInt8(ascii: "6")) else { return nil }
            i += 1
            guard Array(b[i..<i + tail.count]) == tail else { return nil }
            i += tail.count
            let date = b[i...]
            for (k, c) in date.enumerated() where !(k == 4 || k == 7 ? c == UInt8(ascii: "-") : isDigit(c)) { return nil }
            return hash
        }
        if sourceID == owner {
            let head = Array("owner:sha256:".utf8)
            guard b.count == head.count + 64, b.starts(with: head), isHex64(b[head.count...]) else { return nil }
            return Array(b[head.count...])
        }
        return nil
    }

    /// The colon-separated part `n` of a release ID, as Python's `split(":")[n]`.
    static func part(_ t: PFDText, _ n: Int) -> [UInt8] {
        let parts = t.bytes.split(separator: UInt8(ascii: ":"), omittingEmptySubsequences: false)
        return n < parts.count ? Array(parts[n]) : []
    }

    static let offLicence = PFDText(bytes: Array(
        "ODbL 1.0 https://opendatacommons.org/licenses/odbl/1-0/; contents: https://opendatacommons.org/licenses/dbcl/1-0/".utf8))
    static let offSchema = PFDText("off-v3.6-product-record")
    static let offProjections = set(["off-product-projection-v4", "off-product-projection-v5"])
    static let offProjectionsV2 = offProjections.union([offV6])
    static let offAttributionPrefix = Array("Open Food Facts \u{00B7} https://world.openfoodfacts.org/product/".utf8)
    static let ownerSchema = PFDText("pfc-intake-label-v1")
    static let ownerPipeline = PFDText("personal-food-catalogue-skill-v1")
    static let ownerLicence = PFDText("private")
    static let ownerAttribution = PFDText("Label values typed or confirmed by the owner")

    static func offAttributionOK(_ t: PFDText) -> Bool {
        let b = t.bytes
        guard b.starts(with: offAttributionPrefix) else { return false }
        let digits = b.dropFirst(offAttributionPrefix.count)
        return (8...14).contains(digits.count) && digits.allSatisfy(isDigit)
    }

    /// The characters Python's `str.isspace` accepts, so the `title` rule matches `strip()`.
    static let pythonWhitespace: Set<UInt32> = Set([0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0,
                                                    0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]).union(0x2000...0x200A)

    static func isBlank(_ t: PFDText) -> Bool {
        t.string.unicodeScalars.allSatisfy { pythonWhitespace.contains($0.value) }
    }

    static func isStringList(_ v: PFDValue) -> Bool { v.items?.allSatisfy { $0.text != nil } ?? false }
    static func isOptionalString(_ v: PFDValue) -> Bool { v.isNull || v.text != nil }
}

/// `export_v1._check`, rule for rule.
struct PersonalFoodDatabaseChecker {
    typealias R = PersonalFoodDatabaseRules
    private(set) var codes: [PersonalFoodDatabaseRuleCode] = []

    /// A declared release: its source ID and pipeline version.
    struct Declared {
        let kind: PFDText
        let pipeline: PFDText
    }

    /// One value's serving for the v2 `serving-mismatch` rule; nil when it was not scaled.
    struct Serving: Hashable {
        let quantity: Double
        let unit: PFDText
    }

    private mutating func err(_ code: PersonalFoodDatabaseRuleCode) { codes.append(code) }

    mutating func check(_ doc: PFDValue) {
        guard let keys = doc.keys, keys == R.topKeys,
              let schema = doc["schema"], let generated = doc["generated"], let sources = doc["sources"],
              let corporaValue = doc["generic_corpora"], let itemsValue = doc["items"] else {
            return err(.topKeys)
        }
        // An unknown schema keeps the v1 rules for the rest of the file, as `export_v1` does.
        let v2 = schema.isString(PFDText(bytes: Array(PersonalFoodDatabaseSchema.v2.rawValue.utf8)))
        if !schema.isString(PFDText(bytes: Array(PersonalFoodDatabaseSchema.v1.rawValue.utf8))) && !v2 { err(.schema) }
        if generated.text.flatMap({ PersonalFoodDatabaseDate(ascii: $0.bytes) }) == nil { err(.generated) }

        var declared: [PFDText: Declared] = [:]  // release ID -> source ID and pipeline
        if sources.items == nil { err(.sources) }
        for s in sources.items ?? [] {
            guard s.keys == R.sourceKeys,
                  let fields = s.members, fields.allSatisfy({ ($0.value.text?.bytes.isEmpty == false) }),
                  let sid = s["source_release_id"]?.text, let kind = s["source_id"]?.text,
                  let releasedAt = s["released_at"]?.text, let artifact = s["artifact_sha256"]?.text,
                  let manifest = s["manifest_sha256"]?.text, let schemaVersion = s["schema_version"]?.text,
                  let pipeline = s["pipeline_version"]?.text, let licence = s["licence"]?.text,
                  let attribution = s["attribution"]?.text else {
                err(.sourceFields)
                continue
            }
            guard let idHash = R.releaseHash(sid, sourceID: kind, v2: v2) else {
                err(.sourceForm)
                continue
            }
            if artifact.bytes != idHash || manifest.bytes != idHash { err(.sourceHash) }
            let isOFF = kind == R.openFoodFacts
            let dateOK = R.utcDate(releasedAt) != nil
                && (!isOFF || sid.hasSuffix(Array(":retrieved:".utf8) + releasedAt.bytes.prefix(10)))
            if !dateOK { err(.sourceDate) }
            let pinsOK: Bool
            if isOFF {
                pinsOK = schemaVersion == R.offSchema && licence == R.offLicence
                    && (v2 ? R.offProjectionsV2 : R.offProjections).contains(pipeline) && R.part(sid, 4) == pipeline.bytes
                    && R.offAttributionOK(attribution)
            } else {
                pinsOK = schemaVersion == R.ownerSchema && licence == R.ownerLicence
                    && pipeline == R.ownerPipeline && attribution == R.ownerAttribution
            }
            if !pinsOK { err(.sourcePins) }
            if declared[sid] != nil { err(.sourceDuplicate) }
            declared[sid] = Declared(kind: kind, pipeline: pipeline)
        }

        var corpora: [PFDText: PFDText] = [:]
        for c in corporaValue.items ?? [.null] {
            guard c.keys == R.corpusKeys, let source = c["source"]?.text, R.genericSources.contains(source),
                  let hash = c["corpus_sha256"]?.text, R.isHex64(hash.bytes), corpora[source] == nil else {
                err(.corpus)
                continue
            }
            corpora[source] = hash
        }

        guard let items = itemsValue.items else { return err(.items) }
        if items.count > PersonalFoodDatabaseCodec.limitItems { err(.count) }
        var ids = Set<PFDText>()
        var previous = PFDText(bytes: [])
        for item in items {
            guard item.keys == R.itemKeys else {
                err(.itemKeys)
                continue
            }
            guard let title = item["title"]?.text, !R.isBlank(title), let brand = item["brand"],
                  R.isOptionalString(brand) else {
                err(.title)
                continue
            }
            guard let id = item["id"]?.text, R.isEntryID(id) else {
                err(.idForm)
                continue
            }
            if ids.contains(id) {
                err(.idDuplicate)
            } else if id <= previous {
                err(.idOrder)
            }
            ids.insert(id)
            previous = max(previous, id)
            let typesOK = [item["titles"], item["aliases"], item["fallback_chain"]].allSatisfy { $0.map(R.isStringList) ?? false }
                && [item["concept"], item["variety"]].allSatisfy { $0.map(R.isOptionalString) ?? false }
            if !typesOK { err(.itemTypes) }
            guard let category = item["category"]?.text, R.categories.contains(category),
                  let productType = item["product_type"]?.text, R.productTypes.contains(productType),
                  let state = item["state"]?.text, R.states.contains(state),
                  let basis = item["basis"]?.text, R.bases.contains(basis) else {
                err(.vocabulary)
                continue
            }
            if let ref = item["generic_reference"], !ref.isNull {
                if ref.keys == R.referenceKeys, let source = ref["source"]?.text, let corpus = ref["corpus_sha256"]?.text,
                   let record = ref["record_id"]?.text, let match = ref["match"]?.text, let role = ref["role"]?.text,
                   R.genericSources.contains(source), R.genericMatches.contains(match), R.roles.contains(role),
                   !record.bytes.isEmpty {
                    if corpora[source] != corpus { err(.referenceCorpus) }
                    if role == R.merge, !(match == PFDText("same_food_same_state")
                                          && (state == PFDText("raw") || state == PFDText("cooked"))
                                          && basis == PFDText("per_100_g")) {
                        err(.mergeCondition)
                    }
                    if (source == R.tfda) != record.hasPrefix(R.tfdaPrefix) { err(.tfdaRecordID) }
                } else {
                    err(.reference)
                }
            }
            guard let nutrients = item["label_nutrients"]?.members else {
                err(.labelNutrients)
                continue
            }
            var servings: [PFDText: Set<Serving?>] = [:]
            for (key, value) in nutrients {
                if let got = checkValue(key: key, value: value, declared: declared, v2: v2, basis: basis) {
                    servings[got.release, default: []].insert(got.serving)
                }
            }
            if servings.values.contains(where: { $0.count > 1 }) { err(.servingMismatch) }
        }
    }

    /// `export_v1._check_value`. Under v2 it returns a product value's release and serving for the
    /// `serving-mismatch` rule.
    private mutating func checkValue(key: PFDText, value v: PFDValue, declared: [PFDText: Declared], v2: Bool,
                                     basis: PFDText) -> (release: PFDText, serving: Serving?)? {
        guard let canonical = R.canonicalUnits[key] else { err(.unknownNutrient); return nil }
        guard let keys = v.keys else { err(.valueShape); return nil }
        let optional = keys.intersection(R.valueOptional)
        guard R.valueKeys.isSubset(of: keys), keys.isSubset(of: R.valueKeys.union(R.valueOptional)), optional.count != 1 else {
            err(.valueKeys)
            return nil
        }
        if v["unit"]?.text != PFDText(bytes: Array(canonical.unit.rawValue.utf8)) { err(.unit) }
        let number = v["value"]?.nutrientNumber
        if number == nil { err(.value) }
        guard let kind = v["source_kind"]?.text,
              (kind == R.manualDeclaration && v["match"]?.text == R.owner)
                || (kind == R.exactProductDataset && v["match"]?.text == R.probable) else {
            err(.kindMatch)
            return nil
        }
        let isOwner = kind == R.manualDeclaration
        if isOwner, v["record_id"]?.isNull != true { err(.recordID) }
        if !isOwner, !(v["record_id"]?.text.map(R.isGTINRecordID) ?? false) { err(.recordID) }
        let source = v["source_release"]?.text.flatMap { declared[$0] }
        if let source {
            if source.kind != (isOwner ? R.owner : R.openFoodFacts) { err(.releaseKind) }
        } else {
            err(.undeclaredRelease)
        }
        if v2 {
            return checkTransformsV2(canonical: canonical, value: v, number: number, kind: kind, source: source, basis: basis)
        }
        guard optional.count == 2, let transforms = v["transforms"], let sv = v["source_value"] else { return nil }
        guard sv.keys == R.sourceValueKeys, let svNumber = sv["value"]?.nutrientNumber, let svUnit = sv["unit"]?.text else {
            err(.sourceValue)
            return nil
        }
        guard let list = transforms.items, list.count == 1, list[0].keys == R.transformKeys,
              let id = list[0]["transform_id"]?.text, let version = list[0]["version"]?.text else {
            err(.transformShape)
            return nil
        }
        guard let rule = R.transform(id: id, version: version) else { err(.transformUnknown); return nil }
        if rule.nutrient != canonical.key || rule.sourceUnit != svUnit || rule.sourceKind != kind {
            err(.transformScope)
        } else if let number, R.transformArithmeticFails(expected: rule.apply(svNumber), value: number) {
            err(.transformArithmetic)
        }
        return nil
    }

    /// `export_v1._check_value_v2`: the import v2 transforms; everything before them is the v1 rule.
    private mutating func checkTransformsV2(
        canonical: (key: NutrientKey, unit: NutrientUnit), value v: PFDValue, number: Double?, kind: PFDText,
        source: Declared?, basis: PFDText
    ) -> (release: PFDText, serving: Serving?)? {
        let productRelease = kind == R.exactProductDataset ? v["source_release"]?.text : nil
        guard let transforms = v["transforms"], let sv = v["source_value"] else {
            return productRelease.map { ($0, nil) }
        }
        guard let svKeys = sv.keys, svKeys == R.sourceValueKeys || svKeys == R.sourceValueKeysWithServing,
              let svNumber = sv["value"]?.nutrientNumber, let svUnit = sv["unit"]?.text else {
            err(.sourceValue)
            return nil
        }
        let hasServingKey = svKeys.contains(PFDText("serving"))
        var serving: Serving?
        if hasServingKey {
            guard let s = sv["serving"], s.keys == R.servingKeys, let quantity = R.servingQuantity(s["quantity"]),
                  let unit = s["unit"]?.text, unit == PFDText("g") || unit == PFDText("ml") else {
                err(.sourceValue)
                return nil
            }
            serving = Serving(quantity: quantity, unit: unit)
        }
        guard let list = transforms.items, list.count == 1 || list.count == 2 else {
            err(.transformShape)
            return nil
        }
        var pairs: [(id: PFDText, version: PFDText)] = []
        for item in list {
            guard item.keys == R.transformKeys, let id = item["transform_id"]?.text, let version = item["version"]?.text else {
                err(.transformShape)
                return nil
            }
            pairs.append((id, version))
        }
        func isServing(_ p: (id: PFDText, version: PFDText)) -> Bool {
            p.id == R.servingToHundred.id && p.version == R.servingToHundred.version
        }
        if pairs.count == 2, !(pairs[0].id == R.massGToMG.id && pairs[0].version == R.massGToMG.version && isServing(pairs[1])) {
            err(.transformShape)
            return nil
        }
        if pairs.contains(where: isServing) != hasServingKey {
            err(.sourceValue)
            return nil
        }
        if pairs.contains(where: { !isServing($0) && R.transform(id: $0.id, version: $0.version) == nil }) {
            err(.transformUnknown)
            return nil
        }
        let canonicalUnit = PFDText(bytes: Array(canonical.unit.rawValue.utf8))
        var unit = svUnit
        var expected = svNumber
        for pair in pairs {
            let ok: Bool
            if isServing(pair), let serving {
                ok = R.servingNutrients.contains(canonical.key) && kind == R.exactProductDataset && unit == canonicalUnit
                    && source?.pipeline == R.offV6 && R.servingUnits[basis] == serving.unit
                expected = expected * (100 / serving.quantity)
            } else if let rule = R.transform(id: pair.id, version: pair.version) {
                ok = rule.nutrient == canonical.key && rule.sourceUnit == unit && rule.sourceKind == kind
                expected = rule.apply(expected)
                unit = canonicalUnit
            } else {
                ok = false
            }
            if !ok {
                err(.transformScope)
                return nil
            }
        }
        if let number {
            if R.transformArithmeticFails(expected: expected, value: number) {
                err(.transformArithmetic)
            } else if serving != nil, OpenFoodFactsServingRule.isImplausible(number, unit: canonical.unit) {
                err(.servingImplausible)
            }
        }
        return productRelease.map { ($0, serving) }
    }
}

/// Builds the typed file from a tree the checker accepted. Every step is optional, so a gap in the
/// checks becomes a refusal, never a trap.
enum PersonalFoodDatabaseBuilder {
    typealias R = PersonalFoodDatabaseRules

    static func file(_ doc: PFDValue) -> PersonalFoodDatabaseFile? {
        guard let schema = doc["schema"]?.text.flatMap({ PersonalFoodDatabaseSchema(rawValue: $0.string) }),
              let generated = doc["generated"]?.text.flatMap({ PersonalFoodDatabaseDate(ascii: $0.bytes) }),
              let sourceValues = doc["sources"]?.items, let corpusValues = doc["generic_corpora"]?.items,
              let itemValues = doc["items"]?.items else { return nil }
        var sources: [PersonalFoodDatabaseDeclaredSource] = []
        for s in sourceValues {
            guard let source = declaredSource(s) else { return nil }
            sources.append(source)
        }
        var corpora: [PersonalFoodDatabaseGenericSource: String] = [:]
        for c in corpusValues {
            guard let source = c["source"]?.text.flatMap({ PersonalFoodDatabaseGenericSource(rawValue: $0.string) }),
                  let hash = c["corpus_sha256"]?.text?.string else { return nil }
            corpora[source] = hash
        }
        var entries: [PersonalFoodDatabaseEntry] = []
        entries.reserveCapacity(itemValues.count)
        for item in itemValues {
            guard let entry = entry(item) else { return nil }
            entries.append(entry)
        }
        return PersonalFoodDatabaseFile(schema: schema, generated: generated, sources: sources, genericCorpora: corpora,
                                        entries: entries)
    }

    static func declaredSource(_ s: PFDValue) -> PersonalFoodDatabaseDeclaredSource? {
        guard let sid = s["source_release_id"]?.text?.string,
              let kind = s["source_id"]?.text.flatMap({ PersonalFoodDatabaseSourceID(rawValue: $0.string) }),
              let releasedAt = s["released_at"]?.text.flatMap(R.utcDate),
              let artifact = s["artifact_sha256"]?.text?.string, let schema = s["schema_version"]?.text?.string,
              let pipeline = s["pipeline_version"]?.text?.string, let licence = s["licence"]?.text?.string,
              let attribution = s["attribution"]?.text?.string, let manifest = s["manifest_sha256"]?.text?.string
        else { return nil }
        return PersonalFoodDatabaseDeclaredSource(
            sourceReleaseID: sid, sourceID: kind, releasedAt: releasedAt, artifactSHA256: artifact, schemaVersion: schema,
            pipelineVersion: pipeline, licence: licence, attribution: attribution, manifestSHA256: manifest)
    }

    static func strings(_ v: PFDValue?) -> [String]? {
        guard let items = v?.items else { return nil }
        var out: [String] = []
        for item in items {
            guard let t = item.text else { return nil }
            out.append(t.string)
        }
        return out
    }

    static func optionalString(_ v: PFDValue?) -> String?? {
        guard let v else { return nil }
        if v.isNull { return .some(nil) }
        return v.text.map { .some($0.string) }
    }

    static func entry(_ item: PFDValue) -> PersonalFoodDatabaseEntry? {
        guard let id = item["id"]?.text?.string, let brand = optionalString(item["brand"]),
              let title = item["title"]?.text?.string, let titles = strings(item["titles"]),
              let aliases = strings(item["aliases"]), let concept = optionalString(item["concept"]),
              let variety = optionalString(item["variety"]), let chain = strings(item["fallback_chain"]),
              let category = item["category"]?.text.flatMap({ PersonalFoodDatabaseCategory(rawValue: $0.string) }),
              let productType = item["product_type"]?.text.flatMap({ PersonalFoodDatabaseProductType(rawValue: $0.string) }),
              let state = item["state"]?.text.flatMap({ PersonalFoodDatabaseState(rawValue: $0.string) }),
              let basis = item["basis"]?.text.flatMap({ PersonalFoodDatabaseBasis(rawValue: $0.string) }),
              let nutrientMembers = item["label_nutrients"]?.members, let refValue = item["generic_reference"]
        else { return nil }
        var nutrients: [PersonalFoodDatabaseLabelNutrient] = []
        for (key, value) in nutrientMembers {
            guard let canonical = R.canonicalUnits[key], let label = labelValue(value, unit: canonical.unit) else { return nil }
            nutrients.append(PersonalFoodDatabaseLabelNutrient(key: canonical.key, value: label))
        }
        var reference: PersonalFoodDatabaseGenericReference?
        if !refValue.isNull {
            guard let source = refValue["source"]?.text.flatMap({ PersonalFoodDatabaseGenericSource(rawValue: $0.string) }),
                  let corpus = refValue["corpus_sha256"]?.text?.string, let record = refValue["record_id"]?.text?.string,
                  let match = refValue["match"]?.text.flatMap({ PersonalFoodDatabaseReferenceMatch(rawValue: $0.string) }),
                  let role = refValue["role"]?.text.flatMap({ PersonalFoodDatabaseReferenceRole(rawValue: $0.string) })
            else { return nil }
            reference = PersonalFoodDatabaseGenericReference(
                source: source, corpusSHA256: corpus, recordID: record, match: match, role: role)
        }
        return PersonalFoodDatabaseEntry(
            id: id, brand: brand, title: title, titles: titles, aliases: aliases, concept: concept, variety: variety,
            fallbackChain: chain, category: category, productType: productType, state: state, basis: basis,
            labelNutrients: nutrients, genericReference: reference)
    }

    static func labelValue(_ v: PFDValue, unit: NutrientUnit) -> PersonalFoodDatabaseLabelValue? {
        guard let number = v["value"]?.nutrientNumber, let kind = v["source_kind"]?.text,
              let release = v["source_release"]?.text?.string else { return nil }
        let source: PersonalFoodDatabaseValueSource
        if kind == R.manualDeclaration {
            source = .manualDeclaration(sourceRelease: release)
        } else {
            guard let record = v["record_id"]?.text?.string else { return nil }
            source = .exactProductDataset(sourceRelease: release, recordID: record)
        }
        var transform: PersonalFoodDatabaseTransform?
        if let list = v["transforms"]?.items, let sv = v["source_value"] {
            var steps: [PersonalFoodDatabaseTransformStep] = []
            for item in list {
                guard let id = item["transform_id"]?.text?.string, let version = item["version"]?.text?.string else { return nil }
                steps.append(PersonalFoodDatabaseTransformStep(transformID: id, version: version))
            }
            guard !steps.isEmpty, let svValue = sv["value"]?.nutrientNumber, let svUnit = sv["unit"]?.text?.string else { return nil }
            var serving: PositiveQuantity?
            if let s = sv["serving"] {
                guard let quantity = R.servingQuantity(s["quantity"]), let servingUnit = s["unit"]?.text,
                      let quantityUnit: QuantityUnit = servingUnit == PFDText("g") ? .grams
                        : servingUnit == PFDText("ml") ? .millilitres : nil,
                      let positive = try? PositiveQuantity(value: quantity, unit: quantityUnit) else { return nil }
                serving = positive
            }
            transform = PersonalFoodDatabaseTransform(steps: steps, sourceValue: svValue, sourceUnit: svUnit, serving: serving)
        }
        return PersonalFoodDatabaseLabelValue(value: number, unit: unit, source: source, transform: transform)
    }
}
