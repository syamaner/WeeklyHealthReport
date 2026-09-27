import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// Same-author synthetic development replay through the actual bundled adapters.
final class RankedRetrievalDevelopmentTests: XCTestCase {
    struct Fixture: Decodable { let version: String; let cases: [Scenario] }
    struct Scenario: Decodable { let id: String; let query: String; let preparation: String? }
    struct Row: Encodable {
        let id: String; let query: String; let source: String
        let records: [String]; let names: [String]; let sourceIDs: [String]
        let candidates: [PopulatedFoodCandidate]; let releases: [SourceRelease]
        let notes: [String?]; let suggestions: [String]
    }
    func testPlainYoghurtAndFatAgreementRankBeforeSourceLimits() throws {
        let ids = ReplayIDs()
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let sources: [any GenericFoodSearching] = [cofid, usda,
            CompositeGenericFoodSearch(sources: [cofid, usda], ids: ids)]
        for search in sources {
            let request = GenericFoodSearchRequest(text: try LedgerText("200g Greek youghurt"),
                capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
            guard case let .confirmation(route) = try search.search(request) else { return XCTFail("Missing yoghurt") }
            XCTAssertTrue(try XCTUnwrap(route.matches.first).candidate.name.value.lowercased().contains("plain"))
            XCTAssertEqual(route.confirmation.evidence.first?.originalPayload, .text(request.text))
        }
        for (search, fat) in [(cofid as any GenericFoodSearching, "10.2"), (usda as any GenericFoodSearching, "5"),
                            (sources[2], "5"), (sources[2], "10.2")] {
            let request = GenericFoodSearchRequest(text: try LedgerText("200g Greek yoghurt \(fat)% fat"),
                capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
            guard case let .confirmation(route) = try search.search(request) else { return XCTFail("Missing yoghurt") }
            let first = try XCTUnwrap(route.matches.first).candidate
            XCTAssertTrue(FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: first))
            XCTAssertEqual(route.confirmation.expectedIdentity, first.candidate.identity)
            XCTAssertEqual(route.confirmation.expectedEdibleQuantity, first.candidate.edibleQuantity)
            XCTAssertTrue(try XCTUnwrap(FoodQueryCandidateAssessment.note(query: request.parsedQuery, candidate: first)).contains("still needs review"))
            for match in route.matches where !FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: match.candidate) {
                XCTAssertTrue(try XCTUnwrap(FoodQueryCandidateAssessment.note(query: request.parsedQuery, candidate: match.candidate)).contains("Alternative:"))
            }
        }
    }

    func testRibeyeSpeciesPreferenceDoesNotOverrideExplicitSpeciesOrPreparation() throws {
        let search = try USDAGenericFoodSearch(ids: ReplayIDs())
        for (text, species) in [("cooked ribeye", "beef"), ("200g cooked rib-eye", "beef"), ("bison ribeye", "game meat")] {
            let request = GenericFoodSearchRequest(text: try LedgerText(text),
                identity: GenericFoodIdentityQuery(preparation: try PreparationState(kind: .cooked)),
                capturedAt: Date(timeIntervalSince1970: 1700000000), locale: try LedgerText("en_GB"))
            guard case let .confirmation(route) = try search.search(request) else { return XCTFail(text) }
            XCTAssertTrue(try XCTUnwrap(route.matches.first).candidate.name.value.lowercased().hasPrefix(species))
            XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .cooked })
            if species == "game meat" { XCTAssertTrue(route.matches.allSatisfy { $0.candidate.name.value.lowercased().contains("bison") }) }
        }
    }

    func testReplay() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Tools/FoodSearchQuality/retrieval-scenarios-v2.json")
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
