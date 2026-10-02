import Foundation
import FoodLedgerDomain
import FoodLedgerApplication
import FoodLedgerTestSupport
import FoodGenericSearch

private struct Scenario: Decodable { let case_id: String; let text: String; let target_record: String?; let action: String }
private struct Inputs: Decodable { let cases: [Scenario] }
@main struct LinkedRunner {
    static func main() throws {
        let inputs = try JSONDecoder().decode(Inputs.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let observations = try inputs.cases.map { try run($0, corpus: CommandLine.arguments[2]) }
        try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    }
    private static func run(_ scenario: Scenario, corpus: String) throws -> [String: Any] {
        let ids = LinkedIDs()
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self), committer: store, clock: LinkedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: LinkedClock(), ids: ids, calendar: calendar)
        let searcher = try CoFIDGenericFoodSearch(corpusURL: URL(fileURLWithPath: corpus), ids: ids)
        let interpretation = FoodQueryInterpretation(scenario.text)
        let parsed = interpretation.parsedQuery
        var retrieval = "not_run", validation = "not_run", error = ""
        var targetFound = false, initiallyUndecided = false, preacceptBlocked = false, originalPreserved = false, provenancePreserved = false
        var genericEstimate = false, selectedRecord: String?
        var handoffValue: Double?, handoffUnit: String?
        var state: FoodConfirmationState?
        if interpretation.allowsDiscovery {
            let prep = interpretation.preparation
            let request = GenericFoodSearchRequest(text: try LedgerText(scenario.text), identity: GenericFoodIdentityQuery(preparation: try prep.map { try PreparationState(kind: $0) }), capturedAt: LinkedClock.date, locale: try LedgerText("en_GB"))
            switch try searcher.search(request) {
            case let .noResult(route):
                retrieval = "no_result"
                originalPreserved = route.evidence.originalPayload == .text(try LedgerText(scenario.text))
            case let .confirmation(route):
                retrieval = "confirmation"
                var draft = FoodConfirmationState(input: route.confirmation, queryQuantity: parsed.quantity, prefillSourceQuantity: false)
                handoffValue = draft.quantity.value; handoffUnit = draft.quantity.unit.rawValue
                initiallyUndecided = draft.decision == .undecided
                do { _ = try service.save(draft, operationID: ids.makeID(OperationTag.self)) }
                catch let observed { let writes = try store.counts().operations; preacceptBlocked = (observed as? FoodConfirmationSaveError) == .noAcceptedCandidate && writes == 0 }
                if let target = scenario.target_record, let index = route.matches.firstIndex(where: { $0.candidate.candidate.recordID.value == target }) {
                    targetFound = true
                    FoodConfirmationReducer.reduce(state: &draft, action: .selectCandidate(index))
                    selectedRecord = draft.selectedCandidate.candidate.recordID.value
                    genericEstimate = draft.isGenericEstimate
                    if scenario.action == "clear" { FoodConfirmationReducer.reduce(state: &draft, action: .setQuantity(nil, .grams)) }
                    if scenario.action != "unaccepted" { FoodConfirmationReducer.reduce(state: &draft, action: .accept) }
                    state = draft
                    do { _ = try service.save(draft, operationID: ids.makeID(OperationTag.self)); validation = "saved" }
                    catch let observed { validation = "blocked"; error = String(describing: observed) }
                } else { validation = "selection_missing" }
                originalPreserved = route.confirmation.evidence.contains { $0.originalPayload == .text(try! LedgerText(scenario.text)) }
            }
        }
        let archive = try store.archiveState()
        let projection = try FoodIntakeProjection(records: archive.records, reportingDate: FoodReportingDay.key(for: LinkedClock.date, calendar: calendar))
        if let state, !archive.records.logItemVersions.isEmpty {
            originalPreserved = originalPreserved && archive.records.evidence.contains { $0.originalPayload == .text(try! LedgerText(scenario.text)) }
            let candidate = state.selectedCandidate.candidate
            let sourceProvenance = archive.records.resolutionVersions.flatMap { $0.nutrients.entries.flatMap { $0.value.provenance } }
            let evidenceLinked = archive.records.candidateDecisions.contains { decision in
                decision.candidate.recordID == candidate.recordID && decision.candidate.evidenceIDs == candidate.evidenceIDs && candidate.evidenceIDs.allSatisfy { evidenceID in archive.records.evidence.contains { $0.evidenceID == evidenceID } }
            }
            provenancePreserved = archive.records.resolutionVersions.count == 1 && archive.records.resolutionVersions[0].nutrients == candidate.nutrients && !sourceProvenance.isEmpty && evidenceLinked && sourceProvenance.allSatisfy { p in
                p.sourceKind == .genericCompositionDataset && p.recordID?.value == selectedRecord && p.sourceReleaseID == candidate.sourceReleaseID && p.manifestReference?.value == "cofid-2021-generic-search-v1.json" && archive.records.sourceReleases.contains { $0.sourceReleaseID == p.sourceReleaseID && $0.sourceID == p.sourceID }
            }
        }
        let totals: [[String: Any]] = projection.summary.totals.map { ["key": $0.key.rawValue, "known": $0.knownAmount.map { $0 as Any } ?? NSNull(), "incomplete": $0.incompleteContributions, "estimate": $0.includesEstimates] }
        return ["case_id":scenario.case_id, "parser_route":parsed.route.rawValue, "parsed_quantity":parsed.quantity.map { $0.value as Any } ?? NSNull(), "parsed_unit":parsed.quantity.map { $0.unit as Any } ?? NSNull(),
            "retrieval":retrieval, "target_found":targetFound, "initially_undecided":initiallyUndecided, "preaccept_blocked":preacceptBlocked,
            "handoff_value":handoffValue.map { $0 as Any } ?? NSNull(), "handoff_unit":handoffUnit.map { $0 as Any } ?? NSNull(),
            "selected_record":selectedRecord.map { $0 as Any } ?? NSNull(), "generic_estimate":genericEstimate,
            "validation":validation, "error":error, "saved_versions":archive.records.logItemVersions.count, "operations":archive.operations.count,
            "assertions":archive.records.assertions.count, "rows":projection.rows.count,
            "original_preserved":originalPreserved,"provenance_preserved":provenancePreserved,"totals":totals]
    }
}
private struct LinkedClock: LedgerClock {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { Self.date }
}
private final class LinkedIDs: LedgerIDGenerating, @unchecked Sendable {
    private var next = 100
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> { next += 1; return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", next)) }
}
