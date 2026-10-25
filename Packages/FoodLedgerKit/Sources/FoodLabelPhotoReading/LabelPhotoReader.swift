import Foundation
import FoodLedgerApplication
import NutritionLabelParsing

/// Adapter for the `LabelPhotoInterpreting` port (docs/label-photo-ai-prefill-v1.md 12.1, 12.6
/// and 17.1). On device and in order: the strict wire decode, `label-photo-wire-mapping-v1`,
/// format inference, gate v2 on the Taiwan format, `label-arithmetic-checks-v2` over the amount
/// bases and the `pasted-label-conversions-v1` conversions for the stored column. The frozen
/// rules are called, never copied (invariant 6). It never persists, decides or presents, and never
/// changes a value: G3 to G6 stay findings (Confirm turns them into flags), so the mapped
/// candidate is passed on, never the gate's withheld copy.
public struct LabelPhotoReader: LabelPhotoInterpreting {
    public static let versions = LabelPhotoReading.Versions(mapping: LabelPhotoWireMapping.version, gate: LabelDeclineGate.version,
                                                            arithmetic: LabelArithmeticChecksV2.version, conversion: PastedLabelConversions.version)

    public init() {}

    public func reading(wireText: String, imageSHA256: String) -> LabelPhotoReading? {
        guard let wire = LabelPhotoWire.decode(wireText) else { return nil }
        return reading(LabelPhotoWireMapping.map(wire, inputSHA256: imageSHA256))
    }

    func reading(_ candidate: LabelCaptureCandidate) -> LabelPhotoReading {
        let format = LabelFormatInference.infer(candidate)
        var gate: LabelReading.Gate?
        var checks: [LabelReading.Check] = []
        var conversions: [PastedLabelManifest.Conversion] = []
        let storedHeaderID = candidate.declined ? nil : PastedLabelStoredColumn.headerID(for: candidate)
        // Taiwan only in v1 (invariant 9): any other inferred format is declined by the reading.
        if !candidate.declined, format == .taiwan {
            let report = LabelDeclineGate.apply(candidate, format: .taiwan).report
            gate = LabelReading.Gate(format: LabelGateFormat.taiwan.rawValue, skipped: report.skipped?.rawValue,
                                     hardDeclines: report.hardDeclineCodes, flags: Self.flags(report, candidate: candidate))
            let amountBases = candidate.headers.filter { $0.basis != .referenceIntake }.map(\.basis.rawValue)
            checks = LabelArithmeticChecksV2.check(LabelArithmeticTable(candidate, format: .taiwan), amountBases: amountBases).checks
                .map(Self.check)
            if let storedHeaderID {
                conversions = PastedLabelConversions.conversions(for: candidate, storedHeaderID: storedHeaderID).map { Self.conversion($0.record) }
            }
        }
        return LabelPhotoReading(imageSHA256: candidate.inputSHA256, candidate: Self.candidate(candidate), inferredFormat: format.rawValue,
                                 gate: gate, checks: checks, conversions: conversions, storedHeaderID: storedHeaderID, versions: Self.versions)
    }

    // MARK: Projection
    //
    // The same projection as the pasted route's `NutritionLabelTextReader` (pinned, in
    // `FoodLabelTextCapture`, which this target may not import): G3 to G6 with what each concerns,
    // check results, conversion records and the candidate on the pasted manifest's shape.

    static func flags(_ report: LabelGateReport, candidate: LabelCaptureCandidate) -> [LabelReading.Flag] {
        guard report.skipped == nil else { return [] }
        let reasons = Set(report.flags)
        let required = LabelDeclineGate.requiredRows[report.labelFormat] ?? []
        var byNutrient: [String: Set<String>] = [:]
        for cell in candidate.cells where cell.basis != .referenceIntake {
            byNutrient[cell.nutrient, default: []].insert(cell.headerID)
        }
        let per100 = candidate.headers.filter { $0.basis == .per100g || $0.basis == .per100ml }.map(\.headerID)
        var out: [LabelReading.Flag] = []
        if reasons.contains(.requiredRowMissing) {
            out += required.filter { byNutrient[$0] == nil }.map { .init(code: LabelGateReason.requiredRowMissing.rawValue, concerns: $0) }
        }
        if reasons.contains(.columnCountMismatch) {
            for row in required {
                guard let headers = byNutrient[row] else { continue }
                out += per100.filter { !headers.contains($0) }.map { .init(code: LabelGateReason.columnCountMismatch.rawValue, concerns: row + "@" + $0) }
            }
        }
        if reasons.contains(.requiredBasisMissing) {
            out.append(.init(code: LabelGateReason.requiredBasisMissing.rawValue, concerns: "per_100"))
        }
        if reasons.contains(.requiredServingDeclarationMissing) {
            if candidate.servingSize == nil {
                out.append(.init(code: LabelGateReason.requiredServingDeclarationMissing.rawValue, concerns: "serving_size"))
            }
            if candidate.servingsPerPack == nil {
                out.append(.init(code: LabelGateReason.requiredServingDeclarationMissing.rawValue, concerns: "servings_per_pack"))
            }
        }
        return out
    }

    static func check(_ result: LabelCheckResult) -> LabelReading.Check {
        let status: LabelReading.Check.Status = switch result.status {
        case .pass: .pass
        case .fail: .fail
        case .notCheckable: .notCheckable
        }
        return LabelReading.Check(name: result.name, basis: result.basis, nutrient: result.nutrient, child: result.child, status: status)
    }

    static func conversion(_ record: PastedLabelConversionRecord) -> PastedLabelManifest.Conversion {
        PastedLabelManifest.Conversion(nutrient: record.nutrient, rule: record.rule.rawValue, ruleVersion: record.ruleVersion,
            sourceHeaderID: record.sourceHeaderID, sourceRowID: record.sourceRowID, operandText: record.operandText,
            operandUnit: record.operandUnit, factorText: record.factorText, intermediateText: record.intermediateText,
            storedText: record.storedText, comparator: record.comparator?.rawValue, rounding: record.rounding)
    }

    static func candidate(_ candidate: LabelCaptureCandidate) -> PastedLabelManifest.Candidate {
        PastedLabelManifest.Candidate(route: candidate.route, inputSHA256: candidate.inputSHA256, declined: candidate.declined,
            declineReasons: candidate.declineReasons, wouldMarkReady: candidate.wouldMarkReady, language: candidate.language.rawValue,
            servingSize: candidate.servingSize.map {
                .init(printedText: $0.printedText, decimalText: $0.decimalText, unit: $0.unit, canonicalUnit: $0.canonicalUnit)
            },
            servingsPerPack: candidate.servingsPerPack.map {
                .init(printedText: $0.printedText, decimalText: $0.decimalText, approximate: $0.approximate)
            },
            headers: candidate.headers.map {
                .init(headerID: $0.headerID, printedText: $0.printedText, basis: $0.basis.rawValue, servingConversion: $0.servingConversion)
            },
            cells: candidate.cells.map {
                .init(rowID: $0.rowID, parentRowID: $0.parentRowID, nutrient: $0.nutrient, printedLabel: $0.printedLabel,
                      headerID: $0.headerID, basis: $0.basis.rawValue, printedText: $0.printedText, comparator: $0.comparator.rawValue,
                      decimalText: $0.decimalText, unit: $0.unit, canonicalUnit: $0.canonicalUnit, servingConversion: $0.servingConversion)
            },
            warnings: candidate.warnings)
    }
}
