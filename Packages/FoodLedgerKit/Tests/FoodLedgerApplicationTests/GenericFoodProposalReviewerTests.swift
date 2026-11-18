import Foundation
@testable import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

@MainActor
final class GenericFoodProposalReviewerTests: XCTestCase {
    private let key = "synthetic-provider-key-123456789"
    private let url = URL(string: "https://publisher.example/tofu")!

    func testSingleEmptySourceRetainsExtractionOutcomeWithoutExtraProviderCalls() async throws {
        let ports = ReviewPorts(empty: true, leadURLs: [url])
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        XCTAssertTrue(result.validation.candidates.isEmpty)
        XCTAssertEqual(result.sourceAttempts, [url])
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract"])
    }

    func testSingleUnreadableSourceRetainsItsAcquisitionReason() async throws {
        let ports = ReviewPorts(captureError: .unsupportedContent, leadURLs: [url])
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected unreadable source") }
        catch let failure as GenericFoodProposalPartialFailure {
            guard case .acquisition(.unsupportedContent) = failure.reason else { return XCTFail("Original reason was replaced") }
            XCTAssertEqual(failure.sourceAttempts, [url])
        }
    }

    func testUnreadableSourcesStopAtTwoAndPreserveFailedAttemptURLs() async throws {
        let ports = ReviewPorts(captureError: .unsupportedContent)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected unreadable sources") }
        catch let failure as GenericFoodProposalPartialFailure {
            XCTAssertEqual(failure.sourceAttempts.map(\.host), ["publisher.example", "other.example"])
            XCTAssertEqual(failure.discovery?.leads.count, 2)
        }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "chooseSource", "capture"])
    }

    func testSuppliedURLNeverAutomaticallyTriesAnotherSource() async throws {
        let ports = ReviewPorts(empty: true)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        let result = try await service.review(foodTerms: "tofu", sourceURL: url, key: key)
        XCTAssertEqual(result.sourceAttempts, [url])
        let calls = await ports.calls
        XCTAssertEqual(calls, ["capture", "extract"])
    }

    func testApplicabilityAbstentionDoesNotSearchUntilItFindsAPassingSource() async throws {
        let ports = ReviewPorts(selectionChoice: "none")
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
            sourceSelection: ports, selection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        XCTAssertEqual(result.suggestedChoice, "none")
        XCTAssertEqual(result.sourceAttempts.count, 1)
        let calls = await ports.calls
        XCTAssertEqual(calls.filter { $0 == "chooseSource" }.count, 1)
    }

    // #508 phase 1: a first lead between the old and new bounds is no longer refused as too
    // large, so it is reviewed and the second lead is never captured.
    func testFirstLeadBetweenOldAndNewBoundsIsReviewedWithoutASecondCapture() async throws {
        let ports = ReviewPorts(extraBlocks: 700)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
            sourceSelection: ports, selection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract", "select"])
        XCTAssertEqual(result.sourceAttempts.map(\.host), ["publisher.example"])
        XCTAssertEqual(result.documents.first?.blocks.count, 701)
        XCTAssertFalse(try XCTUnwrap(result.documents.first).fits(.reviewManifestV1V2))
        XCTAssertEqual(result.suggestedChoice, "c1")
    }

    // #508 phase 2 (contract test 16): a page whose candidates conflict gets the applicability
    // check, which was skipped before, and its answer is recorded and drives the offer.
    func testCompetingPanelsGetTheCheckAndItsAnswerIsRecorded() async throws {
        for (choice, offered, preselected) in [("c1", ["c1", "c2"], "c1" as String?), ("clarify", ["c1", "c2"], nil)] {
            let ports = ReviewPorts(selectionChoice: choice, competingPanels: true)
            let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
                sourceSelection: ports, selection: ports)
            let result = try await service.review(foodTerms: "tofu", sourceURL: url, key: key)
            let calls = await ports.calls
            XCTAssertEqual(calls, ["capture", "extract", "select"], choice)
            XCTAssertTrue(result.validation.candidates.allSatisfy { $0.status == .conflictingCandidates && $0.choosable }, choice)
            XCTAssertEqual(result.selection?.choice, choice)
            XCTAssertEqual(result.offer.candidates.map(\.id), offered, choice)
            XCTAssertEqual(result.offer.preselectedID, preselected, choice)
        }
    }

    // MARK: #508 phase 3, contract tests 18 and 19

    func testReviewPortsPassTheSharedCapturePortContract() async {
        let violations = await FoodDocumentCapturePortContracts.violations { shape in
            let address = URL(string: "https://publisher.example/tofu")!
            return (ReviewPorts(pageShapes: [address: shape]), address)
        }
        XCTAssertEqual(violations, [])
    }

    func testSuppliedAddressAndRunWithoutSelectorMayReadInPart() async throws {
        let supplied = ReviewPorts(pageShapes: [url: .overBoundsWithPanel])
        let result = try await reviewer(supplied, ranking: false).review(foodTerms: "tofu", sourceURL: url, key: key)
        XCTAssertNotNil(result.documents.first?.partialRead)
        let permissions = await supplied.permissions
        XCTAssertEqual(permissions, [.permitted])
        let unselected = ReviewPorts(pageShapes: [url: .overBoundsWithPanel])
        let run = try await GenericFoodProposalReviewer(discovery: unselected, capture: unselected, extraction: unselected)
            .review(foodTerms: "tofu", key: key)
        XCTAssertNotNil(run.documents.first?.partialRead)
        let unselectedPermissions = await unselected.permissions, calls = await unselected.calls
        XCTAssertEqual(unselectedPermissions, [.permitted])
        XCTAssertEqual(calls.filter { $0 == "capture" }.count, 1)
    }

    func testAFirstLeadOverTheBoundsYieldsToAnotherLeadAndIsReadInPartOnlyWithoutOne() async throws {
        let other = URL(string: "https://other.example/tofu")!
        let ports = ReviewPorts(pageShapes: [url: .overBoundsWithPanel])
        let result = try await GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports,
            selection: ports).review(foodTerms: "tofu", key: key)
        let permissions = await ports.permissions
        XCTAssertEqual(permissions, [.refused, .permitted])
        XCTAssertEqual(result.sourceAttempts, [url, other])
        XCTAssertNil(result.documents.first?.partialRead)
        // With no other admissible lead, the first capture may read in part: one capture.
        let alone = ReviewPorts(leadURLs: [url], pageShapes: [url: .overBoundsWithPanel])
        let single = try await GenericFoodProposalReviewer(discovery: alone, capture: alone, extraction: alone, sourceSelection: alone,
            selection: alone).review(foodTerms: "tofu", key: key)
        let alonePermissions = await alone.permissions
        XCTAssertEqual(alonePermissions, [.permitted])
        XCTAssertNotNil(single.documents.first?.partialRead)
        XCTAssertEqual(single.sourceAttempts, [url])
        // A lead the link policy refuses is not another admissible lead.
        XCTAssertFalse(GenericFoodProposalReviewer.hasAnotherAdmissibleLead(.init(leads: [.init(title: "Tofu", url: url),
            .init(title: "Tofu", url: URL(string: "http://other.example/tofu")!)], searchSuggestionsHTML: nil), besides: url))
        XCTAssertTrue(GenericFoodProposalReviewer.hasAnotherAdmissibleLead(.init(leads: [.init(title: "Tofu", url: url),
            .init(title: "Tofu", url: other)], searchSuggestionsHTML: nil), besides: url))
    }

    func testNoWayBackWhenTheSecondLeadIsNotCaptured() async throws {
        // The selector abstains, the second lead has a provider error, or a market conflict: the run
        // ends as today (the second attempt's reason), and the first page is never read in part.
        let abstains = ReviewPorts(pageShapes: [url: .overBoundsWithPanel])
        await abstains.secondChoice(.abstain(reason: "None suits"))
        let provider = ReviewPorts(pageShapes: [url: .overBoundsWithPanel])
        await provider.secondChoice(error: .quotaExceeded)
        for (ports, expected) in [(abstains, "sourceNotSuggested"), (provider, "provider")] {
            let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
            do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected the run to end") }
            catch let failure as GenericFoodProposalPartialFailure {
                switch failure.reason {
                case .sourceNotSuggested: XCTAssertEqual(expected, "sourceNotSuggested")
                case .provider: XCTAssertEqual(expected, "provider")
                default: XCTFail("Unexpected reason \(failure.reason)")
                }
                XCTAssertEqual(failure.sourceAttempts, [url])
            }
            let permissions = await ports.permissions
            XCTAssertEqual(permissions, [.refused])
        }
        let first = URL(string: "https://publisher.co.uk/yoghurt")!
        let market = ReviewPorts(leadURLs: [first, URL(string: "https://ie.fage/yoghurts/fage-total-0")!],
                                 pageShapes: [first: .overBoundsWithPanel])
        let service = GenericFoodProposalReviewer(discovery: market, capture: market, extraction: market, sourceSelection: market)
        do { _ = try await service.review(foodTerms: "FAGE plain yoghurt UK", key: key); XCTFail("Expected market conflict") }
        catch let failure as GenericFoodProposalPartialFailure {
            guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong failure reason") }
            XCTAssertEqual(failure.sourceAttempts, [first])
        }
        let marketPermissions = await market.permissions
        XCTAssertEqual(marketPermissions, [.refused])
    }

    func testAnEmptyFirstExtractionThenASecondPageOverTheBoundsReadsItInPart() async throws {
        let other = URL(string: "https://other.example/tofu")!
        let ports = ReviewPorts(emptyFirstOnly: true, pageShapes: [other: .overBoundsWithPanel])
        let result = try await GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports,
            selection: ports).review(foodTerms: "tofu", key: key)
        let permissions = await ports.permissions, calls = await ports.calls
        XCTAssertEqual(permissions, [.refused, .permitted])
        XCTAssertNotNil(result.documents.first?.partialRead)
        XCTAssertEqual(calls.filter { $0 == "capture" }.count, 2, "Never more than two captures")
    }

    func testEmptyFirstSourceUsesOneDistinctAlternativeWithoutRediscovery() async throws {
        let ports = ReviewPorts(emptyFirstOnly: true)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
            sourceSelection: ports, selection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract", "chooseSource", "capture", "extract", "select"])
        XCTAssertEqual(result.sourceAttempts.map(\.host), ["publisher.example", "other.example"])
        XCTAssertEqual(result.discovery?.leads.count, 2)
        XCTAssertEqual(result.documents.count, 1, "Distinct source panels must not be merged")
        XCTAssertEqual(result.documents.first?.url, "https://other.example/tofu")
    }

    func testEmptyAlternativeStopsAtTwoSourcesAndNoApplicability() async throws {
        let ports = ReviewPorts(empty: true)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
            sourceSelection: ports, selection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        XCTAssertEqual(result.sourceAttempts.count, 2)
        XCTAssertTrue(result.validation.candidates.isEmpty)
        let calls = await ports.calls
        XCTAssertEqual(calls.filter { $0 == "capture" }.count, 2)
        XCTAssertFalse(calls.contains("select"))
    }

    func testProviderFailureDoesNotSpendOnAlternativeSource() async throws {
        let ports = ReviewPorts(extractionError: .quotaExceeded)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected quota failure") } catch {}
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract"])
    }

    func testRepresentativeLeadRetainsRestrictedScope() async throws {
        let ports = ReviewPorts(sourceChoice: .selected(index: 0, purpose: .representativeEstimate, reason: "representative_food_lead"))
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        XCTAssertTrue(result.representativeSourceOnly)
    }

    func testSelectedWrongMarketStopsBeforeCaptureAndPreservesEveryLead() async throws {
        for useSelector in [true, false] {
            let urls = [URL(string: "https://ie.fage/yoghurts/fage-total-0")!, URL(string: "https://publisher.co.uk/yoghurt")!]
            let ports = ReviewPorts(leadURLs: urls)
            let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
                sourceSelection: useSelector ? ports : nil)
            do { _ = try await service.review(foodTerms: "FAGE plain yoghurt UK", key: key); XCTFail("Expected market conflict") }
            catch let failure as GenericFoodProposalPartialFailure {
                guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong failure reason") }
                XCTAssertEqual(failure.discovery?.leads.map(\.url), urls)
                XCTAssertNil(failure.attemptedSourceURL)
            }
            let calls = await ports.calls
            XCTAssertEqual(calls, useSelector ? ["discover", "chooseSource"] : ["discover"])
        }
    }

    func testSuppliedWrongMarketHasNoDiscoveryCaptureOrProviderCall() async throws {
        let ports = ReviewPorts()
        let service = reviewer(ports)
        do {
            _ = try await service.review(foodTerms: "UK yoghurt", sourceURL: URL(string: "https://ie.fage/yoghurt")!, key: key)
            XCTFail("Expected market conflict")
        } catch let failure as GenericFoodProposalPartialFailure {
            guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong failure reason") }
            XCTAssertNil(failure.discovery); XCTAssertNil(failure.attemptedSourceURL)
        }
        let calls = await ports.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testRedirectedWrongMarketStopsBeforeExtractionAndRetainsAttemptedURL() async throws {
        let ports = ReviewPorts(capturedURL: URL(string: "https://ie.fage/yoghurt")!)
        let service = reviewer(ports)
        do {
            _ = try await service.review(foodTerms: "UK yoghurt", sourceURL: url, key: key)
            XCTFail("Expected redirected market conflict")
        } catch let failure as GenericFoodProposalPartialFailure {
            guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong failure reason") }
            XCTAssertEqual(failure.attemptedSourceURL, url)
        }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["capture"])
    }

    func testSourceSelectionChoosesOnlyAnOfferedLeadBeforeCapture() async throws {
        let ports = ReviewPorts(sourceChoice: .selected(index: 1, purpose: .primaryProduct, reason: "Exact source"))
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        let result = try await service.review(foodTerms: "tofu", key: key)
        XCTAssertEqual(result.attemptedSourceURL?.host, "other.example")
        XCTAssertEqual(result.documents.first?.url, "https://other.example/tofu")
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract"])
    }

    func testSourceAbstentionInvalidIndexAndFailurePreserveLeadsWithoutCapture() async throws {
        for ports in [ReviewPorts(sourceChoice: .abstain(reason: "Wrong market")),
                      ReviewPorts(sourceChoice: .selected(index: 2, purpose: .primaryProduct, reason: "Invented choice")),
                      ReviewPorts(sourceChoice: .selected(index: -1, purpose: .primaryProduct, reason: "Invalid choice")),
                      ReviewPorts(sourceError: .quotaExceeded)] {
            let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
            do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected closed source choice") }
            catch let failure as GenericFoodProposalPartialFailure {
                XCTAssertEqual(failure.discovery?.leads.count, 2)
                XCTAssertNil(failure.attemptedSourceURL)
            }
            let calls = await ports.calls
            XCTAssertEqual(calls, ["discover", "chooseSource"])
        }
    }

    func testSuppliedURLSkipsSourceSelectionAndRejectedKeyRemainsDistinct() async throws {
        let ports = ReviewPorts(sourceError: .credentialRejected)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports, sourceSelection: ports)
        do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected key rejection") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .credentialRejected) }
        let result = try await service.review(foodTerms: "tofu", sourceURL: url, key: key)
        XCTAssertNil(result.discovery)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource", "capture", "extract"])
    }

    func testDeadlineDuringSourceChoicePreventsCapture() async throws {
        let ports = ReviewPorts(suspendSourceChoice: true)
        let service = GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
            sourceSelection: ports, timeout: .milliseconds(30))
        do { _ = try await service.review(foodTerms: "tofu", key: key); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .timedOut) }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "chooseSource"])
    }

    func testDiscoveryCaptureExtractionAndRankingEachRunOnce() async throws {
        let ports = ReviewPorts()
        let result = try await reviewer(ports).review(foodTerms: "  tofu  ", key: key)
        XCTAssertEqual(result.foodTerms, "tofu")
        XCTAssertEqual(result.discovery?.leads.count, 2)
        XCTAssertEqual(result.selection?.choice, "c1")
        XCTAssertFalse(result.rankingUnavailable)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture", "extract", "select"])
    }

    func testSuppliedURLSkipsDiscoveryAndOptionalSelectorCanBeOmitted() async throws {
        let ports = ReviewPorts()
        let result = try await reviewer(ports, ranking: false).review(foodTerms: "tofu", sourceURL: url, key: key)
        XCTAssertNil(result.discovery); XCTAssertNil(result.selection)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["capture", "extract"])
    }

    func testNoCandidateSkipsRankingRatherThanSelectingAnInventedCandidate() async throws {
        let ports = ReviewPorts(empty: true)
        let result = try await reviewer(ports).review(foodTerms: "tofu", key: key)
        XCTAssertTrue(result.validation.candidates.isEmpty)
        XCTAssertNil(result.selection); XCTAssertFalse(result.rankingUnavailable)
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture", "extract"])
    }

    func testCaptureFailureRetainsEveryDiscoveredLinkAndDoesNotRetry() async throws {
        let ports = ReviewPorts(captureError: .unsupportedContent)
        do { _ = try await reviewer(ports).review(foodTerms: "tofu", key: key); XCTFail("Expected failure") }
        catch let failure as GenericFoodProposalPartialFailure {
            XCTAssertEqual(failure.discovery?.leads.count, 2)
            guard case .acquisition(.unsupportedContent) = failure.reason else { return XCTFail("Wrong stage") }
        }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture"])
    }

    func testExtractionQuotaFailureRetainsLinksAndNeverCallsSelector() async throws {
        let ports = ReviewPorts(extractionError: .quotaExceeded)
        do { _ = try await reviewer(ports).review(foodTerms: "tofu", key: key); XCTFail("Expected failure") }
        catch let failure as GenericFoodProposalPartialFailure {
            XCTAssertEqual(failure.discovery?.leads.count, 2)
            guard case .provider(.quotaExceeded) = failure.reason else { return XCTFail("Wrong stage") }
        }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture", "extract"])
    }

    func testApplicabilityFailurePreservesInspectableProposalButBlocksConfirmation() async throws {
        let ports = ReviewPorts(selectionError: .serviceUnavailable)
        let result = try await reviewer(ports).review(foodTerms: "tofu", key: key)
        XCTAssertEqual(result.validation.candidates.filter(\.selectionEligible).count, 1)
        XCTAssertNil(result.selection); XCTAssertTrue(result.rankingUnavailable)
        XCTAssertEqual(result.selectionFailure, .serverError)
        XCTAssertEqual(result.suggestedChoice, "clarify")
        XCTAssertFalse(result.permitsConfirmation(of: try XCTUnwrap(result.validation.candidates.first)))
    }

    func testApplicabilityFailureRecordsItsKind() async throws {
        let cases: [(FoodWebDiscoveryError, FoodProposalSelectionFailure)] = [
            (.connectionFailed, .transport), (.timedOut, .timedOut), (.quotaExceeded, .rateLimited),
            (.serviceUnavailable, .serverError), (.invalidResponse, .invalidResponse),
            (.requestRejected, .requestRejected), (.permissionDenied, .requestRejected)]
        for (error, expected) in cases {
            let result = try await reviewer(ReviewPorts(selectionError: error)).review(foodTerms: "tofu", key: key)
            XCTAssertEqual(result.selectionFailure, expected, "\(error)")
            XCTAssertTrue(result.rankingUnavailable)
            XCTAssertNil(result.selection)
        }
    }

    func testOutOfSetApplicabilityChoiceIsRecordedAsChoiceNotOffered() async throws {
        let result = try await reviewer(ReviewPorts(selectionChoice: "c9")).review(foodTerms: "tofu", key: key)
        XCTAssertEqual(result.selectionFailure, .choiceNotOffered)
        XCTAssertNil(result.selection)
        XCTAssertFalse(result.permitsConfirmation(of: try XCTUnwrap(result.validation.candidates.first)))
    }

    func testSuccessfulApplicabilityRecordsNoFailure() async throws {
        let result = try await reviewer(ReviewPorts()).review(foodTerms: "tofu", key: key)
        XCTAssertNil(result.selectionFailure)
        XCTAssertFalse(result.rankingUnavailable)
    }

    func testCredentialRejectionRemainsDistinctAtExtractionAndSelection() async throws {
        for ports in [ReviewPorts(extractionError: .credentialRejected), ReviewPorts(selectionError: .credentialRejected)] {
            do { _ = try await reviewer(ports).review(foodTerms: "tofu", key: key); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .credentialRejected) }
        }
    }

    func testConcurrentReviewIsRejectedAndCancellationPreventsLaterProviderCalls() async throws {
        let ports = ReviewPorts(suspendCapture: true)
        let service = reviewer(ports)
        let pending = Task { try await service.review(foodTerms: "tofu", key: key) }
        try await waitForCapture(ports)
        do { _ = try await service.review(foodTerms: "rice", key: key); XCTFail("Expected concurrency guard") }
        catch { XCTAssertEqual(error as? GenericFoodProposalReviewError, .alreadyRunning) }
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture"])
        // A cancelled attempt releases the concurrency guard for a later explicit tap.
        await ports.resumeCapture()
        _ = try await service.review(foodTerms: "tofu", key: key)
    }

    func testOverallDeadlineCancelsAcquisitionBeforeProviderCalls() async throws {
        let ports = ReviewPorts(suspendCapture: true)
        do {
            _ = try await reviewer(ports, timeout: .milliseconds(30)).review(foodTerms: "tofu", key: key)
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .timedOut) }
        let calls = await ports.calls
        XCTAssertEqual(calls, ["discover", "capture"])
    }

    func testKeyEchoAndInvalidSourceAreRejectedBeforeAnyPortCall() async throws {
        let ports = ReviewPorts()
        let service = reviewer(ports)
        for (terms, source) in [(key, url), ("tofu", URL(string: "http://publisher.example/tofu")!)] {
            do { _ = try await service.review(foodTerms: terms, sourceURL: source, key: key); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? FoodWebDiscoveryError, .invalidQuery) }
        }
        let calls = await ports.calls
        XCTAssertTrue(calls.isEmpty)
    }

    private func reviewer(_ ports: ReviewPorts, ranking: Bool = true, timeout: Duration = .seconds(2)) -> GenericFoodProposalReviewer {
        GenericFoodProposalReviewer(discovery: ports, capture: ports, extraction: ports,
                                    selection: ranking ? ports : nil, timeout: timeout)
    }

    private func waitForCapture(_ ports: ReviewPorts) async throws {
        for _ in 0..<1000 {
            if await ports.calls.contains("capture") { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Capture did not begin")
    }
}

private actor ReviewPorts: FoodWebDiscovering, FoodDocumentCapturing, FoodProposalExtracting, FoodProposalSelecting, FoodSourceLeadSelecting {
    var calls: [String] = []
    let empty: Bool
    let emptyFirstOnly: Bool
    var extractionCount = 0
    let captureError: FoodSourceAcquisitionError?
    let extractionError: FoodWebDiscoveryError?
    let selectionError: FoodWebDiscoveryError?
    let selectionChoice: String
    var suspendCapture: Bool
    let sourceChoice: FoodSourceLeadDecision
    let sourceError: FoodWebDiscoveryError?
    let suspendSourceChoice: Bool
    let leadURLs: [URL]
    let capturedURL: URL?
    let extraBlocks: Int
    let competingPanels: Bool
    /// Scripted page shapes by address (#508 phase 3); any other address is a whole page.
    let pageShapes: [URL: FoodDocumentCapturePortContracts.PageShape]
    /// The part-read permission of every capture, in order.
    var permissions: [FoodDocumentPartReadPermission] = []
    /// A different answer from the second source choice, when set (#508 phase 3 source order).
    var secondSourceChoice: FoodSourceLeadDecision?
    var secondSourceError: FoodWebDiscoveryError?
    private var sourceChoices = 0
    init(empty: Bool = false, emptyFirstOnly: Bool = false, captureError: FoodSourceAcquisitionError? = nil,
         extractionError: FoodWebDiscoveryError? = nil, selectionError: FoodWebDiscoveryError? = nil, selectionChoice: String = "c1",
         suspendCapture: Bool = false, sourceChoice: FoodSourceLeadDecision = .selected(index: 0, purpose: .primaryProduct, reason: "Source"),
         sourceError: FoodWebDiscoveryError? = nil, suspendSourceChoice: Bool = false,
         leadURLs: [URL] = [URL(string: "https://publisher.example/tofu")!, URL(string: "https://other.example/tofu")!],
         capturedURL: URL? = nil, extraBlocks: Int = 0, competingPanels: Bool = false,
         pageShapes: [URL: FoodDocumentCapturePortContracts.PageShape] = [:]) {
        self.empty = empty; self.emptyFirstOnly = emptyFirstOnly; self.captureError = captureError; self.extractionError = extractionError
        self.selectionError = selectionError; self.selectionChoice = selectionChoice; self.suspendCapture = suspendCapture
        self.sourceChoice = sourceChoice; self.sourceError = sourceError; self.suspendSourceChoice = suspendSourceChoice
        self.leadURLs = leadURLs; self.capturedURL = capturedURL; self.extraBlocks = extraBlocks
        self.competingPanels = competingPanels; self.pageShapes = pageShapes
    }
    func chooseSource(foodTerms: String, leads: [FoodWebLead], key: String) async throws -> FoodSourceLeadDecision {
        calls.append("chooseSource"); sourceChoices += 1
        if suspendSourceChoice { try await Task.sleep(for: .seconds(30)) }
        if let sourceError { throw sourceError }
        if sourceChoices == 2, let secondSourceError { throw secondSourceError }
        if sourceChoices == 2, let secondSourceChoice { return secondSourceChoice }
        return sourceChoice
    }
    func resumeCapture() { suspendCapture = false }
    func secondChoice(_ choice: FoodSourceLeadDecision? = nil, error: FoodWebDiscoveryError? = nil) {
        secondSourceChoice = choice; secondSourceError = error
    }
    func validate(key: String) async throws { XCTFail("Review must not add a validation request") }
    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult {
        calls.append("discover")
        return .init(leads: leadURLs.map { .init(title: "Tofu source", url: $0) }, searchSuggestionsHTML: nil)
    }
    func capture(_ url: URL, partRead: FoodDocumentPartReadPermission) async throws -> CapturedFoodDocument {
        calls.append("capture"); permissions.append(partRead)
        if suspendCapture { try await Task.sleep(for: .seconds(30)) }
        if let captureError { throw captureError }
        let blocks: [FoodDocumentBlock] = [.init(id: "b1", kind: "text", text: "Tofu Per 100 g Protein 6 g", locator: "line1")]
            + (competingPanels ? [.init(id: "b2", kind: "text", text: "Tofu Per 100 g Protein 7 g", locator: "line2")] : [])
            + (0..<extraBlocks).map { .init(id: "b\($0 + 2)", kind: "li", text: "Menu item \($0)", locator: "li\($0)") }
        switch pageShapes[url] ?? .whole {
        case .whole: break
        case .overBoundsWithoutPanel: throw FoodSourceAcquisitionError.responseTooLarge
        case .overBoundsWithPanel:
            guard partRead == .permitted else { throw FoodSourceAcquisitionError.responseTooLarge }
            return try FoodDocumentCapturePortContracts.partReadDocument(id: "d1", url: capturedURL ?? url, blocks: blocks)
        }
        return try CapturedFoodDocument(id: "d1", url: (capturedURL ?? url).absoluteString, rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic_fixture", retrievedAt: "2026-10-04T00:00:00Z", blocks: blocks)
    }
    func extract(foodTerms: String, documents: [CapturedFoodDocument], key: String) async throws -> FoodProposalExtraction {
        calls.append("extract")
        if let extractionError { throw extractionError }
        extractionCount += 1
        if empty || (emptyFirstOnly && extractionCount == 1) { return .init(version: FoodProposalExtraction.schemaVersion, candidates: [], preferredId: "none") }
        let reference: [[String: Any]] = [["block_id": "b1", "quote": "Tofu Per 100 g Protein 6 g"]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { nutrient in
            let known = nutrient == .protein
            return ["key": nutrient.rawValue, "state": known ? "declared" : "unknown", "value": known ? "6" as Any : NSNull(),
                    "unit": known ? "g" as Any : NSNull(), "evidence": known ? reference : [],
                    "unknown_reason": known ? NSNull() : "not_observed" as Any]
        }
        let candidate: [String: Any] = ["id": "c1", "document_id": "d1", "name": "Tofu", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": reference, "panel_evidence": reference,
            "basis": ["amount": "100", "unit": "g", "label": "Per 100 g", "evidence": reference],
            "nutrients": nutrients, "limitations": []]
        var candidates = [candidate]
        if competingPanels {
            let second: [[String: Any]] = [["block_id": "b2", "quote": "Tofu Per 100 g Protein 7 g"]]
            var other = candidate
            other["id"] = "c2"; other["identity_evidence"] = second; other["panel_evidence"] = second
            other["basis"] = ["amount": "100", "unit": "g", "label": "Per 100 g", "evidence": second]
            other["nutrients"] = FoodProposalNutrientKey.allCases.map { nutrient -> [String: Any] in
                let known = nutrient == .protein
                return ["key": nutrient.rawValue, "state": known ? "declared" : "unknown", "value": known ? "7" as Any : NSNull(),
                        "unit": known ? "g" as Any : NSNull(), "evidence": known ? second : [],
                        "unknown_reason": known ? NSNull() : "not_observed" as Any]
            }
            candidates.append(other)
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject:
            ["version": FoodProposalExtraction.schemaVersion, "candidates": candidates, "preferred_id": "c1"]))
    }
    func select(foodTerms: String, documents: [CapturedFoodDocument], validation: FoodProposalValidation, key: String) async throws -> FoodProposalSelection {
        calls.append("select")
        if let selectionError { throw selectionError }
        if competingPanels { return try .init(unscoredChoice: selectionChoice, validation: validation) }
        return try .init(choice: selectionChoice, probabilities: ["c1": 0.8, "none": 0.1, "clarify": 0.1], rawConfidence: 0.8, validation: validation)
    }
}
