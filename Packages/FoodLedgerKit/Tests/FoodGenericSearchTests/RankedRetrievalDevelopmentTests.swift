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
    struct Scenario: Decodable { let id: String; let query: String; let preparation: String? }
    struct Row: Encodable {
        let id: String; let query: String; let source: String
        let records: [String]; let names: [String]; let sourceIDs: [String]
        let candidates: [PopulatedFoodCandidate]; let releases: [SourceRelease]
        let notes: [String?]; let suggestions: [String]
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

    func testReplay() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Tools/FoodSearchQuality/retrieval-scenarios-v3.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: path))
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let sources: [(String, any GenericFoodSearching)] = [
            ("cofid", cofid), ("usda", usda),
            ("composite", CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids))
        ]
        var rows: [Row] = []
        for scenario in fixture.cases {
            let preparation = try scenario.preparation.map { value in
                try PreparationState(kind: XCTUnwrap(PreparationKind(rawValue: value)))
            }
            let request = GenericFoodSearchRequest(text: try LedgerText(scenario.query),
                identity: GenericFoodIdentityQuery(preparation: preparation),
                capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
            for (source, search) in sources {
                switch try search.search(request) {
                case let .confirmation(route):
                    XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(request.text))
                    let candidates = route.matches.map(\.candidate)
                    XCTAssertTrue(candidates.allSatisfy { candidate in
                        route.confirmation.sourceReleases.contains { $0.sourceReleaseID == candidate.candidate.sourceReleaseID }
                    })
                    rows.append(Row(id: scenario.id, query: scenario.query, source: source,
                        records: candidates.map { $0.candidate.recordID.value }, names: candidates.map { $0.name.value },
                        sourceIDs: candidates.map { $0.candidate.sourceReleaseID.value }, candidates: candidates,
                        releases: route.confirmation.sourceReleases,
                        notes: candidates.map { FoodQueryCandidateAssessment.note(query: request.parsedQuery, candidate: $0) }, suggestions: []))
                case let .noResult(route):
                    XCTAssertEqual(route.evidence.originalPayload, .text(request.text))
                    rows.append(Row(id: scenario.id, query: scenario.query, source: source, records: [], names: [],
                        sourceIDs: [], candidates: [], releases: [], notes: [], suggestions: route.suggestedQueries))
                }
            }
        }
        if let output = ProcessInfo.processInfo.environment["WHR_RETRIEVAL_REPORT"] {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rows).write(to: URL(fileURLWithPath: output))
        }
    }
}
private final class ReplayIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 1
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        defer { value += 1 }
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
