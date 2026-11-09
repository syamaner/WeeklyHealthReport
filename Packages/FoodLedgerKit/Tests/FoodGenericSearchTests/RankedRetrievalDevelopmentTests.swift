import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Same-author synthetic development replay through the actual bundled adapters.
final class RankedRetrievalDevelopmentTests: XCTestCase {
    func testNamedCutsSurviveFullCoverageAndRankBeforeParentheticalMentionsAcrossSources() throws {
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let sources: [any GenericFoodSearching] = [cofid, usda, CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)]
        for source in sources {
            let query = "250g cooked weight sirloin"
            let request = try GenericFoodSearchRequest(text: LedgerText(query), identity: .init(preparation: PreparationState(kind: .cooked)), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: LedgerText("en_GB"))
            guard case let .confirmation(route) = try source.search(request) else { return XCTFail("Full cut-token coverage should retrieve named cuts") }
            let first = try XCTUnwrap(route.matches.first)
            let direct = first.candidate.name.value.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            XCTAssertTrue(direct.lowercased().contains("sirloin"), direct)
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .cooked })
            XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(try LedgerText(query)))
            XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
            let miss = try GenericFoodSearchRequest(text: LedgerText("250g sirloin zzzzqqqq"), capturedAt: request.capturedAt, locale: request.locale)
            guard case .noResult = try source.search(miss) else { return XCTFail("All meaningful tokens remain required") }
        }
        let request = try GenericFoodSearchRequest(text: LedgerText("sirloin"), identity: .init(preparation: PreparationState(kind: .cooked)), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: LedgerText("en_GB"))
        guard case let .confirmation(route) = try cofid.search(request) else { return XCTFail() }
        XCTAssertTrue(route.matches.contains { $0.candidate.name.value.contains("sirloin steak, grilled") }, "Long source names must not be lost to a numeric score floor")
        for species in ["lamb", "beef", "veal"] {
            let q = try GenericFoodSearchRequest(text: LedgerText("250g cooked \(species) sirloin"), identity: request.identity, capturedAt: request.capturedAt, locale: request.locale)
            guard case let .confirmation(route) = try usda.search(q) else { return XCTFail("Known explicit species should be available") }
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.name.value.lowercased().hasPrefix(species) })
        }
    }

    struct Fixture: Decodable { let version: String; let cases: [Scenario] }
    struct Scenario: Decodable { let id: String; let query: String; let preparation: String?; let market: String? }
    struct Row: Encodable {
        let id: String; let query: String; let source: String
        let records: [String]; let names: [String]; let sourceIDs: [String]
        let candidates: [PopulatedFoodCandidate]; let releases: [SourceRelease]
        let notes: [String?]; let suggestions: [String]

        func removingTaiwanRecords() -> Row {
            let keep = records.indices.filter { !records[$0].hasPrefix("tfda:") }
            return Row(id: id, query: query, source: source, records: keep.map { records[$0] }, names: keep.map { names[$0] },
                       sourceIDs: keep.map { sourceIDs[$0] }, candidates: keep.map { candidates[$0] },
                       releases: releases.filter { !$0.sourceReleaseID.value.hasPrefix("tfda") },
                       notes: keep.map { notes[$0] }, suggestions: suggestions)
        }
    }
    func testGenericRepresentationPreferenceRunsBeforeTruncationAndAcrossSources() throws {
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        for source in [cofid as any GenericFoodSearching, usda as any GenericFoodSearching,
            CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)] {
            for (query, preferred) in [("Greek yoghurt", "plain"), ("200ml milk", "whole"), ("0.25kg rice", "white")] {
                let request = GenericFoodSearchRequest(text: try LedgerText(query), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
                guard case let .confirmation(route) = try source.search(request) else { return XCTFail(query) }
                XCTAssertTrue(try XCTUnwrap(route.matches.first).candidate.name.value.lowercased().contains(preferred), query)
                XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(request.text))
            }
        }
    }
    func testUnrequestedPartsFollowMeatOnlyAndRequestedPartsLead() throws {
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        for source in [cofid as any GenericFoodSearching, CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)] {
            let request = GenericFoodSearchRequest(text: try LedgerText("150 g grilled chicken"), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
            guard case let .confirmation(route) = try source.search(request) else { return XCTFail("grilled chicken") }
            let names = route.matches.map { $0.candidate.name.value }
            let first = try XCTUnwrap(names.first)
            XCTAssertTrue(first.contains("meat only") && !first.hasPrefix("Chicken, skin"), first)
            let skin = try XCTUnwrap(names.firstIndex { $0.hasPrefix("Chicken, skin, roasted/grilled") })
            let meatOnly = try XCTUnwrap(names.firstIndex { $0.contains("without skin, meat only") })
            XCTAssertLessThan(meatOnly, skin)
            XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(request.text))
            let liver = GenericFoodSearchRequest(text: try LedgerText("chicken liver"), capturedAt: request.capturedAt, locale: request.locale)
            guard case let .confirmation(liverRoute) = try source.search(liver) else { return XCTFail("chicken liver") }
            XCTAssertTrue(try XCTUnwrap(liverRoute.matches.first).candidate.name.value.lowercased().contains("liver"))
        }
    }

    func testExplicitQualifiersAndHardPreparationRemainAuthoritative() throws {
        let search = try USDAGenericFoodSearch(ids: ReplayIDs())
        for (text, required) in [("red rice", "red"), ("sheep milk", "sheep"), ("bison ribeye", "bison"), ("strawberry Greek yoghurt", "strawberry")] {
            let request = GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
            guard case let .confirmation(route) = try search.search(request) else { return XCTFail(text) }
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.name.value.lowercased().contains(required) })
        }
        let request = GenericFoodSearchRequest(text: try LedgerText("ribeye"), identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .cooked)), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try search.search(request) else { return XCTFail("ribeye") }
        XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .cooked })
    }

    func testWholeEggPreferencePreservesExplicitWhitesAndGreekStyleNames() throws {
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        for (sourceIndex, source) in [cofid as any GenericFoodSearching, usda as any GenericFoodSearching,
                       CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)].enumerated() {
            for text in ["2 eggs", "egg white", "Greek yoghurt", "Greek-style yoghurt"] {
                let request = GenericFoodSearchRequest(text: try LedgerText(text), capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
                guard case let .confirmation(route) = try source.search(request) else {
                    // USDA has Greek yoghurt, but no Greek-style record; never substitute the type.
                    XCTAssertEqual(text, "Greek-style yoghurt")
                    XCTAssertEqual(sourceIndex, 1)
                    continue
                }
                let name = try XCTUnwrap(route.matches.first).candidate.name.value.lowercased()
                if text == "2 eggs" { XCTAssertFalse(name.contains("white"), name); XCTAssertTrue(name.contains("whole"), name) }
                if text == "egg white" { XCTAssertTrue(name.contains("white"), name) }
                if text == "Greek-style yoghurt" { XCTAssertTrue(name.contains("style"), name) }
                if text == "Greek yoghurt" {
                    for match in route.matches where match.candidate.name.value.lowercased().contains("style") {
                        XCTAssertTrue(try XCTUnwrap(FoodQueryCandidateAssessment.note(query: request.parsedQuery, candidate: match.candidate)).contains("Tentative alternative"))
                    }
                }
            }
        }
    }

    /// One replay of the latest scenario set feeds every frozen report version.
    /// v3 and v4 rows use the original two-source composite, so their earlier
    /// labels and expected reports stay comparable; v3 rows are the v4 rows for
    /// the unchanged v3 case identifiers. v5 rows use the production composite
    /// with Taiwan TFDA as a regional source and the scenario's market; v6
    /// rows are the v5 rows plus the plural/singular cases (food-lexical-terms-v9);
    /// v7 rows are the v6 rows plus the dark chocolate cocoa cases (cocoa-percent-policy-v1).
    /// v8 rows (#384, docs/ciqual-2025-admission-v1.md) are the v7 cases plus three chocolate
    /// type cases, with the composite row from the production composite: Ciqual as a
    /// reference-only source (composite-generic-ranking-v11). The v3 to v7 rows keep their
    /// source lists; the v8 composite reuses each case's CoFID, USDA and TFDA searches.
    func testReplay() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Tools/FoodSearchQuality")
        func load(_ name: String) throws -> Fixture {
            try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
        }
        let v3 = try load("retrieval-scenarios-v3.json"), v4 = try load("retrieval-scenarios-v4.json")
        let v5 = try load("retrieval-scenarios-v5.json"), v6 = try load("retrieval-scenarios-v6.json")
        let v7 = try load("retrieval-scenarios-v7.json")
        let fixture = try load("retrieval-scenarios-v8.json")
        for earlier in [v3, v4, v5, v6, v7] {
            XCTAssertEqual(earlier.cases.map(\.id), Array(fixture.cases.prefix(earlier.cases.count)).map(\.id))
            XCTAssertEqual(earlier.cases.map(\.query), Array(fixture.cases.prefix(earlier.cases.count)).map(\.query))
        }
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let tfda = try TFDAGenericFoodSearch(ids: ids)
        let ciqual = try CiqualGenericFoodSearch(ids: ids)
        let baseline = ProcessInfo.processInfo.environment["WHR_RETRIEVAL_REPORT_V5_BASELINE"] != nil
        let v3IDs = Set(v3.cases.map(\.id)), v4IDs = Set(v4.cases.map(\.id)), v5IDs = Set(v5.cases.map(\.id))
        let v6IDs = Set(v6.cases.map(\.id)), v7IDs = Set(v7.cases.map(\.id))
        struct CaseRows { var local: [Row] = []; var composite: Row?; var production: Row?; var baseline: Row?; var failure: String? }
        /// One scenario's rows. The searchers hold no mutable state and every composite request
        /// carries its own capture evidence, so each case has its own caches and the cases run
        /// concurrently; rows are reassembled in fixture order below (CI time, #405). The scorer
        /// reads record IDs, names and sources only, never the generated ledger identifiers.
        func replayCase(_ scenario: Scenario) throws -> CaseRows {
            // Pure caches keyed by the composite's evidence: the v8 composite repeats the v7
            // composite's source searches, so v3 to v7 rows are unchanged.
            let shared = [SharedSearch(cofid), SharedSearch(usda), SharedSearch(tfda)]
            let request = try replayRequest(scenario)
            let promoted = RegionalSourceOrderPolicy.promotesTaiwan(query: scenario.query, marketIsTaiwan: scenario.market == "taiwan")
            let promotes: (GenericFoodSearchRequest) -> Bool = { request in
                RegionalSourceOrderPolicy.promotesTaiwan(query: request.text.value, marketIsTaiwan: scenario.market == "taiwan")
            }
            let regional = CompositeGenericFoodSearch(sources: [shared[0], shared[1]], regionalSources: [shared[2]],
                                                      promotesRegional: promotes, ids: ids)
            let production = CompositeGenericFoodSearch(sources: [shared[0], shared[1]], regionalSources: [shared[2]],
                                                        referenceSources: [ciqual], promotesRegional: promotes, ids: ids)
            var result = CaseRows()
            result.local = [try replayRow(scenario, source: "cofid", request: request, search: cofid),
                            try replayRow(scenario, source: "usda", request: request, search: usda)]
            let composite = try replayRow(scenario, source: "composite", request: request, search: regional)
            guard let evidence = shared[0].lastEvidence else { throw ReplayFailure.noEvidence(scenario.id) }
            let productionRequest = GenericFoodSearchRequest(text: request.text, identity: request.identity, capturedAt: request.capturedAt,
                                                             locale: request.locale, captureEvidence: evidence)
            result.production = try replayRow(scenario, source: "composite", request: productionRequest, search: production)
            result.composite = composite
            if v4IDs.contains(scenario.id) && promoted { result.failure = "\(scenario.id): a v4 case promotes Taiwan" }
            if baseline {
                // composite-generic-ranking-v8 equivalent: every source interleaved.
                let interleaved = CompositeGenericFoodSearch(sources: [cofid, usda, tfda], ids: ids)
                result.baseline = try replayRow(scenario, source: "composite", request: request, search: interleaved)
            }
            return result
        }
        let lock = NSLock()
        var results = [CaseRows](repeating: CaseRows(), count: fixture.cases.count)
        DispatchQueue.concurrentPerform(iterations: fixture.cases.count) { index in
            let scenario = fixture.cases[index]
            let result: CaseRows
            do { result = try replayCase(scenario) } catch { result = CaseRows(failure: "\(scenario.id): \(error)") }
            lock.lock(); defer { lock.unlock() }
            results[index] = result
        }
        XCTAssertEqual(results.compactMap(\.failure), [])
        var rows: [Row] = [], regionalRows: [Row] = [], baselineRows: [Row] = [], productionRows: [Row] = []
        for (scenario, result) in zip(fixture.cases, results) {
            guard let composite = result.composite, let production = result.production else { continue }
            productionRows += result.local + [production]
            regionalRows += result.local + [composite]
            if v4IDs.contains(scenario.id) {
                // When Taiwan is not promoted, v9 places every TFDA row after the UK and US
                // rows without reordering them, so the two-source composite used by the
                // v3 and v4 labels is the regional row without TFDA records (exact for scored fields).
                // This avoids searching CoFID and USDA a third time per case.
                rows += result.local + [composite.removingTaiwanRecords()]
            }
            if let row = result.baseline { baselineRows += result.local + [row] }
        }
        try write(rows.filter { v3IDs.contains($0.id) }, environment: "WHR_RETRIEVAL_REPORT")
        try write(rows, environment: "WHR_RETRIEVAL_REPORT_V4")
        try write(regionalRows.filter { v5IDs.contains($0.id) }, environment: "WHR_RETRIEVAL_REPORT_V5")
        try write(regionalRows.filter { v6IDs.contains($0.id) }, environment: "WHR_RETRIEVAL_REPORT_V6")
        try write(regionalRows.filter { v7IDs.contains($0.id) }, environment: "WHR_RETRIEVAL_REPORT_V7")
        try write(productionRows, environment: "WHR_RETRIEVAL_REPORT_V8")
        if baseline { try write(baselineRows.filter { v5IDs.contains($0.id) }, environment: "WHR_RETRIEVAL_REPORT_V5_BASELINE") }
    }

    func testTwoSourceRowsEqualRegionalRowsWithoutTaiwanWhenNotPromoted() throws {
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let regional = CompositeGenericFoodSearch(sources: [cofid, usda], regionalSources: [try TFDAGenericFoodSearch(ids: ids)], ids: ids)
        let twoSource = CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)
        for query in ["120 g banana", "rice", "guava", "100g apple", "250g cooked weight sirloin", "milk",
                      "dark chocolate 85%", "100% cacao", "dark chocolate"] {
            let scenario = Scenario(id: query, query: query, preparation: nil, market: nil)
            let request = try replayRequest(scenario)
            XCTAssertEqual(try replayRow(scenario, source: "composite", request: request, search: regional).removingTaiwanRecords().records,
                           try replayRow(scenario, source: "composite", request: request, search: twoSource).records, query)
        }
    }

    private func replayRequest(_ scenario: Scenario) throws -> GenericFoodSearchRequest {
        let preparation = try scenario.preparation.map { value in
            try PreparationState(kind: XCTUnwrap(PreparationKind(rawValue: value)))
        }
        return GenericFoodSearchRequest(text: try LedgerText(scenario.query),
            identity: GenericFoodIdentityQuery(preparation: preparation),
            capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
    }

    private func replayRow(_ scenario: Scenario, source: String, request: GenericFoodSearchRequest,
                           search: any GenericFoodSearching) throws -> Row {
        switch try search.search(request) {
        case let .confirmation(route):
            XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(request.text))
            let candidates = route.matches.map(\.candidate)
            XCTAssertTrue(candidates.allSatisfy { candidate in
                route.confirmation.sourceReleases.contains { $0.sourceReleaseID == candidate.candidate.sourceReleaseID }
            })
            return Row(id: scenario.id, query: scenario.query, source: source,
                records: candidates.map { $0.candidate.recordID.value }, names: candidates.map { $0.name.value },
                sourceIDs: candidates.map { $0.candidate.sourceReleaseID.value }, candidates: candidates,
                releases: route.confirmation.sourceReleases,
                notes: candidates.map { FoodQueryCandidateAssessment.note(query: request.parsedQuery, candidate: $0) }, suggestions: [])
        case let .noResult(route):
            XCTAssertEqual(route.evidence.originalPayload, .text(request.text))
            return Row(id: scenario.id, query: scenario.query, source: source, records: [], names: [],
                sourceIDs: [], candidates: [], releases: [], notes: [], suggestions: route.suggestedQueries)
        }
    }

    private func write(_ rows: [Row], environment: String) throws {
        guard let output = ProcessInfo.processInfo.environment[environment] else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rows).write(to: URL(fileURLWithPath: output))
    }
}
/// Returns the stored outcome for a repeated request with the same capture evidence; requests
/// without evidence are always searched.
private final class SharedSearch: GenericFoodSearching, @unchecked Sendable {
    let inner: any GenericFoodSearching
    var lastEvidence: CaptureEvidence?
    private var cache: [String: GenericFoodSearchOutcome] = [:]
    init(_ inner: any GenericFoodSearching) { self.inner = inner }
    func clear() { cache = [:] }
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        guard let evidence = request.captureEvidence else { return try inner.search(request) }
        lastEvidence = evidence
        let key = "\(request.text.value)|\(String(describing: request.identity))|\(evidence.evidenceID.rawValue)|\(request.additionalEvidence.count)"
        if let hit = cache[key] { return hit }
        let outcome = try inner.search(request)
        cache[key] = outcome
        return outcome
    }
}
/// Sequential identifiers, locked because the replay's cases run concurrently (#405); the
/// order they are handed out in is not part of any scored field.
private final class ReplayIDs: LedgerIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        lock.lock(); defer { lock.unlock() }
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
private enum ReplayFailure: Error { case noEvidence(String) }
