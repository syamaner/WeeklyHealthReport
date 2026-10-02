import Foundation
import FoodLedgerDomain
import FoodLedgerApplication
import FoodLedgerTestSupport
import FoodGenericSearch

private struct Scenario: Decodable {
    let case_id: String; let text: String; let backend: String; let entry: String
    let target_record: String; let action: String
}
private struct Inputs: Decodable { let cases: [Scenario] }
@main struct MultiSourceRunner {
    static func main() throws {
        let inputs = try JSONDecoder().decode(Inputs.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let rows = try inputs.cases.map { try run($0, cofid: CommandLine.arguments[2], usda: CommandLine.arguments[3]) }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[4]))
    }
    private static func run(_ scenario: Scenario, cofid: String, usda: String) throws -> [String: Any] {
        let ids = MultiIDs(), store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store, clock: MultiClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: MultiClock(), ids: ids, calendar: calendar)
        let cofidSource = try CoFIDGenericFoodSearch(corpusURL: URL(fileURLWithPath: cofid), ids: ids)
        let usdaSource = try USDAGenericFoodSearch(corpusURL: URL(fileURLWithPath: usda), ids: ids)
        let searcher: any GenericFoodSearching
        switch scenario.backend {
        case "cofid": searcher = cofidSource
        case "usda": searcher = usdaSource
        case "composite": searcher = CompositeGenericFoodSearch(sources: [cofidSource, usdaSource], ids: ids)
        default: throw FoodLedgerValidationError.invalidProvenance
        }
        let interpretation = FoodQueryInterpretation(scenario.text)
        let parsed = interpretation.parsedQuery
        let importer = FoodListImportService(searcher: searcher, ids: ids)
        var draft: FoodListLineDraft?
        let route: GenericFoodConfirmationRoute?
        if scenario.entry == "list" {
            guard let line = try FoodListParser.parse(scenario.text).first else { throw FoodLedgerValidationError.invalidProvenance }
            let value = FoodListLineDraft(parsed: line, operationID: try ids.makeID(OperationTag.self), evidenceID: try ids.makeID(EvidenceTag.self))
            draft = value
            if case let .candidates(result) = try importer.search(value, at: MultiClock.date, locale: LedgerText("en_GB")) { route = result } else { route = nil }
        } else if !interpretation.allowsDiscovery {
            route = nil
        } else {
            let prep = interpretation.preparation
            let request = GenericFoodSearchRequest(text: try LedgerText(scenario.text), identity: GenericFoodIdentityQuery(preparation: try prep.map { try PreparationState(kind: $0) }), capturedAt: MultiClock.date, locale: try LedgerText("en_GB"))
            if case let .confirmation(result) = try searcher.search(request) { route = result } else { route = nil }
        }
        var validation = "selection_missing", error = "", original = false, provenance = false
        var initial = false, preaccept = false, generic = false, found = false, offered = false, converted = false, reopened = false
        var quantity: Double?, unit: String?, record: String?, savedValue: Double?, savedUnit: String?
        if let route, let index = route.matches.firstIndex(where: { $0.candidate.candidate.recordID.value == scenario.target_record }) {
            found = true
            let milk = try CoFIDWholeMilkVolumeConversion()
            // Match the app's explicit conversion composition: attach its source only
            // for the precisely eligible record. No nutrient reference enters execution.
            let releases = route.confirmation.sourceReleases + (milk.applies(to: route.matches[index].candidate) ? [milk.sourceRelease] : [])
            let input = try PopulatedFoodConfirmation(evidence: route.confirmation.evidence, sourceReleases: releases,
                candidates: route.confirmation.candidates, expectedIdentity: route.confirmation.expectedIdentity,
                expectedEdibleQuantity: route.confirmation.expectedEdibleQuantity)
            var state = FoodConfirmationState(input: input, queryQuantity: parsed.quantity, prefillSourceQuantity: false)
            FoodConfirmationReducer.reduce(state: &state, action: .selectCandidate(index))
            if let draft {
                state.quantity = try importer.confirmation(for: draft, route: route, candidateIndex: index).quantity
            }
            quantity = state.quantity.value; unit = state.quantity.unit.rawValue
            record = state.selectedCandidate.candidate.recordID.value; generic = state.isGenericEstimate
            initial = state.decision == .undecided
            do { _ = try service.save(state, operationID: ids.makeID(OperationTag.self)) }
            catch let observed { let writes = try store.counts().operations; preaccept = (observed as? FoodConfirmationSaveError) == .noAcceptedCandidate && writes == 0 }
            if let value = state.quantity.value {
                let offer = try milk.offer(for: state.selectedCandidate, original: PositiveQuantity(value: value, unit: state.quantity.unit))
                offered = offer != nil
                if scenario.action == "convert" || scenario.action == "convert_then_edit" {
                    if let offer { FoodConfirmationReducer.reduce(state: &state, action: .setConversion(offer)) }
                }
            }
            if scenario.action == "convert_then_edit" { FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(100, .millilitres)) }
            converted = state.quantity.conversion != nil
            FoodConfirmationReducer.reduce(state: &state, action: .accept)
            do {
                let saved = try service.save(state, operationID: ids.makeID(OperationTag.self)); validation = "saved"
                savedValue = saved.logItemVersion.edibleQuantity.value; savedUnit = saved.logItemVersion.edibleQuantity.unit.rawValue
                let p = saved.resolutionVersion.nutrients.entries.flatMap { $0.value.provenance }
                let selected = state.selectedCandidate.candidate
                provenance = saved.resolutionVersion.nutrients == selected.nutrients && !p.isEmpty && p.allSatisfy { provenance in
                    provenance.sourceKind == .genericCompositionDataset && provenance.recordID == selected.recordID && provenance.sourceReleaseID == selected.sourceReleaseID
                    && saved.sourceReleases.contains { release in release.sourceReleaseID == provenance.sourceReleaseID }
                }
                provenance = provenance && selected.evidenceIDs.allSatisfy { id in saved.evidence.contains { $0.evidenceID == id } }
                if let draft {
                    original = try saved.evidence.contains { evidence in
                        guard evidence.evidenceID == draft.evidenceID, evidence.kind == .manual,
                              case let .descriptor(text) = evidence.originalPayload,
                              let payload = try JSONSerialization.jsonObject(with: Data(text.value.utf8)) as? [String: Any] else { return false }
                        return payload["original"] as? String == scenario.text
                    } && saved.evidence.contains { $0.kind == .genericSearch && selected.evidenceIDs.contains($0.evidenceID) }
                } else { original = saved.evidence.contains { $0.originalPayload == .text(try! LedgerText(scenario.text)) } }
                if let restored = try service.reopen(logItemID: saved.logItem.logItemID) {
                    reopened = restored.quantity.conversion == state.quantity.conversion
                    if converted { reopened = reopened && saved.quantityConversion?.sourceReleaseID == milk.sourceRelease.sourceReleaseID && restored.input.sourceReleases.contains(milk.sourceRelease) }
                }
            } catch let observed { validation = "blocked"; error = String(describing: observed) }
        }
        let archive = try store.archiveState()
        let projection = try FoodIntakeProjection(records: archive.records, reportingDate: FoodReportingDay.key(for: MultiClock.date, calendar: calendar))
        let totals: [[String: Any]] = projection.summary.totals.map { ["key": $0.key.rawValue, "known": $0.knownAmount.map { $0 as Any } ?? NSNull(), "incomplete": $0.incompleteContributions, "estimate": $0.includesEstimates] }
        return ["case_id": scenario.case_id, "backend": scenario.backend, "entry": scenario.entry,
            "parser_route": scenario.entry == "list" ? "not_applicable" : parsed.route.rawValue, "target_found": found, "selected_record": record.map { $0 as Any } ?? NSNull(),
            "handoff_value": quantity.map { $0 as Any } ?? NSNull(), "handoff_unit": unit.map { $0 as Any } ?? NSNull(),
            "initially_undecided": initial, "preaccept_blocked": preaccept, "generic_estimate": generic,
            "conversion_offered": offered, "conversion_applied": converted, "reopen_preserved": reopened,
            "validation": validation, "error": error, "edible_value": savedValue.map { $0 as Any } ?? NSNull(), "edible_unit": savedUnit.map { $0 as Any } ?? NSNull(),
            "saved_versions": archive.records.logItemVersions.count, "operations": archive.operations.count,
            "rows": projection.rows.count, "original_preserved": original, "provenance_preserved": provenance, "totals": totals]
    }
}
private struct MultiClock: LedgerClock { static let date = Date(timeIntervalSince1970: 1_700_000_000); func now() -> Date { Self.date } }
private final class MultiIDs: LedgerIDGenerating, @unchecked Sendable {
    private var next = 100
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> { next += 1; return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", next)) }
}
