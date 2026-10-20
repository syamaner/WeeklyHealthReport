import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import NutritionLabelParsing

/// Adapter for the `LabelTextReading` port (`docs/pasted-nutrition-label-v1.md` sections 2.4
/// and 8.1, decision 10). It runs, on device and in order: parser v3
/// (`docs/pasted-nutrition-label-reader-v3.md`) on the exact text, format inference, the faithful
/// gate v2 port, the `pasted-label-conversions-v1` conversions for the stored column and the
/// `label-arithmetic-checks-v1` checks, and maps their output to the
/// application's `LabelReading`. It never persists, decides or presents, and never changes a
/// value: G3 to G6 stay findings here (the application turns them into Confirm flags), so the
/// parser's candidate is passed on as parsed, never the gate's withheld copy.
public struct NutritionLabelTextReader: LabelTextReading {
    private let parser = NutritionLabelTextParserV3()

    public init() {}

    /// The versions of an ordinary read (checks v1).
    public static let versions = LabelReading.Versions(parser: NutritionLabelTextParserV3.version, gate: LabelDeclineGate.version,
        arithmetic: LabelArithmeticChecks.version, conversion: PastedLabelConversions.version,
        formatInference: LabelFormatInference.version)
    /// The versions of a read with asserted bases (checks v2; reader v3 section 8.4.5).
    public static let assertedVersions = LabelReading.Versions(parser: NutritionLabelTextParserV3.version, gate: LabelDeclineGate.version,
        arithmetic: LabelArithmeticChecksV2.version, conversion: PastedLabelConversions.version,
        formatInference: LabelFormatInference.version)

    /// Reader v3 section 8.4.2: with `assertedBases`, parser v3 reads the text with them in place
    /// of the amount headers that were never printed (declining `asserted_bases_mismatch` when they
    /// do not fit) and the checks are v2; without, an ordinary read, and a `no_basis_header`
    /// decline carries the parser's unheaded shape as `UnheadedTable`.
    public func read(_ text: String, textSHA256: String, assertedBases: AssertedBases?) -> LabelReading {
        let candidate: LabelCaptureCandidate
        var unheaded: UnheadedTable?
        if let assertedBases {
            candidate = parser.parse(text, route: "A", inputSHA256: textSHA256, assertedBases: assertedBases.columns.map(Self.basis))
        } else {
            candidate = parser.parse(text, route: "A", inputSHA256: textSHA256)
            if candidate.declineReasons == ["no_basis_header"] {
                unheaded = parser.unheadedShape(text, route: "A", inputSHA256: textSHA256).map(Self.unheadedTable)
            }
        }
        let format = LabelFormatInference.infer(candidate)
        var gate: LabelReading.Gate?
        var checks: [LabelReading.Check] = []
        var conversions: [PastedLabelManifest.Conversion] = []
        let storedHeaderID = candidate.declined ? nil : PastedLabelStoredColumn.headerID(for: candidate)
        if !candidate.declined, let gateFormat = format.gateFormat {
            let report = LabelDeclineGate.apply(candidate, format: gateFormat).report
            gate = LabelReading.Gate(format: gateFormat.rawValue, skipped: report.skipped?.rawValue,
                                     hardDeclines: report.hardDeclineCodes, flags: Self.flags(report, candidate: candidate))
            let table = LabelArithmeticTable(candidate, format: gateFormat)
            if assertedBases != nil {
                let amountBases = candidate.headers.filter { $0.basis != .referenceIntake }.map(\.basis.rawValue)
                checks = LabelArithmeticChecksV2.check(table, amountBases: amountBases).checks.map(Self.check)
            } else {
                checks = LabelArithmeticChecks.check(table).checks.map(Self.check)
            }
        }
        if let storedHeaderID {
            conversions = PastedLabelConversions.conversions(for: candidate, storedHeaderID: storedHeaderID).map { Self.conversion($0.record) }
        }
        return LabelReading(origin: .pastedText, textSHA256: textSHA256, candidate: Self.candidate(candidate), format: format.rawValue,
                            gate: gate, checks: checks, conversions: conversions, storedHeaderID: storedHeaderID,
                            versions: assertedBases == nil ? Self.versions : Self.assertedVersions, unheadedTable: unheaded)
    }

    static func basis(_ basis: AssertedBases.Basis) -> LabelBasis {
        switch basis {
        case .perServing: .perServing
        case .per100g: .per100g
        case .per100ml: .per100ml
        }
    }

    static func unheadedTable(_ shape: NutritionLabelTextParserV3.UnheadedShape) -> UnheadedTable {
        let hint = shape.energyLineHint.flatMap { hint -> UnheadedTable.EnergyLineHint? in
            AssertedBases.Basis(rawValue: hint.basis.rawValue).map { UnheadedTable.EnergyLineHint(printedText: hint.printedText, basis: $0) }
        }
        return UnheadedTable(amountColumnCount: shape.amountColumnCount, referenceColumnPrinted: shape.referenceColumnPrinted,
            servingSize: shape.servingSize.map {
                .init(printedText: $0.printedText, decimalText: $0.decimalText, unit: $0.unit, canonicalUnit: $0.canonicalUnit)
            },
            servingsPerPack: shape.servingsPerPack.map {
                .init(printedText: $0.printedText, decimalText: $0.decimalText, approximate: $0.approximate)
            },
            energyLineHint: hint)
    }

    // MARK: Mapping

    /// G3 to G6 with the row, cell or line each concerns, in rule order. Recomputed from the same
    /// rows and columns gate v2 reads, only for the reasons the gate reported.
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

/// Adapter for the `PastedLabelConversionChecking` port: recomputes a stored conversion record
/// with `PastedLabelConversions.storedTextMatches` (steps 1 to 4 from `operand_text` and the
/// rule; the intermediate is never compared). A rule or comparator the parser does not know
/// fails closed.
public struct NutritionLabelConversionChecker: PastedLabelConversionChecking {
    public init() {}

    public func storedTextMatches(_ record: PastedLabelManifest.Conversion) -> Bool {
        guard let rule = PastedLabelConversionRule(rawValue: record.rule) else { return false }
        var comparator: PastedLabelConversionComparator?
        if let text = record.comparator {
            guard let known = PastedLabelConversionComparator(rawValue: text) else { return false }
            comparator = known
        }
        return PastedLabelConversions.storedTextMatches(PastedLabelConversionRecord(nutrient: record.nutrient, rule: rule,
            ruleVersion: record.ruleVersion, sourceHeaderID: record.sourceHeaderID, sourceRowID: record.sourceRowID,
            operandText: record.operandText, operandUnit: record.operandUnit, factorText: record.factorText,
            intermediateText: record.intermediateText, storedText: record.storedText, comparator: comparator, rounding: record.rounding))
    }
}
