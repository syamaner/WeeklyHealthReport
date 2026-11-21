import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// The pure Open Food Facts product projection (docs/confirm-enrichment-openrouter-v1-phase.md section
/// 3.3 item 5): moved unchanged from the barcode lookup so that the barcode route, text search and the
/// Confirm enrichment evaluation tool build exactly the same candidate from the same product record.
/// It names no network or transport type; the routes that fetch a record call it.
public enum OpenFoodFactsProductMapping {
    /// Shared closed admission rules for barcode and text-search records.
    /// Search callers pass the actual product JSON, never a fabricated scan response.
    public static func project(product: [String: Any], artifact: Data, gtin: LedgerText,
                        evidence: CaptureEvidence, retrievedAt now: Date,
                        searchScore: Double? = nil, searchCategory: String? = nil) throws -> PackagedFoodLookupOutcome {
        guard let returned = product["code"] as? String else { throw OFFLookupError.malformedResponse }
        guard let name = product["product_name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .insufficientData }
        let pack = product["quantity"] as? String ?? ""
        let mass = pack.range(of: #"(?i)\d\s*(g|kg)\b"#, options: .regularExpression) != nil
        let liquid = pack.range(of: #"(?i)\d\s*(ml|cl|dl|l)\b"#, options: .regularExpression) != nil
        // v5 (#458): a pack quantity that states a mass or a volume decides the basis as before; a
        // missing or unrecognised one lets the single eligible label panel state its own basis.
        let packBasis: Bool? = mass == liquid ? nil : liquid
        guard !(mass && liquid),
              !(product["categories_tags"] as? [String] ?? []).contains("en:dietary-supplements"),
              let sourceSet = Self.sourceNutrients(product, volume: packBasis) else { return .insufficientData }
        let volume = sourceSet.volume
        let basis: ResolutionBasis = volume ? .per100Millilitres : .per100Grams
        let nutrients = sourceSet.values
        let hash = SHA256.hash(data: artifact).map { String(format: "%02x", $0) }.joined()
        // v6 (per-serving panels scaled to per 100) only for a record v5 would decline, so every
        // v5 record keeps its bytes, hashes and release ID (off-barcode-candidate-plan-v1).
        let projectionVersion = sourceSet.serving == nil && !sourceSet.panelOverridesPack ? "off-product-projection-v5"
            : OpenFoodFactsServingRule.projectionVersion
        let schemaVersion = searchScore == nil ? "off-v3.6-explicit-basis-candidates-v4" : "off-search-explicit-basis-candidates-v5"
        let releaseID = try ExternalIdentifier("off:snapshot:sha256:\(hash):projection:\(projectionVersion):schema:\(schemaVersion):retrieved:\(now.timeIntervalSince1970)")
        let productURL = "https://world.openfoodfacts.org/product/\(returned)"
        let release = try SourceRelease(sourceReleaseID: releaseID, sourceID: ExternalIdentifier("open-food-facts"),
            releasedAt: now, artifactHash: SHA256Digest(hash), schemaVersion: LedgerText(schemaVersion),
            pipelineVersion: LedgerText(projectionVersion),
            licence: LedgerText("ODbL 1.0 https://opendatacommons.org/licenses/odbl/1-0/; contents: https://opendatacommons.org/licenses/dbcl/1-0/"),
            attribution: LedgerText("Open Food Facts · \(productURL) · Retrieved \(ISO8601DateFormatter().string(from: now))"), manifestHash: SHA256Digest(hash))
        let fields: [NutrientKey: String] = [.energyConsumed: "energy-kcal", .protein: "proteins", .carbohydrates: "carbohydrates",
            .fatTotal: "fat", .fatSaturated: "saturated-fat", .fiber: "fiber", .sugar: "sugars", .sodium: "sodium"]
        // A per-serving panel (v6): values scale by 100 / serving; the source keeps its own basis.
        let servingScale = sourceSet.serving.map { 100 / $0 } ?? 1
        let sourceBasis: ResolutionBasis = try sourceSet.serving.map {
            .perServing(try PositiveQuantity(value: $0, unit: volume ? .millilitres : .grams))
        } ?? basis
        var available = 0
        // v6: a value that only overflows because of the serving scale means a wrong serving size.
        var scaledOverflow = false
        let entries = try NutrientKey.allCases.map { key -> NutrientEntry in
            // Legacy sodium _100g is normalised independently of the contributor unit.
            guard key != .sodium || sourceSet.isModern,
                  let field = fields[key], let number = nutrients[field + "_100g"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue >= 0 else {
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
            guard let sourceUnit = nutrients[field + "_unit"] as? String else {
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            let convertsGrams = key == .sodium && sourceUnit == "g"
            guard sourceUnit == key.canonicalUnit.rawValue || convertsGrams else {
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            let rawModifier = nutrients[field + "_modifier"]
            guard rawModifier == nil || rawModifier is String else {
                return try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            }
            let modifier = rawModifier as? String ?? ""
            guard ["", "<", "<=", ">", ">="].contains(modifier) else {
                return try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            }
            let sourceAmount = number.doubleValue
            let amount = sourceAmount * (convertsGrams ? 1_000 : 1) * servingScale
            guard amount.isFinite else {
                if sourceSet.serving != nil, (sourceAmount * (convertsGrams ? 1_000 : 1)).isFinite { scaledOverflow = true }
                return try NutrientEntry(key: key, value: .unknown(.missingConversion))
            }
            available += 1
            let unit = try LedgerText(sourceUnit)
            var transforms = convertsGrams ? [try NutrientTransform(transformID: LedgerText("mass-g-to-mg"), transformVersion: LedgerText("v1"))] : []
            if sourceSet.serving != nil {
                transforms.append(try NutrientTransform(transformID: LedgerText(OpenFoodFactsServingRule.transformID),
                    transformVersion: LedgerText(OpenFoodFactsServingRule.transformVersion)))
            }
            let source = try SourceExactNutrientValue(amount: sourceAmount, unit: unit, basis: sourceBasis)
            let provenance = try NutrientProvenance(sourceKind: .exactProductDataset, sourceID: ExternalIdentifier("open-food-facts"),
                sourceReleaseID: releaseID, recordID: ExternalIdentifier("off:gtin:\(gtin.value)"), manifestReference: LedgerText("\(productURL)#\(sourceSet.path)/\(sourceSet.path == "nutriments" ? field + "_100g" : field)"), transforms: transforms)
            if !modifier.isEmpty {
                let upper = modifier.hasPrefix("<") ? amount : nil
                let lower = modifier.hasPrefix(">") ? amount : nil
                let closed = modifier.hasSuffix("=")
                let bound = try SourceBoundedNutrientValue(lower: lower == nil ? nil : sourceAmount, upper: upper == nil ? nil : sourceAmount,
                    lowerClosed: lower != nil && closed, upperClosed: upper != nil && closed,
                    unit: unit, basis: sourceBasis)
                return try NutrientEntry(key: key, value: .bounded(NutrientBounds(lower: lower, upper: upper,
                    lowerClosed: bound.lowerClosed, upperClosed: bound.upperClosed, origin: .augmented,
                    unit: key.canonicalUnit, sourceValue: .bounded(bound), provenance: [provenance])))
            }
            return try NutrientEntry(key: key, value: .augmented(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(source), provenance: [provenance])))
        }
        guard available > 0 else { return .insufficientData }
        // v6 plausibility: a scaled value no food can have per 100 (more than 100 g of a nutrient
        // or 900 kcal) means a wrong serving size, so the record declines rather than mislead.
        // Both ends of a bound are checked too, and an overflow from scaling declines (Qodo review).
        if sourceSet.serving != nil, scaledOverflow || entries.contains(where: { entry in
            let implausible = OpenFoodFactsServingRule.isImplausible
            switch entry.value {
            case let .augmented(value): return implausible(value.amount, value.unit)
            case let .bounded(bounds): return [bounds.lower, bounds.upper].compactMap { $0 }.contains { implausible($0, bounds.unit) }
            default: return false
            }
        }) { return .insufficientData }
        let identity = try DecisiveIdentity(preparation: PreparationState(kind: .unknown), bone: .unknown, skin: .unknown,
            drained: .unknown, packingMedium: .unknown, fortification: .unknown, servingBasis: basis)
        let quantity = try EdibleQuantityIdentity.known(PositiveQuantity(value: 100, unit: volume ? .millilitres : .grams), conversionVersionID: nil)
        let metadata = try CandidateMatchMetadata(methodVersion: LedgerText(searchScore == nil ? "off-product-candidates-v4" : "off-search-candidates-v5"), score: searchScore ?? 1,
            materialDifferences: [LedgerText("Community product data; check name, package and nutrition basis. Missing values remain unknown.")],
            libraryAliases: searchScore == nil ? [try BarcodeIdentity.gtin(gtin).lookupAlias] : [])
        // v6: the source line says the values were scaled, so Confirm shows it.
        let servingNote = (sourceSet.serving.map {
            ", scaled from a \(Self.servingText($0)) \(OpenFoodFactsServingText.unit(millilitres: volume)) serving"
        } ?? "") + (sourceSet.panelOverridesPack || (sourceSet.serving != nil && packBasis.map { $0 != volume } == true)
            ? ", as the nutrition panel states (the pack is in \(volume ? "g" : "mL"))" : "")
        let candidate = try PopulatedFoodCandidate(candidate: ProviderNeutralCandidate(sourceReleaseID: releaseID,
            recordID: ExternalIdentifier("off:gtin:\(gtin.value)"), identity: identity, edibleQuantity: quantity,
            nutrients: NutrientSet(entries: entries), evidenceIDs: [evidence.evidenceID], matchMetadata: metadata),
            name: LedgerText(name), brand: (product["brands"] as? String).flatMap { try? LedgerText($0) },
            variant: LedgerText("Open Food Facts · source estimate · \(pack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\(pack) · ")per 100 \(volume ? "mL" : "g")" + servingNote + (searchCategory.map { "; source category: \($0). Review this type against your request." } ?? "")), barcode: gtin, itemClass: .food, packFacts: PackFacts())
        return .candidate(try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: identity, expectedEdibleQuantity: quantity))
    }
    // Choose one source input set. OFF's aggregate may mix packaging, estimates and
    // preparations, so it is never used to backfill this candidate.
    /// `volume` is the pack's basis, or nil when the pack states neither; then exactly one eligible
    /// panel across both bases may state its own (v5, #458). Legacy values still need a mass pack.
    /// v6: a single per 100 panel that the pack contradicts states its own basis
    /// (`panelOverridesPack`); with no per 100 panel, exactly one per-serving panel with a stated
    /// serving in g or ml; `serving` is its size, and the caller scales by 100 / serving.
    private static func sourceNutrients(_ product: [String: Any], volume packBasis: Bool?)
        -> (values: [String: Any], path: String, isModern: Bool, volume: Bool, serving: Double?, panelOverridesPack: Bool)? {
        if product["nutrition"] != nil {
            guard let nutrition = product["nutrition"] as? [String: Any], let sets = nutrition["input_sets"] as? [[String: Any]] else { return nil }
            let bases = packBasis.map { [$0 ? "100ml" : "100g"] } ?? ["100g", "100ml"]
            let eligible = sets.enumerated().filter {
                $0.element["source"] as? String == "packaging" && bases.contains($0.element["per"] as? String ?? "")
                    && $0.element["preparation"] as? String == "as_sold"
            }
            // v6 (owner decision, 12 November 2026): when the pack's basis matches no panel, the
            // record's single per 100 panel states its own basis and wins over the pack. With no
            // per 100 panel at all, a per-serving panel is scaled instead.
            var chosen = eligible
            var panelOverridesPack = false
            if eligible.isEmpty {
                let per100 = sets.enumerated().filter {
                    $0.element["source"] as? String == "packaging" && $0.element["preparation"] as? String == "as_sold"
                        && ["100g", "100ml"].contains($0.element["per"] as? String ?? "")
                }
                if per100.isEmpty { return servingNutrients(sets) }
                guard per100.count == 1 else { return nil }
                chosen = per100; panelOverridesPack = true
            }
            guard chosen.count == 1, let values = chosen[0].element["nutrients"] as? [String: Any] else { return nil }
            let panel = chosen[0].element
            let volume = panel["per"] as? String == "100ml"
            if let quantity = panel["per_quantity"] {
                guard let number = quantity as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == 100 else { return nil }
            }
            if let unit = panel["per_unit"] {
                guard unit as? String == (volume ? "ml" : "g") else { return nil }
            }
            var result: [String: Any] = [:]
            for (field, raw) in values {
                guard let value = raw as? [String: Any] else { continue }
                result[field + "_100g"] = value["value"]
                result[field + "_unit"] = value["unit"]
                result[field + "_modifier"] = value["modifier"]
            }
            return (result, "nutrition/input_sets/\(chosen[0].offset)/nutrients", true, volume, nil, panelOverridesPack)
        }
        guard packBasis == false else { return nil } // Legacy *_100g does not distinguish mass from volume.
        guard product["nutrition_data_per"] as? String == "100g" else { return nil }
        guard let values = product["nutriments"] as? [String: Any] else { return nil }
        return (values, "nutriments", false, false, nil, false)
    }

    /// "28" or "12.5": the serving as Open Food Facts states it, without a trailing ".0".
    static func servingText(_ value: Double) -> String { OpenFoodFactsServingText.number(value) }

    /// v6: exactly one `packaging`, `as_sold`, `per: serving` panel whose `per_quantity` is a
    /// finite number above 0 and whose `per_unit` (g or ml) agrees with any pack basis.
    private static func servingNutrients(_ sets: [[String: Any]])
        -> (values: [String: Any], path: String, isModern: Bool, volume: Bool, serving: Double?, panelOverridesPack: Bool)? {
        let panels = sets.enumerated().filter {
            $0.element["source"] as? String == "packaging" && $0.element["per"] as? String == "serving"
                && $0.element["preparation"] as? String == "as_sold"
        }
        guard panels.count == 1, let values = panels[0].element["nutrients"] as? [String: Any],
              let serving = servingQuantity(panels[0].element["per_quantity"]), serving.isFinite, serving > 0,
              let unit = panels[0].element["per_unit"] as? String, unit == "g" || unit == "ml" else { return nil }
        // The panel's unit decides the basis, as a per 100 panel's does, whatever the pack states.
        let volume = unit == "ml"
        var result: [String: Any] = [:]
        for (field, raw) in values {
            guard let value = raw as? [String: Any] else { continue }
            result[field + "_100g"] = value["value"]
            result[field + "_unit"] = value["unit"]
            result[field + "_modifier"] = value["modifier"]
        }
        return (result, "nutrition/input_sets/\(panels[0].offset)/nutrients", true, volume, serving, false)
    }

    /// A serving size as a number, or as text holding only a plain decimal ("112", "12.5"), which
    /// Open Food Facts often stores; a boolean, a signed or exponent form, or anything else is nil.
    static func servingQuantity(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber { return CFGetTypeID(number) == CFBooleanGetTypeID() ? nil : number.doubleValue }
        guard let text = raw as? String, text.range(of: #"^[0-9]{1,6}(\.[0-9]{1,3})?$"#, options: .regularExpression) != nil else { return nil }
        return Double(text)
    }

}
