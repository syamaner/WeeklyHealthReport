import Foundation
import FoodLedgerDomain
import FoodLedgerApplication
import FoodLedgerTestSupport
import FoodGenericSearch
private struct Selection: Decodable { let line: Int; let target_record: String }
private struct Scenario: Decodable { let case_id: String; let text: String; let selections: [Selection] }
private struct Inputs: Decodable { let cases: [Scenario] }
@main struct ListJourneyRunner {
    static func main() throws {
        let input = try JSONDecoder().decode(Inputs.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let rows = try input.cases.map { try execute($0, corpus: CommandLine.arguments[2]) }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    }
    private static func execute(_ scenario: Scenario, corpus: String) throws -> [String: Any] {
        let ids = ListIDs(); let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try ids.makeID(ActorTag.self),committer:store,clock:ListClock(),encoder:FoundationCanonicalJSONEncoder(),digester:SHA256Digester())
        var calendar = Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let service = FoodConfirmationService(ledger:ledger,reader:store,clock:ListClock(),ids:ids,calendar:calendar)
        let searcher = try CoFIDGenericFoodSearch(corpusURL:URL(fileURLWithPath:corpus),ids:ids)
        let importer = FoodListImportService(searcher:searcher,ids:ids)
        let parsed = try FoodListParser.parse(scenario.text)
        var lines: [[String:Any]] = []
        for line in parsed {
            var outcome="context",error="",initial=false,blocked=false,provenance=false
            var original: Bool?
            var handoff:Double?,unit:String?,record:String?
            let before = try store.counts().operations
            if !line.notices.contains(.contextLine) {
                let draft = FoodListLineDraft(parsed:line,operationID:try ids.makeID(OperationTag.self),evidenceID:try ids.makeID(EvidenceTag.self))
                switch try importer.search(draft,at:ListClock.date,locale:LedgerText("en_GB")) {
                case .unresolved: outcome="unresolved"
                case let .candidates(route):
                    if let selection = scenario.selections.first(where:{$0.line==line.lineNumber}),let index=route.matches.firstIndex(where:{$0.candidate.candidate.recordID.value==selection.target_record}) {
                        var state=try importer.confirmation(for:draft,route:route,candidateIndex:index)
                        record=state.selectedCandidate.candidate.recordID.value
                        handoff=state.quantity.value;unit=state.quantity.unit.rawValue;initial=state.decision == .undecided
                        do { _=try service.save(state,operationID:ids.makeID(OperationTag.self)) }
                        catch let observed { let writes=try store.counts().operations;blocked=(observed as? FoodConfirmationSaveError) == .noAcceptedCandidate && writes==before }
                        FoodConfirmationReducer.reduce(state:&state,action:.accept)
                        do {
                            let saved=try service.save(state,operationID:draft.operationID);outcome="saved"
                            let p=saved.resolutionVersion.nutrients.entries.flatMap{$0.value.provenance}
                            provenance=saved.resolutionVersion.nutrients==state.selectedCandidate.candidate.nutrients && !p.isEmpty && p.allSatisfy{$0.recordID?.value==record && $0.sourceReleaseID==state.selectedCandidate.candidate.sourceReleaseID && $0.sourceKind == .genericCompositionDataset && $0.manifestReference?.value=="cofid-2021-generic-search-v1.json"} && saved.candidateDecision.candidate.evidenceIDs.contains(draft.evidenceID) && saved.evidence.contains{$0.evidenceID==draft.evidenceID} && saved.evidence.contains{$0.kind == .genericSearch && saved.candidateDecision.candidate.evidenceIDs.contains($0.evidenceID)}
                        } catch let observed { outcome="blocked";error=String(describing:observed) }
                        original=try route.confirmation.evidence.contains{evidence in
                            guard evidence.evidenceID == draft.evidenceID, evidence.kind == .manual else { return false }
                            guard case let .descriptor(text)=evidence.originalPayload,let data=text.value.data(using:.utf8),let payload=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{return false}
                            return payload["original"] as? String == line.original && payload["lineNumber"] as? Int == line.lineNumber
                        }
                    } else { outcome="selection_missing";original=false }
                }
            }
            let after=try store.counts().operations
            lines.append(["line":line.lineNumber,"original":line.original,"query":line.query,"quantity":line.quantity.map{$0 as Any} ?? NSNull(),"unit":line.unit.map{$0.rawValue as Any} ?? NSNull(),"preparation":line.preparation.map{$0.rawValue as Any} ?? NSNull(),"notices":line.notices.map{$0.rawValue},"handoff":handoff.map{$0 as Any} ?? NSNull(),"handoff_unit":unit.map{$0 as Any} ?? NSNull(),"record":record.map{$0 as Any} ?? NSNull(),"outcome":outcome,"error":error,"initially_undecided":initial,"preaccept_blocked":blocked,"write_delta":after-before,"original_preserved":original.map{$0 as Any} ?? NSNull(),"provenance_preserved":provenance])
        }
        let archive=try store.archiveState();let projection=try FoodIntakeProjection(records:archive.records,reportingDate:FoodReportingDay.key(for:ListClock.date,calendar:calendar))
        let totals:[[String:Any]]=projection.summary.totals.map{["key":$0.key.rawValue,"known":$0.knownAmount.map{$0 as Any} ?? NSNull(),"incomplete":$0.incompleteContributions,"estimate":$0.includesEstimates]}
        return ["case_id":scenario.case_id,"lines":lines,"saved_count":projection.rows.count,"saved_versions":archive.records.logItemVersions.count,"operations":archive.operations.count,"evidence_count":archive.records.evidence.count,"assertions":archive.records.assertions.count,"outstanding_food_lines":lines.filter{!(["saved","context"].contains($0["outcome"] as! String))}.count,"totals":totals]
    }
}
private struct ListClock:LedgerClock{static let date=Date(timeIntervalSince1970:1_700_000_000);func now()->Date{Self.date}}
private final class ListIDs:LedgerIDGenerating,@unchecked Sendable{private var next=100;func makeID<Tag>(_ tag:Tag.Type)throws->LedgerID<Tag>{next+=1;return try LedgerID(String(format:"00000000-0000-0000-0000-%012x",next))}}
