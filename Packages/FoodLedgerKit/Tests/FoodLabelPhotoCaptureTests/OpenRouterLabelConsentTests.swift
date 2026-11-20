import FoodLabelPhotoCapture
import FoodLedgerApplication
import FoodLedgerTestSupport
import Foundation
import XCTest

/// docs/openrouter-single-consent-v1-amendment.md O1.2 and O1.6 tests 1 and 2 for the label photo
/// and pasted label text adapters: with the gate refusing, nothing reaches the transport, each
/// adapter returns its named refusal, and each site names its use. Synthetic data only.
final class OpenRouterLabelConsentTests: XCTestCase {
    typealias Photo = OpenRouterLabelPhotoRouteTests
    typealias Text = OpenRouterPastedLabelAITextRouteTests

    func testARefusedPhotoAttemptSendsNothing() async throws {
        let transport = Photo.FakeTransport([.success(Photo.reply(Photo.answer()))])
        let egress = RecordingOpenRouterEgress(permits: false)
        let attempt = OpenRouterLabelPhotoAttempt(egress: egress, transport: transport, keys: Photo.Keys(Photo.key),
                                                  request: try OpenRouterLabelPhotoRequest())
        let result = await attempt.attempt(Photo().image, timeout: 45)
        XCTAssertEqual(result, .notSent(.notPermitted))
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(egress.uses, [.labelPhotoRead])
    }

    func testARefusedPhotoCatalogueCheckSendsNothingOnBothFetches() async throws {
        let transport = Photo.FakeTransport([])
        let egress = RecordingOpenRouterEgress(permits: false)
        do {
            _ = try await OpenRouterLabelRouteChecker(egress: egress, transport: transport, clock: Photo.Clock()).check(LabelPhotoRoute.current)
            XCTFail("Expected a refusal")
        } catch { XCTAssertEqual(error as? LabelPhotoRouteCheckFailure, .notPermitted) }
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(egress.uses, [.labelPhotoCatalogueCheck])
        // Refused on the second fetch only: one listing request, then nothing.
        let second = Photo.FakeTransport([.success(Photo.reply(Photo.listing))])
        let late = RecordingOpenRouterEgress(permits: true, then: [false])
        do { _ = try await OpenRouterLabelRouteChecker(egress: late, transport: second, clock: Photo.Clock()).check(LabelPhotoRoute.current); XCTFail() }
        catch { XCTAssertEqual(error as? LabelPhotoRouteCheckFailure, .notPermitted) }
        XCTAssertEqual(second.sent.count, 1)
        XCTAssertEqual(late.uses, [.labelPhotoCatalogueCheck, .labelPhotoCatalogueCheck])
    }

    func testTheTextCheckerUsesItsOwnUseAndSendsNothingWhenRefused() async throws {
        let route = Text.route
        for refusedAsk in [1, 2] {
            let transport = Photo.FakeTransport([.success(Photo.reply(Photo.listing))])
            let egress = refusedAsk == 1 ? RecordingOpenRouterEgress(permits: false) : RecordingOpenRouterEgress(permits: true, then: [false])
            do {
                _ = try await OpenRouterPastedLabelAITextRouteChecker(egress: egress, transport: transport, clock: Photo.Clock()).check(route)
                XCTFail("Expected a refusal")
            } catch { XCTAssertEqual(error as? OpenRouterPastedLabelAITextRouteChecker.CheckError, .notPermitted) }
            XCTAssertEqual(transport.sent.count, refusedAsk - 1, "zero transport calls on the refused fetch")
            XCTAssertEqual(egress.uses, Array(repeating: .pastedLabelTextCatalogueCheck, count: refusedAsk), "never the photo use")
        }
    }

    func testARefusedTextAttemptPassesTheRefusalContract() async throws {
        let route = Text.route
        let transport = Text.CountingTransport(body: Data())
        let egress = RecordingOpenRouterEgress(permits: false)
        let attempt = OpenRouterPastedLabelAITextAttempt(egress: egress, transport: transport, keys: Photo.Keys(Photo.key),
                                                         request: try OpenRouterPastedLabelAITextRequest(route: route))
        let violations = await PastedLabelAITextPortContracts.refusing(attempt, sends: { transport.sends })
        XCTAssertEqual(violations, [])
        XCTAssertEqual(egress.uses, [.pastedLabelTextRead])
    }

    func testTheNewNotSentCaseRoundTrips() throws {
        XCTAssertEqual(PastedLabelAITextNotSent.notPermitted.rawValue, "not_permitted")
        let encoded = try JSONEncoder().encode(PastedLabelAITextNotSent.notPermitted)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #""not_permitted""#)
        XCTAssertEqual(try JSONDecoder().decode(PastedLabelAITextNotSent.self, from: encoded), .notPermitted)
    }

    /// The app's rule: uses not in force are never permitted, even with the switch on.
    func testUsesNotInForceAreTheTwoPastedTextUses() {
        XCTAssertEqual(OpenRouterUse.allCases.filter { !$0.isInForce }, [.pastedLabelTextRead, .pastedLabelTextCatalogueCheck])
    }
}
