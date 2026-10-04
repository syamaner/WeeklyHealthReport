import CryptoKit
import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodGenericSearch
import XCTest

/// Actual retained public responses, replayed through current orchestration with
/// transports that cannot network. This is integration evidence, not new inference.
@MainActor
final class FrozenFoodWorkflowReplayTests: XCTestCase {
    func testHistoricalExtractionRemainsInspectableWithoutConfirmationCheck() async throws {
        guard ProcessInfo.processInfo.environment["FOOD_WORKFLOW_REPLAY"] == "1" else {
            throw XCTSkip("Set FOOD_WORKFLOW_REPLAY=1 to replay retained public workflow evidence")
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let runs = repository.appendingPathComponent("Tools/GenericFoodProposalEvaluation/runs")
        let choices = URL(fileURLWithPath: "/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/lead-selection-v1/run")
        let choicePlan = try verifiedPlan(choices)
        let extractionRoot = runs.appendingPathComponent("workflow-extraction-grok-6-v2")
        let extractionPlan = try verifiedPlan(extractionRoot)
        let extractionCases = try XCTUnwrap(extractionPlan["cases"] as? [[String: Any]])
        let discoveryRoot = runs.appendingPathComponent("workflow-discovery-6-v1")
        _ = try verifiedPlan(discoveryRoot)
        let captureRoot = runs.appendingPathComponent("workflow-first-lead-capture-6-v1")
        _ = try verifiedPlan(captureRoot)
        let cases = try XCTUnwrap(choicePlan["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 6)
        for row in cases {
            let id = try XCTUnwrap(row["id"] as? String)
            guard id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { return XCTFail("Invalid case ID") }
            let query = try XCTUnwrap(row["query"] as? String)
            let expected = try XCTUnwrap(row["expected"] as? [String: Any])
            let abstain = expected["expected_decision"] as? String == "abstain"
            let discoveryFolder = discoveryRoot.appendingPathComponent("results/" + id)
            let discoveryReceipt = try object(discoveryFolder.appendingPathComponent("receipt.json"))
            let discoveryRequest = try data(discoveryFolder.appendingPathComponent("request-1.json"))
            let discoveryResponse = try data(discoveryFolder.appendingPathComponent("response-1.json"))
            try checkReceipt(discoveryReceipt, request: discoveryRequest, response: discoveryResponse)
            let sourceRequest = try data(choices.appendingPathComponent("snapshot/" + id + "-request.json"))
            let sourceResponse = try data(choices.appendingPathComponent("results/" + id + "/response.bin"))
            let sourceReceipt = try object(choices.appendingPathComponent("results/" + id + "/receipt.json"))
            XCTAssertEqual(hash(sourceResponse), sourceReceipt["raw_response_sha256"] as? String)
            var entries = [(discoveryRequest, discoveryResponse), (sourceRequest, sourceResponse)]
            let captureFolder = captureRoot.appendingPathComponent("results/" + id)
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let document = try decoder.decode(CapturedFoodDocument.self, from: data(captureFolder.appendingPathComponent("document.json")))
            let captureReceipt = try object(captureFolder.appendingPathComponent("capture-receipt.json"))
            let responses = try XCTUnwrap(captureReceipt["responses"] as? [[String: Any]])
            let response = try XCTUnwrap(responses.last)
            let bodyName = try XCTUnwrap(response["body_file"] as? String)
            guard bodyName.range(of: "^source-body-[0-9]+\\.bin$", options: .regularExpression) != nil else { return XCTFail("Invalid body path") }
            let raw = try data(captureFolder.appendingPathComponent(bodyName))
            XCTAssertEqual(hash(raw), document.rawSha256)
            let mediaType = try XCTUnwrap(response["media_type"] as? String).components(separatedBy: ";")[0]
            let found = try object(discoveryFolder.appendingPathComponent("discovery.json"))
            let leads = try XCTUnwrap(found["leads"] as? [[String: Any]])
            let firstURL = try XCTUnwrap(URL(string: XCTUnwrap(leads.first?["url"] as? String)))
            let capture = FrozenCapture(document: document, raw: raw, mediaType: mediaType, expectedURL: firstURL)
            let extractionCase = try XCTUnwrap(extractionCases.first { $0["comparison_case"] as? String == id })
            if !abstain {
                let folder = extractionRoot.appendingPathComponent("results/grok-" + id)
                let request = try data(folder.appendingPathComponent("request-1.json"))
                let response = try data(folder.appendingPathComponent("response-1.json"))
                try checkReceipt(object(folder.appendingPathComponent("receipt.json")), request: request, response: response)
                entries.append((request, response))
            }
            let transport = FrozenWorkflowTransport(entries: entries, historicalSystemPrompt: true)
            let provider = OpenRouterFoodProvider(extractionRoute: .grok) { request in try await transport.reply(request) }
            let reviewer = GenericFoodProposalReviewer(discovery: provider, capture: capture, extraction: provider, sourceSelection: provider)
            if abstain {
                do { _ = try await reviewer.review(foodTerms: query, key: "synthetic-replay-key-no-network"); XCTFail("Expected source abstention") }
                catch let failure as GenericFoodProposalPartialFailure {
                    guard case .sourceNotSuggested = failure.reason else { return XCTFail("Wrong failure stage") }
                    XCTAssertNil(failure.attemptedSourceURL)
                    XCTAssertEqual(failure.discovery?.leads.count, 3)
                }
                let captures = await capture.calls; XCTAssertEqual(captures, 0)
            } else {
                let result = try await reviewer.review(foodTerms: query, key: "synthetic-replay-key-no-network")
                let gold = try XCTUnwrap(extractionCase["gold"] as? [String: Any])
                let permitted = result.validation.candidates.filter { result.permitsConfirmation(of: $0) }
                XCTAssertTrue(permitted.isEmpty, "Historical evidence has no applicability check: " + id)
                XCTAssertNil(result.selection)
                let preferred = result.validation.candidates.first {
                    $0.id == result.validation.extractorPreferredId && $0.selectionEligible
                }
                XCTAssertEqual(preferred != nil, gold["outcome"] as? String == "selected", id)
                if let candidate = preferred {
                    XCTAssertTrue(try XCTUnwrap(gold["allowed_names"] as? [String]).contains(candidate.candidate.name), id)
                }
                let captures = await capture.calls; XCTAssertEqual(captures, 1)
            }
            let count = await transport.calls; XCTAssertEqual(count, abstain ? 2 : 3, id)
        }
    }

    func testRetainedLiveWrongMarketChoiceNowStopsBeforeCapture() async throws {
        guard ProcessInfo.processInfo.environment["FOOD_WORKFLOW_REPLAY"] == "1" else {
            throw XCTSkip("Set FOOD_WORKFLOW_REPLAY=1 to replay the retained wrong-market selection")
        }
        let root = URL(fileURLWithPath: "/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/workflow-live-smoke-v1")
        let plan = try verifiedPlan(root)
        let row = try XCTUnwrap((plan["cases"] as? [[String: Any]])?.first { $0["id"] as? String == "fage-total-0" })
        let query = try XCTUnwrap(row["query"] as? String)
        let folder = root.appendingPathComponent("results/fage-total-0")
        let completion = try object(folder.appendingPathComponent("completion-receipt.json"))
        for (name, expected) in try XCTUnwrap(completion["output_hashes"] as? [String: String]) {
            guard !name.contains("/"), !name.contains("..") else { throw FoodWebDiscoveryError.invalidResponse }
            XCTAssertEqual(hash(try data(folder.appendingPathComponent(name))), expected, name)
        }
        let receipt = try object(folder.appendingPathComponent("receipt.json"))
        let requests = try XCTUnwrap(receipt["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 2)
        var entries: [(Data, Data)] = []
        for index in 1...2 {
            let request = try data(folder.appendingPathComponent("request-\(index).json"))
            let response = try data(folder.appendingPathComponent("response-\(index).json"))
            XCTAssertEqual(hash(request), requests[index - 1]["request_sha256"] as? String)
            XCTAssertEqual(hash(response), requests[index - 1]["response_sha256"] as? String)
            entries.append((request, response))
        }
        let transport = FrozenWorkflowTransport(entries: entries, historicalSystemPrompt: true)
        let provider = OpenRouterFoodProvider(extractionRoute: .grok) { request in try await transport.reply(request) }
        let capture = ForbiddenMarketCapture()
        let reviewer = GenericFoodProposalReviewer(discovery: provider, capture: capture, extraction: provider, sourceSelection: provider)
        do {
            _ = try await reviewer.review(foodTerms: query, key: "synthetic-replay-key-no-network")
            XCTFail("The retained Irish source choice must not reach capture")
        } catch let failure as GenericFoodProposalPartialFailure {
            guard case .sourceMarketConflict = failure.reason else { return XCTFail("Wrong repaired failure") }
            XCTAssertNil(failure.attemptedSourceURL)
            XCTAssertEqual(failure.discovery?.leads.count, 3)
        }
        let calls = await transport.calls; XCTAssertEqual(calls, 2)
        let captures = await capture.calls; XCTAssertEqual(captures, 0)
    }

    func testCurrentFourCallWorkflowReplaysWithRequiredApplicabilityCheck() async throws {
        guard ProcessInfo.processInfo.environment["FOOD_WORKFLOW_REPLAY"] == "1" else {
            throw XCTSkip("Set FOOD_WORKFLOW_REPLAY=1 to replay the retained four-call workflow")
        }
        let root = URL(fileURLWithPath: "/Users/sertanyamaner/Documents/ChatGPT/New project/nutrition-structured-proposals-v1/generic-source-v1/repair-20261004-v2")
        let planData = try data(root.appendingPathComponent("workflow-plan.json"))
        XCTAssertEqual(hash(planData), try String(contentsOf: root.appendingPathComponent("workflow-plan.sha256"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let plan = try StrictFoodProposalJSON.object(planData)
        let folder = root.appendingPathComponent("workflow-result")
        let completion = try object(root.appendingPathComponent("workflow-completion.json"))
        for (name, expected) in try XCTUnwrap(completion["output_hashes"] as? [String: String]) {
            guard !name.contains("/"), !name.contains("..") else { throw FoodWebDiscoveryError.invalidResponse }
            XCTAssertEqual(hash(try data(folder.appendingPathComponent(name))), expected, name)
        }
        let receipt = try object(folder.appendingPathComponent("receipt.json"))
        let requests = try XCTUnwrap(receipt["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 4)
        var entries: [(Data, Data)] = []
        for index in 1...4 {
            let request = try data(folder.appendingPathComponent("request-\(index).json"))
            let response = try data(folder.appendingPathComponent("response-\(index).json"))
            XCTAssertEqual(hash(request), requests[index - 1]["request_sha256"] as? String)
            XCTAssertEqual(hash(response), requests[index - 1]["response_sha256"] as? String)
            entries.append((request, response))
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let document = try decoder.decode(CapturedFoodDocument.self, from: data(folder.appendingPathComponent("document.json")))
        let raw = try data(folder.appendingPathComponent("source-body-1.bin"))
        XCTAssertEqual(hash(raw), document.rawSha256)
        let capture = FrozenCapture(document: document, raw: raw, mediaType: "text/html",
            expectedURL: try XCTUnwrap(URL(string: document.url)))
        let transport = FrozenWorkflowTransport(entries: entries)
        let provider = OpenRouterFoodProvider(extractionRoute: .grok, selectionRoute: .applicability) { request in try await transport.reply(request) }
        let reviewer = GenericFoodProposalReviewer(discovery: provider, capture: capture, extraction: provider,
            sourceSelection: provider, selection: provider)
        let result = try await reviewer.review(foodTerms: XCTUnwrap(plan["query"] as? String), key: "synthetic-replay-key-no-network")
        XCTAssertFalse(result.rankingUnavailable)
        XCTAssertEqual(result.suggestedChoice, "c1")
        XCTAssertEqual(result.validation.candidates.filter { result.permitsConfirmation(of: $0) }.map(\.id), ["c1"])
        XCTAssertNil(result.selection?.rawConfidence)
        let calls = await transport.calls; XCTAssertEqual(calls, 4)
        let captures = await capture.calls; XCTAssertEqual(captures, 1)
    }

    private func data(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    private func object(_ url: URL) throws -> [String: Any] { try StrictFoodProposalJSON.object(data(url)) }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func verifiedPlan(_ root: URL) throws -> [String: Any] {
        let bytes = try data(root.appendingPathComponent("plan.json"))
        XCTAssertEqual(hash(bytes), try String(contentsOf: root.appendingPathComponent("plan.sha256"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let plan = try StrictFoodProposalJSON.object(bytes)
        for (name, expected) in try XCTUnwrap(plan["snapshot_hashes"] as? [String: String]) {
            guard name.hasPrefix("snapshot/"), !name.contains("..") else { throw FoodWebDiscoveryError.invalidResponse }
            XCTAssertEqual(hash(try data(root.appendingPathComponent(name))), expected, name)
        }
        return plan
    }
    private func checkReceipt(_ receipt: [String: Any], request: Data, response: Data) throws {
        let item = try XCTUnwrap((receipt["requests"] as? [[String: Any]])?.first)
        XCTAssertEqual(hash(request), item["request_sha256"] as? String)
        XCTAssertEqual(hash(response), item["response_sha256"] as? String)
    }
}

private actor FrozenCapture: FoodDocumentCapturing {
    let document: CapturedFoodDocument
    let raw: Data
    let mediaType: String
    let expectedURL: URL
    private(set) var calls = 0
    init(document: CapturedFoodDocument, raw: Data, mediaType: String, expectedURL: URL) {
        self.document = document; self.raw = raw; self.mediaType = mediaType; self.expectedURL = expectedURL
    }
    func capture(_ url: URL) async throws -> CapturedFoodDocument {
        calls += 1; XCTAssertEqual(url, expectedURL)
        let value = try GenericFoodDocumentProjector.project(raw, url: XCTUnwrap(URL(string: document.url)), mediaType: mediaType,
            retrievedAt: XCTUnwrap(ISO8601DateFormatter().date(from: document.retrievedAt)), origin: document.captureOrigin)
        XCTAssertEqual(value, document)
        return value
    }
}

private actor FrozenWorkflowTransport {
    let entries: [(Data, Data)]
    private(set) var calls = 0
    let historicalSystemPrompt: Bool
    init(entries: [(Data, Data)], historicalSystemPrompt: Bool = false) {
        self.entries = entries; self.historicalSystemPrompt = historicalSystemPrompt
    }
    func reply(_ request: URLRequest) throws -> OpenRouterFoodHTTPReply {
        guard calls < entries.count else { throw FoodWebDiscoveryError.invalidResponse }
        let (expectedData, response) = entries[calls]; calls += 1
        var actual = try StrictFoodProposalJSON.object(XCTUnwrap(request.httpBody))
        var expected = try StrictFoodProposalJSON.object(expectedData)
        var actualMessages = try XCTUnwrap(actual["messages"] as? [[String: String]])
        var expectedMessages = try XCTUnwrap(expected["messages"] as? [[String: String]])
        // Historical responses predate the prompt repair. Replay verifies the unchanged
        // payload/schema/route and current gates; it cannot establish new-prompt inference.
        if historicalSystemPrompt {
            XCTAssertEqual(actualMessages.first?["role"], "system")
            XCTAssertEqual(expectedMessages.first?["role"], "system")
            actualMessages[0]["content"] = "historical-system-prompt"
            expectedMessages[0]["content"] = "historical-system-prompt"
            actual["messages"] = actualMessages; expected["messages"] = expectedMessages
        }
        if let a = actualMessages.last?["content"], let b = expectedMessages.last?["content"],
           let left = try? StrictFoodProposalJSON.object(Data(a.utf8)), let right = try? StrictFoodProposalJSON.object(Data(b.utf8)) {
            XCTAssertEqual(left as NSDictionary, right as NSDictionary)
            actualMessages[actualMessages.count - 1]["content"] = ""
            expectedMessages[expectedMessages.count - 1]["content"] = ""
            actual["messages"] = actualMessages; expected["messages"] = expectedMessages
        }
        XCTAssertEqual(actual as NSDictionary, expected as NSDictionary)
        return .init(status: 200, data: response)
    }
}

private actor ForbiddenMarketCapture: FoodDocumentCapturing {
    private(set) var calls = 0
    func capture(_ url: URL) async throws -> CapturedFoodDocument {
        calls += 1
        XCTFail("A rejected market must not be captured")
        throw FoodSourceAcquisitionError.invalidURL
    }
}
