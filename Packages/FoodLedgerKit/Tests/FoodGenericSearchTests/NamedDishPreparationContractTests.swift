import Foundation
import XCTest
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

final class NamedDishPreparationContractTests: XCTestCase {
    private func request(_ text: String, basis: ResolutionBasis? = nil) throws -> GenericFoodSearchRequest {
        try GenericFoodSearchRequest(text: LedgerText(text), identity: .init(servingBasis: basis), capturedAt: Date(timeIntervalSince1970: 0), locale: LedgerText("en_GB"))
    }
    func testBundledAdaptersShareOrdinaryAndMethodBoundaries() throws {
        let sources: [any GenericFoodSearching] = [try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), try USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())]
        for source in sources {
            for query in ["100g cooked milk powder", "200g boiled porridge made with water"] {
                guard case .noResult = try source.search(request(query)) else { return XCTFail(query) }
            }
            if case let .confirmation(route) = try source.search(request("175g raw quinoa")) {
                XCTAssertTrue(route.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == .raw })
            }
            guard case .noResult = try source.search(request("200g cooked porridge made with water", basis: .per100Millilitres)) else { return XCTFail("Preparation exception must not relax basis") }
        }
    }
    func testNamedDishSourceUnknownKeepsItsFactsAndCannotBecomeSufficient() throws {
        let source = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator())
        guard case let .confirmation(before) = try source.search(request("200g porridge made with water")),
              case let .confirmation(after) = try source.search(request("200g cooked porridge made with water")) else { return XCTFail() }
        XCTAssertEqual(before.matches.count, after.matches.count)
        for match in after.matches {
            let old = try XCTUnwrap(before.matches.first { $0.candidate.candidate.recordID == match.candidate.candidate.recordID })
            XCTAssertEqual(old.candidate.candidate.identity, match.candidate.candidate.identity)
            XCTAssertEqual(old.candidate.candidate.nutrients, match.candidate.candidate.nutrients)
            XCTAssertEqual(old.candidate.candidate.sourceReleaseID, match.candidate.candidate.sourceReleaseID)
            XCTAssertEqual(match.candidate.candidate.identity.preparation.kind, .unknown)
            XCTAssertTrue(FoodQueryCandidateAssessment.note(query: FoodQueryParser.parse("200g cooked porridge made with water"), candidate: match.candidate)?.contains("not established") == true)
        }
        let coverage = try ConservativeFoodSearchCoverageAssessment().assess(.confirmation(after), for: request("200g cooked porridge made with water"))
        XCTAssertTrue(coverage.allSatisfy { $0.match == .uncertain && $0.basis == .unknown && $0.quantity == .needsUserInput })
        XCTAssertNil(after.reuse)
        XCTAssertEqual(FoodConfirmationState(input: after.confirmation).decision, .undecided)
    }
    func testKnownPreparationStaysAheadOfUnverifiedAlternativesAcrossSources() throws {
        let local = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator()), USDAGenericFoodSearch(ids: RandomLedgerIDGenerator())], ids: RandomLedgerIDGenerator())
        guard case let .confirmation(route) = try local.search(request("200g cooked porridge made with milk")) else { return XCTFail() }
        XCTAssertEqual(route.matches.first?.candidate.candidate.identity.preparation.kind, .cooked)
        XCTAssertTrue(route.matches.dropFirst().contains { $0.candidate.candidate.identity.preparation.kind == .unknown })
        XCTAssertNil(route.reuse)
    }
}
