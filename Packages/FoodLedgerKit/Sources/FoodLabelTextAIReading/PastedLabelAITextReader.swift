import FoodLedgerApplication
import Foundation
import NutritionLabelParsing

/// The adapter for the `PastedLabelAITextReading` port (docs/pasted-label-ai-text-v1.md 4.2, 4.7,
/// 4.8, 5.2 item 2, 11.1, R5 and D19). Pure and on device, in product order:
///
/// 1. the strict text wire decode (`pasted-label-ai-text-wire-schema-v1`);
/// 2. `pasted-label-ai-text-mapping-v4`, which runs the locator and the unit check;
/// 3. format inference (`pasted-label-ai-text-format-v1` over the frozen inference), then decline gate v2 with the Taiwan format or `.uk`,
///    `label-arithmetic-checks-v2` over the amount bases and the `pasted-label-conversions-v1`
///    conversions for the stored column. The frozen rules are called, never copied;
/// 4. the panel detector, on the text and again on the candidate;
/// 5. the vocabulary check (`pasted-label-ai-text-vocabulary-v3`) on every value's row label and
///    header; a header naming two bases declines before the format step (D33);
/// 6. attention: `label-photo-attention-v1` composed for the gate flags and failed checks, plus the
///    text reasons (`pasted-label-ai-text-attention-v1`).
///
/// The outcome follows D19: only a hard decline declines (the model's own decline, a detector
/// decline, a header naming two bases (D33), a format the text route does not admit, gate G1 or G2, a gate that could not run, or
/// a mapping that leaves no amount value read). G3 to G6 travel to Confirm. It never persists,
/// decides or presents, and never changes a value: the mapped candidate is passed on, never the
/// gate's withheld copy.
public struct PastedLabelAITextReader: PastedLabelAITextReading {
    public static let versions = PastedLabelAITextReadingResult.Versions(
        wireSchema: PastedLabelAITextWire.schemaVersion, mapping: PastedLabelAITextWireMapping.version, locator: PastedLabelTextLocator.version,
        vocabulary: PastedLabelAITextVocabulary.version, detector: PastedLabelAITextPanelDetector.version, attention: PastedLabelAITextAttention.version,
        format: PastedLabelAITextFormat.version, gate: LabelDeclineGate.version, arithmetic: LabelArithmeticChecksV2.version, conversion: PastedLabelConversions.version)

    public init() {}

    public func reading(text: String, textSHA256: String, answer: Data) -> PastedLabelAITextReadingResult {
        let textDetector = PastedLabelAITextPanelDetector.detect(text: text)
        func ended(_ outcome: PastedLabelAITextReadingResult.Outcome, failure: String? = nil, declines: [String] = [], format: String? = nil,
                   candidate: PastedLabelManifest.Candidate? = nil, gate: LabelReading.Gate? = nil,
                   candidateDetector: PastedLabelAITextPanelDetector.Verdict? = nil) -> PastedLabelAITextReadingResult {
            PastedLabelAITextReadingResult(outcome: outcome, failure: failure, declineReasons: declines, textSHA256: textSHA256, inferredFormat: format,
                                           candidate: candidate, gate: gate, checks: [], conversions: [], storedHeaderID: nil,
                                           textDetector: textDetector, candidateDetector: candidateDetector, values: [], servingLines: [],
                                           servingAttention: [:], versions: Self.versions)
        }
        guard text.unicodeScalars.count <= PastedLabelManifest.maximumTextScalars else { return ended(.failed, failure: "text_too_long") }
        guard let wire = PastedLabelAITextWire.decode(answer) else { return ended(.failed, failure: "unreadable_answer") }
        let mapped = PastedLabelAITextWireMapping.map(wire, text: text, inputSHA256: textSHA256)
        let candidate = mapped.candidate
        let projected = Self.candidate(candidate)
        if candidate.declined {
            return ended(.declined, declines: candidate.declineReasons.map { "model:" + $0 }, candidate: projected)
        }
        if textDetector.declines {
            return ended(.declined, declines: textDetector.markers.map { "detector:" + $0.rawValue }, candidate: projected)
        }
        // Revision 15 (D33, vocabulary v2): a header that names two bases (`per 100g/ml`) does not
        // establish the basis from the paste, whatever basis the model gave it, so the reply is
        // declined as a value column with no recognisable basis is (D27).
        // Vocabulary v3 (revision 20): the text is read only at the header's own located span (the
        // locator's single whole-word occurrence; a repeated header ID is not located), so text
        // elsewhere that repeats the header's words never declines the table.
        let headerSpans = Dictionary(mapped.located.headers.compactMap { header in header.status.range.map { (header.id, $0) } },
                                     uniquingKeysWith: { first, _ in first })
        var seenHeaderIDs: Set<String> = []
        if wire.headers.contains(where: { header in
            let span = seenHeaderIDs.insert(header.headerID).inserted ? headerSpans[header.headerID] : nil
            return PastedLabelAITextVocabulary.namesTwoBases(header: header.printedText, located: span, in: text)
        }) {
            return ended(.declined, declines: [PastedLabelAITextVocabulary.twoBasisDecline], candidate: projected)
        }
        // The text route's format step (`pasted-label-ai-text-format-v1`): the frozen inference,
        // then a `mixed` candidate whose text prints the Taiwan title is Taiwan.
        var format = LabelFormatInference.infer(candidate)
        if format == .ambiguous, PastedLabelAITextFormat.mixedIsTaiwan(language: candidate.language.rawValue, text: text) { format = .taiwan }
        guard let gateFormat = format.gateFormat else {
            return ended(.declined, declines: ["format:" + (format.declineCode ?? format.rawValue)], format: format.rawValue, candidate: projected)
        }
        let report = LabelDeclineGate.apply(candidate, format: gateFormat).report
        let gate = LabelReading.Gate(format: gateFormat.rawValue, skipped: report.skipped?.rawValue, hardDeclines: report.hardDeclineCodes,
                                     flags: Self.flags(report, candidate: candidate))
        if let skipped = report.skipped {
            return ended(.declined, declines: ["gate_skipped:" + skipped.rawValue], format: format.rawValue, candidate: projected, gate: gate)
        }
        if !report.hardDeclineCodes.isEmpty {
            return ended(.declined, declines: report.hardDeclineCodes, format: format.rawValue, candidate: projected, gate: gate)
        }
        let candidateDetector = PastedLabelAITextPanelDetector.detect(candidateHeaders: wire.headers.map(\.printedText),
                                                                      rowLabels: wire.rows.map(\.printedLabel), nutrients: wire.rows.map(\.nutrient))
        if candidateDetector.declines {
            return ended(.declined, declines: candidateDetector.markers.map { "detector:" + $0.rawValue }, format: format.rawValue,
                         candidate: projected, gate: gate, candidateDetector: candidateDetector)
        }
        guard candidate.cells.contains(where: { $0.basis != .referenceIntake }) else {
            return ended(.declined, declines: ["no_usable_table"], format: format.rawValue, candidate: projected, gate: gate,
                         candidateDetector: candidateDetector)
        }
        let amountBases = candidate.headers.filter { $0.basis != .referenceIntake }.map(\.basis.rawValue)
        let checks = LabelArithmeticChecksV2.check(LabelArithmeticTable(candidate, format: gateFormat), amountBases: amountBases).checks.map(Self.check)
        let storedHeaderID = PastedLabelStoredColumn.headerID(for: candidate)
        let conversions = storedHeaderID.map { id in
            PastedLabelConversions.conversions(for: candidate, storedHeaderID: id).map { Self.conversion($0.record) }
        } ?? []
        let (values, servingLines, servingAttention) = Self.attention(wire: wire, text: text, mapped: mapped, gate: gate, checks: checks)
        return PastedLabelAITextReadingResult(outcome: .reachedConfirm, failure: nil, declineReasons: [], textSHA256: textSHA256,
                                              inferredFormat: format.rawValue, candidate: projected, gate: gate, checks: checks,
                                              conversions: conversions, storedHeaderID: storedHeaderID, textDetector: textDetector,
                                              candidateDetector: candidateDetector, values: values, servingLines: servingLines,
                                              servingAttention: servingAttention, versions: Self.versions)
    }

    // MARK: Attention

    static func location(_ status: PastedLabelTextLocator.Status) -> LabelPhotoAttention.Location {
        switch status {
        case .found: .found
        case .notFound: .notFound
        case .ambiguous: .ambiguous
        }
    }

    /// Every wire value with its reasons, and the serving lines with theirs.
    static func attention(wire: PastedLabelAITextWire, text: String, mapped: PastedLabelAITextWireMapping.Mapped, gate: LabelReading.Gate,
                          checks: [LabelReading.Check])
        -> ([PastedLabelAITextReadingResult.Value], [PastedLabelAITextReadingResult.ServingLine], [String: [PastedLabelAITextAttention.Reason]]) {
        let basisByID = Dictionary(mapped.candidate.headers.map { ($0.headerID, $0.basis.rawValue) }, uniquingKeysWith: { first, _ in first })
        let headerTextByID = Dictionary(wire.headers.map { ($0.headerID, $0.printedText) }, uniquingKeysWith: { first, _ in first })
        let scan = PastedLabelTextScan(text)
        var servingLines: [PastedLabelAITextReadingResult.ServingLine] = []
        for (id, printed) in [("serving_size", wire.servingSizeText), ("servings_per_pack", wire.servingsPerPackText)] {
            let trimmed = TextPython.strip(printed)
            guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { continue }
            let count = scan.wholeWordOccurrences(of: trimmed).count
            servingLines.append(.init(id: id, printedText: printed, location: count == 1 ? .found : count == 0 ? .notFound : .ambiguous))
        }
        // The photo attention set over the cells, for the gate flags and failed checks.
        let cellID = { (row: Int, value: Int) in "\(row):\(value)" }
        let cells = mapped.values.compactMap { value -> LabelPhotoAttention.Cell? in
            guard value.read.rowID != nil, let located = mapped.located.value(row: value.rowIndex, index: value.valueIndex) else { return nil }
            let header = wire.rows[value.rowIndex].values[value.valueIndex].headerID
            return LabelPhotoAttention.Cell(id: cellID(value.rowIndex, value.valueIndex), nutrient: wire.rows[value.rowIndex].nutrient,
                                            basis: basisByID[header] ?? "", known: true, location: location(located.status))
        }
        let flagged = Set(gate.flags.compactMap(\.nutrient))
        let failed = checks.filter { $0.status == .fail }.map { LabelPhotoAttention.FailedCheck(name: $0.name, basis: $0.basis, nutrient: $0.nutrient, child: $0.child) }
        let findings = LabelPhotoAttention.items(cells: cells, servingLines: servingLines.map { .init(id: $0.id, location: $0.location) },
                                                 gateFlaggedNutrients: flagged, failedChecks: failed)
        let photoReasons = Dictionary(findings.items.map { ($0.id, $0.reasons) }, uniquingKeysWith: { first, _ in first })
        let values = mapped.values.map { value -> PastedLabelAITextReadingResult.Value in
            let row = wire.rows[value.rowIndex]
            let wireValue = row.values[value.valueIndex]
            let status = mapped.located.value(row: value.rowIndex, index: value.valueIndex)?.status ?? .notFound
            var reasons = value.reasons
            // A not-declared marker (mapping v3, D30) takes the locator and vocabulary checks a cell
            // takes, so a marker on a row or column the model may have misassigned is still an item.
            if value.read.rowID != nil || value.read == .notRead(.notDeclared) {
                if let located = mapped.located.value(row: value.rowIndex, index: value.valueIndex),
                   let reason = PastedLabelAITextAttention.reason(located) {
                    reasons.append(reason)
                }
                reasons += (photoReasons[cellID(value.rowIndex, value.valueIndex)] ?? []).map(PastedLabelAITextAttention.Reason.init)
                if let reason = PastedLabelAITextAttention.reason(PastedLabelAITextVocabulary.checkRow(printedLabel: row.printedLabel,
                                                                                                         nutrient: row.nutrient)) {
                    reasons.append(reason)
                }
                if let basis = basisByID[wireValue.headerID], let printed = headerTextByID[wireValue.headerID],
                   let reason = PastedLabelAITextAttention.reason(PastedLabelAITextVocabulary.checkHeader(printedText: printed, basis: basis)) {
                    reasons.append(reason)
                }
            }
            return .init(rowIndex: value.rowIndex, valueIndex: value.valueIndex, nutrient: row.nutrient, printedLabel: row.printedLabel,
                         headerID: wireValue.headerID, basis: basisByID[wireValue.headerID], printedText: wireValue.printedText,
                         modelUnit: wireValue.unit, read: value.read, locator: status, unitCheck: value.unitCheck,
                         reasons: PastedLabelAITextAttention.ordered(reasons))
        }
        var servingAttention: [String: [PastedLabelAITextAttention.Reason]] = [:]
        for line in servingLines {
            let reasons = (photoReasons[line.id] ?? []).map(PastedLabelAITextAttention.Reason.init)
            if !reasons.isEmpty { servingAttention[line.id] = reasons }
        }
        return (values, servingLines, servingAttention)
    }

    // MARK: Projection
    //
    // The same projection as `LabelPhotoReader` (and the pasted route's `NutritionLabelTextReader`),
    // neither of which this target may import: G3 to G6 with what each concerns, check results,
    // conversion records and the candidate on the pasted manifest's shape.

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
