import Foundation
import FoodLedgerDomain

/// Consumer-owned port: recomputes steps 1 to 4 of `pasted-label-conversions-v1` from a
/// record's `operand_text` and rule and says whether its `stored_text` matches (section 3.5).
/// The arithmetic lives in `NutritionLabelParsing` behind the adapter (decision 10); the
/// application never imports it. The intermediate is never compared.
public protocol PastedLabelConversionChecking: Sendable {
    func storedTextMatches(_ record: PastedLabelManifest.Conversion) -> Bool
}

public enum PastedLabelSourceError: Error, Equatable, Sendable {
    case invalidManifest(String)
}

/// The ledger records a pasted-label manifest stands for, and their verification
/// (`docs/pasted-nutrition-label-v1.md` sections 3.5, 6.1, 6.3 and 6.5).
///
/// There is one derivation: `expectedNutrients` turns the stored manifest into the exact
/// nutrient set the ledger must hold. The builder uses it to write, and save and reopen
/// verification use it to compare, so a stored value can only be a printed cell of the stored
/// column, a calculated value from exactly one such cell, or a user correction bound to its
/// record. Verification reads the stored manifest bytes and never re-parses the pasted text.
public enum PastedLabelSource {
    public static let sourceID = "pasted-nutrition-label"
    public static let captureMethod = "User pasted nutrition label"
    public static let licence = "User-supplied label text; no redistribution licence inferred."
    public static let attribution = "Pasted nutrition label"
    public static let parserVersion = "nutrition-label-text-parser-v2"
    public static let gateVersion = "label-capture-decline-gate-v2"
    public static let arithmeticVersion = "label-arithmetic-checks-v1"
    public static let conversionVersion = "pasted-label-conversions-v1"

    /// Closed and append-only: each manifest version is tied to its admitted pipelines,
    /// `<parser>:<gate>:<arithmetic>:<conversion>`. Entries are never removed or rekeyed.
    public static let admittedPipelines: [String: [String]] = [
        PastedLabelManifest.version: [[parserVersion, gateVersion, arithmeticVersion, conversionVersion].joined(separator: ":")]
    ]

    /// The v1 mapping from the reader's nutrient keys to ledger keys. Rows without a ledger key
    /// (trans fat, added sugars, kJ, salt) are read but never stored as themselves.
    public static let ledgerKeys: [String: NutrientKey] = [
        "energy_kcal": .energyConsumed, "fat": .fatTotal, "saturates": .fatSaturated,
        "carbohydrate": .carbohydrates, "sugars": .sugar, "fibre": .fiber, "protein": .protein, "sodium": .sodium
    ]

    /// The conversion rules of v1: target nutrient, source nutrient, source unit, operand unit, factor.
    struct Rule: Sendable {
        let nutrient: String, sourceNutrient: String, sourceUnit: String, operandUnit: String, factorText: String
    }
    static let rules: [String: Rule] = [
        "kj_to_kcal_v1": Rule(nutrient: "energy_kcal", sourceNutrient: "energy_kj", sourceUnit: "kJ", operandUnit: "kJ", factorText: "4.184"),
        "salt_to_sodium_v1": Rule(nutrient: "sodium", sourceNutrient: "salt", sourceUnit: "g", operandUnit: "g_salt", factorText: "2.5")
    ]

    public static func pipeline(_ manifest: PastedLabelManifest) -> String {
        [manifest.parserVersion, manifest.gateVersion, manifest.arithmeticVersion, manifest.conversionVersion].joined(separator: ":")
    }

    public static func schemaVersion(_ manifest: PastedLabelManifest) -> String {
        PastedLabelManifest.version + ":" + manifest.labelFormat
    }

    public static func manifestReference(hash: SHA256Digest, cell: PastedLabelManifest.Candidate.Cell) -> String {
        "manifest-sha256=\(hash.value);header=\(cell.headerID);row=\(cell.rowID);literal=\(cell.printedText)"
    }

    public static func correctionReference(hash: SHA256Digest, index: Int) -> String {
        "manifest-sha256=\(hash.value);correction=\(index)"
    }

    // MARK: Building

    /// The confirmation input for a manifest the user is logging. The manifest is encoded once
    /// with the injected canonical encoder; those bytes become the evidence payload unchanged and
    /// are never re-encoded from the struct after save.
    public static func confirmation(manifest: PastedLabelManifest, evidenceID: EvidenceID, capturedAt: Date, locale: LedgerText,
                                    encoder: any CanonicalEncoding, digester: any Digesting,
                                    conversions: (any PastedLabelConversionChecking)?) throws -> PopulatedFoodConfirmation {
        let manifestData = try encoder.encode(manifest)
        guard isCanonical(manifestData, encoder: encoder) else { throw PastedLabelSourceError.invalidManifest("canonical bytes") }
        let manifestHash = try digester.sha256(manifestData)
        let evidence = try CaptureEvidence(evidenceID: evidenceID, kind: .labelText, capturedAt: capturedAt, locale: locale,
            captureMethod: LedgerText(captureMethod), captureMethodVersion: LedgerText(PastedLabelManifest.version),
            originalPayload: .text(LedgerText(String(decoding: manifestData, as: UTF8.self))), byteHash: manifestHash)
        let release = try SourceRelease(sourceReleaseID: ExternalIdentifier("pasted-label:" + manifestHash.value),
            sourceID: ExternalIdentifier(sourceID), releasedAt: capturedAt,
            artifactHash: SHA256Digest(manifest.pastedTextSHA256), schemaVersion: LedgerText(schemaVersion(manifest)),
            pipelineVersion: LedgerText(pipeline(manifest)), licence: LedgerText(licence),
            attribution: LedgerText(attribution), manifestHash: manifestHash)
        let candidate = try expectedCandidate(manifest: manifest, release: release, evidence: evidence,
                                              digester: digester, conversions: conversions)
        return try PopulatedFoodConfirmation(evidence: [evidence], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
    }

    // MARK: Verification

    /// Save and reopen verification against the stored manifest: digest, release, pipeline,
    /// identity mapping, and every stored nutrient, unit, bound and basis.
    public static func verify(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate, encoder: any CanonicalEncoding,
                              digester: any Digesting, conversions: (any PastedLabelConversionChecking)?) -> Bool {
        let source = candidate.candidate
        guard let release = input.sourceReleases.first(where: { $0.sourceReleaseID == source.sourceReleaseID }),
              release.sourceID.value == sourceID,
              source.evidenceIDs.count == 1,
              let evidence = input.evidence.first(where: { $0.evidenceID == source.evidenceIDs[0] }),
              evidence.kind == .labelText, evidence.captureMethodVersion.value == PastedLabelManifest.version,
              evidence.captureMethod.value == captureMethod, evidence.attachment == nil,
              case let .text(payload) = evidence.originalPayload else { return false }
        let data = Data(payload.value.utf8)
        guard let hash = try? digester.sha256(data), evidence.byteHash == hash, release.manifestHash == hash,
              isCanonical(data, encoder: encoder), let manifest = PastedLabelManifest.decode(data),
              let expected = try? expectedCandidate(manifest: manifest, release: release, evidence: evidence,
                                                    digester: digester, conversions: conversions) else { return false }
        return expected == candidate
    }

    /// Canonical bytes only: the stored bytes must decode as a strict v1 manifest and re-encode
    /// to exactly themselves (no other whitespace, key order or escaping is admitted).
    public static func isCanonical(_ data: Data, encoder: any CanonicalEncoding) -> Bool {
        guard let manifest = PastedLabelManifest.decode(data), let encoded = try? encoder.encode(manifest) else { return false }
        return encoded == data
    }

    /// On reopen the saved product may carry the user's later name or class corrections; the
    /// immutable source candidate keeps the manifest's name, brand and class, as for reviewed web.
    public static func restoredSourceCandidate(_ input: PopulatedFoodConfirmation,
                                               candidate: PopulatedFoodCandidate) throws -> PopulatedFoodCandidate {
        let source = candidate.candidate
        guard source.evidenceIDs.count == 1,
              let evidence = input.evidence.first(where: { $0.evidenceID == source.evidenceIDs[0] }),
              case let .text(payload) = evidence.originalPayload,
              let manifest = PastedLabelManifest.decode(Data(payload.value.utf8)) else {
            throw PastedLabelSourceError.invalidManifest("evidence")
        }
        // Variant, barcode and pack facts are never part of a pasted label's source candidate; a
        // later user correction lives only on the saved product version.
        return try PopulatedFoodCandidate(candidate: source, name: LedgerText(manifest.name),
            brand: manifest.brand.map { try LedgerText($0) }, itemClass: manifest.identityMapping.itemClass)
    }

    /// The candidate a manifest yields, after checking the release and evidence it is bound to.
    static func expectedCandidate(manifest: PastedLabelManifest, release: SourceRelease, evidence: CaptureEvidence,
                                  digester: any Digesting, conversions: (any PastedLabelConversionChecking)?) throws -> PopulatedFoodCandidate {
        let hash = release.manifestHash
        guard release.sourceID.value == sourceID,
              release.sourceReleaseID.value == "pasted-label:" + hash.value,
              release.schemaVersion.value == schemaVersion(manifest),
              admittedPipelines[manifest.version]?.contains(pipeline(manifest)) == true,
              release.pipelineVersion.value == pipeline(manifest),
              release.licence.value == licence, release.attribution.value == attribution,
              release.releasedAt == evidence.capturedAt,
              release.artifactHash.value == manifest.pastedTextSHA256,
              (try digester.sha256(Data(manifest.pastedText.utf8))).value == manifest.pastedTextSHA256,
              manifest.candidate.inputSHA256 == manifest.pastedTextSHA256,
              manifest.pastedText.unicodeScalars.count <= PastedLabelManifest.maximumTextScalars,
              !manifest.candidate.declined,
              manifest.launchScope.contains(manifest.labelFormat) else {
            throw PastedLabelSourceError.invalidManifest("release")
        }
        let basis = try storedBasis(manifest)
        guard manifest.identityMapping.isCoherent(servingBasis: basis) else { throw PastedLabelSourceError.invalidManifest("identity") }
        let nutrients = try expectedNutrients(manifest: manifest, basis: basis, hash: hash, release: release,
                                              evidence: evidence, conversions: conversions)
        let neutral = try ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID,
            recordID: ExternalIdentifier("pasted-label:" + hash.value + "#header=" + manifest.storedHeaderID),
            identity: manifest.identityMapping.identity, edibleQuantity: try edibleQuantity(basis), nutrients: nutrients,
            evidenceIDs: [evidence.evidenceID])
        return try PopulatedFoodCandidate(candidate: neutral, name: LedgerText(manifest.name),
            brand: manifest.brand.map { try LedgerText($0) }, itemClass: manifest.identityMapping.itemClass)
    }

    // MARK: Basis (section 6.3)

    /// The fixed column rule: per 100 g or ml when printed, else per serving. A per-serving
    /// column with a readable serving size (or one the user entered, recorded as a correction)
    /// is `perServing(quantity)`. Without one it is settled as `perServing(1 count)`: values per
    /// one serving, with no weight or volume, so only an amount in servings can scale it.
    public static func storedBasis(_ manifest: PastedLabelManifest) throws -> ResolutionBasis {
        let headers = manifest.candidate.headers
        let fixed = headers.first { $0.basis == "per_100g" || $0.basis == "per_100ml" } ?? headers.first { $0.basis == "per_serving" }
        guard let header = fixed, header.headerID == manifest.storedHeaderID,
              headers.filter({ $0.headerID == header.headerID }).count == 1 else {
            throw PastedLabelSourceError.invalidManifest("stored column")
        }
        // A serving-size correction or entry is checked on every column: per serving it sets the
        // basis; per 100 g or ml it can only feed `pasted-label-serving-v2` servings.
        let corrected = try servingSizeCorrection(manifest)
        switch header.basis {
        case "per_100g": return .per100Grams
        case "per_100ml": return .per100Millilitres
        default: break
        }
        if let corrected { return .perServing(corrected) }
        return .perServing(try servingQuantity(manifest.candidate.servingSize) ?? PositiveQuantity(value: 1, unit: .count))
    }

    /// The serving size the user corrected or entered on Confirm, if any: at most one record, in
    /// the stored column, exact, in grams or millilitres. A correction names the printed readable
    /// serving size it replaces; an entry is allowed only when none was read.
    public static func servingSizeCorrection(_ manifest: PastedLabelManifest) throws -> PositiveQuantity? {
        let entries = manifest.corrections.filter { $0.nutrient == PastedLabelManifest.Correction.servingSize }
        guard entries.count <= 1 else { throw PastedLabelSourceError.invalidManifest("serving size corrections") }
        guard let entry = entries.first else { return nil }
        let printed = manifest.candidate.servingSize
        switch entry.kind {
        case .corrected:
            guard let printed, let recognised = entry.recognised, recognised.printedText == printed.printedText,
                  recognised.decimalText == printed.decimalText, recognised.unit == printed.unit,
                  recognised.comparator == "=" else { throw PastedLabelSourceError.invalidManifest("serving size recognised") }
        case .entered:
            guard entry.recognised == nil, servingQuantity(printed) == nil else {
                throw PastedLabelSourceError.invalidManifest("serving size entered")
            }
        }
        guard entry.rowID == nil, entry.headerID == manifest.storedHeaderID, entry.corrected.comparator == "=",
              let quantity = quantity(entry.corrected.decimalText, unit: entry.corrected.unit) else {
            throw PastedLabelSourceError.invalidManifest("serving size value")
        }
        return quantity
    }

    /// The edible quantity is the stored column's basis quantity, as for the dataset routes
    /// (CoFID, USDA, TFDA): no pack, drained or portion weight is inferred. Being known and equal
    /// on both sides, it raises no inline acknowledgement, so a pasted-label save writes no assertion.
    static func edibleQuantity(_ basis: ResolutionBasis) throws -> EdibleQuantityIdentity {
        switch basis {
        case .per100Grams: .known(try PositiveQuantity(value: 100, unit: .grams), conversionVersionID: nil)
        case .per100Millilitres: .known(try PositiveQuantity(value: 100, unit: .millilitres), conversionVersionID: nil)
        case let .perServing(quantity): .known(quantity, conversionVersionID: nil)
        case .perUnit, .named, .unknown: throw PastedLabelSourceError.invalidManifest("basis")
        }
    }

    static func servingQuantity(_ size: PastedLabelManifest.Candidate.ServingSize?) -> PositiveQuantity? {
        guard let size, let text = size.decimalText, let unit = size.canonicalUnit else { return nil }
        return quantity(text, unit: unit)
    }

    static func quantity(_ text: String, unit: String) -> PositiveQuantity? {
        let quantityUnit: QuantityUnit
        switch unit {
        case "g": quantityUnit = .grams
        case "ml", "mL": quantityUnit = .millilitres
        default: return nil
        }
        guard let value = amount(text), value > 0 else { return nil }
        return try? PositiveQuantity(value: value, unit: quantityUnit)
    }

    /// Printed decimal text to the ledger amount: `Double(String)` of the text with a decimal
    /// comma read as a point; never computed through other arithmetic.
    static func amount(_ text: String) -> Double? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }),
              text.filter({ $0 == "." || $0 == "," }).count <= 1, text.first?.isNumber == true, text.last?.isNumber == true,
              let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0 else { return nil }
        return value
    }

    // MARK: Nutrients (sections 3.4, 3.5 and 6.1)

    static func expectedNutrients(manifest: PastedLabelManifest, basis: ResolutionBasis, hash: SHA256Digest,
                                  release: SourceRelease, evidence: CaptureEvidence,
                                  conversions checker: (any PastedLabelConversionChecking)?) throws -> NutrientSet {
        let column = manifest.candidate.cells.filter {
            $0.headerID == manifest.storedHeaderID && $0.basis != "reference_intake" && $0.canonicalUnit != "%"
        }
        try checkServingsPerPack(manifest)
        let lines: Set<String> = [PastedLabelManifest.Correction.servingSize, PastedLabelManifest.Correction.servingsPerPack]
        let corrections = manifest.corrections.enumerated().filter { !lines.contains($0.element.nutrient) }
        guard Set(corrections.map(\.element.nutrient)).count == corrections.count,
              Set(manifest.conversions.map(\.nutrient)).count == manifest.conversions.count,
              manifest.conversions.isEmpty || manifest.conversionVersion == conversionVersion else {
            throw PastedLabelSourceError.invalidManifest("duplicate correction or conversion")
        }
        for (_, correction) in corrections {
            guard ledgerKeys[correction.nutrient] != nil else { throw PastedLabelSourceError.invalidManifest("correction nutrient") }
        }
        for conversion in manifest.conversions {
            guard rules[conversion.rule]?.nutrient == conversion.nutrient else { throw PastedLabelSourceError.invalidManifest("conversion rule") }
        }
        func provenance(_ kind: ProvenanceSourceKind, reference: String, transforms: [NutrientTransform] = []) throws -> NutrientProvenance {
            try NutrientProvenance(sourceKind: kind, sourceID: ExternalIdentifier(sourceID), sourceReleaseID: release.sourceReleaseID,
                evidenceID: evidence.evidenceID, capturedAt: evidence.capturedAt, manifestReference: LedgerText(reference),
                transforms: transforms)
        }
        return try NutrientSet(entries: NutrientKey.allCases.map { key in
            let labelNutrients = ledgerKeys.filter { $0.value == key }.map(\.key)
            guard let labelNutrient = labelNutrients.first else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            let printed = column.filter { $0.nutrient == labelNutrient }
            // A recorded conversion is always verified, even when a correction supplies the
            // stored value: it stays in the manifest as evidence of what Confirm showed.
            let conversion = manifest.conversions.first { $0.nutrient == labelNutrient }
            var conversionCell: PastedLabelManifest.Candidate.Cell?
            if let conversion {
                // Printed always wins: a recorded conversion beside a printed counterpart is invalid.
                guard printed.isEmpty, let checker, checker.storedTextMatches(conversion),
                      let rule = rules[conversion.rule] else { throw PastedLabelSourceError.invalidManifest("conversion") }
                let sources = column.filter { $0.nutrient == rule.sourceNutrient }
                guard conversion.ruleVersion == conversionVersion, conversion.operandUnit == rule.operandUnit,
                      conversion.factorText == rule.factorText, sources.count == 1, let cell = sources.first,
                      cell.canonicalUnit == rule.sourceUnit, cell.rowID == conversion.sourceRowID,
                      cell.headerID == conversion.sourceHeaderID, cell.decimalText == conversion.operandText,
                      coherentComparator(cell: cell.comparator, record: conversion.comparator, rounding: conversion.rounding) else {
                    throw PastedLabelSourceError.invalidManifest("conversion source")
                }
                conversionCell = cell
            }
            // A value the user corrected or entered: manual_declaration, bound to its record.
            if let (index, correction) = corrections.first(where: { $0.element.nutrient == labelNutrient }) {
                try checkCorrection(correction, key: key, labelNutrient: labelNutrient, manifest: manifest, column: column,
                                    conversionSource: conversionCell)
                let origin = try provenance(.manualDeclaration, reference: correctionReference(hash: hash, index: index))
                return try NutrientEntry(key: key, value: value(decimalText: correction.corrected.decimalText,
                    comparator: correction.corrected.comparator, key: key, basis: basis, sourceUnit: key.canonicalUnit.rawValue,
                    sourceDecimalText: correction.corrected.decimalText, provenance: origin))
            }
            if let conversion, let cell = conversionCell, let rule = rules[conversion.rule] {
                let transform = NutrientTransform(transformID: try LedgerText(conversion.rule),
                                                  transformVersion: try LedgerText(conversion.ruleVersion))
                let origin = try provenance(.userVerifiedPanel, reference: manifestReference(hash: hash, cell: cell), transforms: [transform])
                return try NutrientEntry(key: key, value: value(decimalText: conversion.storedText, comparator: cell.comparator,
                    key: key, basis: basis, sourceUnit: rule.operandUnit, sourceDecimalText: conversion.operandText, provenance: origin))
            }
            guard !printed.isEmpty else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            // Ambiguous or in another unit: no value is chosen or converted; it stays unknown.
            guard printed.count == 1, let cell = printed.first, cell.canonicalUnit == key.canonicalUnit.rawValue else {
                return try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            }
            let origin = try provenance(.userVerifiedPanel, reference: manifestReference(hash: hash, cell: cell))
            return try NutrientEntry(key: key, value: value(decimalText: cell.decimalText, comparator: cell.comparator, key: key,
                basis: basis, sourceUnit: key.canonicalUnit.rawValue, sourceDecimalText: cell.decimalText, provenance: origin))
        })
    }

    /// An entered servings-per-pack value (G6): at most one, only when the label prints none,
    /// an exact positive number of servings in the stored column's record. It gives no nutrient
    /// and no basis, but it may feed the whole-pack amount option (`PastedLabelServingPolicy.wholePack`,
    /// contract section 2.3).
    static func checkServingsPerPack(_ manifest: PastedLabelManifest) throws {
        let entries = manifest.corrections.filter { $0.nutrient == PastedLabelManifest.Correction.servingsPerPack }
        guard entries.count <= 1 else { throw PastedLabelSourceError.invalidManifest("servings per pack entries") }
        guard let entry = entries.first else { return }
        guard entry.kind == .entered, entry.rowID == nil, entry.recognised == nil, manifest.candidate.servingsPerPack == nil,
              entry.headerID == manifest.storedHeaderID, entry.corrected.unit == "count", entry.corrected.comparator == "=",
              let value = amount(entry.corrected.decimalText), value > 0 else {
            throw PastedLabelSourceError.invalidManifest("servings per pack entered")
        }
    }

    /// A conversion carries the printed comparator only for a bound, with outward rounding.
    static func coherentComparator(cell: String, record: String?, rounding: String?) -> Bool {
        switch cell {
        case "=": record == nil && rounding == nil
        case "<", "<=": record == cell && rounding == "outward"
        default: false
        }
    }

    /// A corrected value names the cell it replaced: a printed cell of the nutrient, or, for a
    /// calculated value, the source cell of its verified conversion. An entered value replaces nothing.
    static func checkCorrection(_ correction: PastedLabelManifest.Correction, key: NutrientKey, labelNutrient: String,
                                manifest: PastedLabelManifest, column: [PastedLabelManifest.Candidate.Cell],
                                conversionSource: PastedLabelManifest.Candidate.Cell?) throws {
        guard correction.headerID == manifest.storedHeaderID, correction.corrected.unit == key.canonicalUnit.rawValue,
              ["=", "<", "<="].contains(correction.corrected.comparator) else {
            throw PastedLabelSourceError.invalidManifest("correction value")
        }
        switch correction.kind {
        case .corrected:
            guard let rowID = correction.rowID, let recognised = correction.recognised,
                  let cell = column.first(where: { $0.rowID == rowID }),
                  cell.nutrient == labelNutrient || cell == conversionSource,
                  recognised == .init(printedText: cell.printedText, decimalText: cell.decimalText, unit: cell.unit, comparator: cell.comparator) else {
                throw PastedLabelSourceError.invalidManifest("correction recognised")
            }
        case .entered:
            guard correction.rowID == nil, correction.recognised == nil, conversionSource == nil,
                  !column.contains(where: { $0.nutrient == labelNutrient }) else {
                throw PastedLabelSourceError.invalidManifest("entered value")
            }
        }
    }

    /// An exact value for `=`, and a bound with no lower end for `<` (open) or `<=` (closed).
    static func value(decimalText: String, comparator: String, key: NutrientKey, basis: ResolutionBasis, sourceUnit: String,
                      sourceDecimalText: String, provenance: NutrientProvenance) throws -> NutrientValue {
        guard let amount = Self.amount(decimalText), let sourceAmount = Self.amount(sourceDecimalText) else {
            throw PastedLabelSourceError.invalidManifest("decimal text")
        }
        switch comparator {
        case "=":
            let source = try SourceExactNutrientValue(amount: sourceAmount, unit: LedgerText(sourceUnit), basis: basis)
            return .measured(try ExactNutrientValue(amount: amount, unit: key.canonicalUnit, sourceValue: .exact(source), provenance: [provenance]))
        case "<", "<=":
            let closed = comparator == "<="
            let source = try SourceBoundedNutrientValue(lower: nil, upper: sourceAmount, lowerClosed: false, upperClosed: closed,
                                                        unit: LedgerText(sourceUnit), basis: basis)
            return .bounded(try NutrientBounds(lower: nil, upper: amount, lowerClosed: false, upperClosed: closed, origin: .measured,
                                               unit: key.canonicalUnit, sourceValue: .bounded(source), provenance: [provenance]))
        default:
            throw PastedLabelSourceError.invalidManifest("comparator")
        }
    }
}

/// Admission of `user_verified_panel` at save (section 6.1): only through a source verifier
/// keyed by `SourceRelease.sourceID`, looked up in an append-only list. The same applies to
/// `manual_declaration` values that claim an admitted source's release.
public enum PanelSourceAdmission {
    public struct Verifier: Sendable {
        public let sourceID: String
        let verify: @Sendable (PopulatedFoodConfirmation, PopulatedFoodCandidate, any CanonicalEncoding, any Digesting,
                               (any PastedLabelConversionChecking)?) -> Bool
    }

    /// Append-only. The v1 entry is `pasted-nutrition-label`; no entry is removed or rekeyed.
    public static let admitted: [Verifier] = [
        Verifier(sourceID: PastedLabelSource.sourceID, verify: PastedLabelSource.verify)
    ]

    public static var admittedSourceIDs: [String] { admitted.map(\.sourceID) }

    /// Whether the candidate falls under admission: any panel value, any value or release that
    /// names an admitted source, or evidence of an admitted capture method.
    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        let source = candidate.candidate
        let provenance = provenance(source)
        let ids = Set(admittedSourceIDs)
        return provenance.contains { $0.sourceKind == .userVerifiedPanel || ids.contains($0.sourceID.value)
                || release(input, $0.sourceReleaseID).map { ids.contains($0.sourceID.value) } == true }
            || release(input, source.sourceReleaseID).map { ids.contains($0.sourceID.value) } == true
            || input.evidence.contains { source.evidenceIDs.contains($0.evidenceID)
                && $0.captureMethodVersion.value == PastedLabelManifest.version }
    }

    /// Fails closed: every panel value, and every manual declaration claiming an admitted
    /// release, must name an admitted `sourceID` whose release says the same, and that source's
    /// verifier must accept the candidate against its stored evidence.
    public static func verify(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate, encoder: any CanonicalEncoding,
                              digester: any Digesting, conversions: (any PastedLabelConversionChecking)?) -> Bool {
        let source = candidate.candidate
        let ids = Set(admittedSourceIDs)
        var claimed: Set<String> = []
        for value in provenance(source) {
            let named = release(input, value.sourceReleaseID)?.sourceID.value
            let claims = value.sourceKind == .userVerifiedPanel || ids.contains(value.sourceID.value) || named.map(ids.contains) == true
            guard claims else { continue }
            guard value.sourceKind == .userVerifiedPanel || value.sourceKind == .manualDeclaration,
                  ids.contains(value.sourceID.value), named == value.sourceID.value,
                  value.sourceReleaseID == source.sourceReleaseID else { return false }
            claimed.insert(value.sourceID.value)
        }
        if let named = release(input, source.sourceReleaseID)?.sourceID.value, ids.contains(named) { claimed.insert(named) }
        guard claimed.count == 1, let id = claimed.first,
              let verifier = admitted.first(where: { $0.sourceID == id }) else { return false }
        return verifier.verify(input, candidate, encoder, digester, conversions)
    }

    static func provenance(_ candidate: ProviderNeutralCandidate) -> [NutrientProvenance] {
        candidate.nutrients.entries.flatMap { entry in ([entry.value] + entry.conflictCandidates).flatMap(\.provenance) }
    }

    static func release(_ input: PopulatedFoodConfirmation, _ id: ExternalIdentifier) -> SourceRelease? {
        input.sourceReleases.first { $0.sourceReleaseID == id }
    }
}
