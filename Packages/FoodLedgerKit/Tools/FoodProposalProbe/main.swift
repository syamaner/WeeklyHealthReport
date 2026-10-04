import CryptoKit
import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain

/// Opt-in local evaluation executable. No credentials in arguments or output.
/// Capture is keyless. Extraction requires the caller's private environment loader.
@main
enum FoodProposalProbe {
    static func main() async {
        do { try await run() }
        catch {
            let code: String
            if let typed = error as? FoodSourceAcquisitionError { code = "capture_\(typed)" }
            else if let typed = error as? FoodWebDiscoveryError { code = "provider_\(typed)" }
            else if let typed = error as? GenericFoodProposalError { code = "proposal_\(typed)" }
            else { code = "local_run_failed" }
            print(code)
            exit(1)
        }
    }
    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 3, args[0] == "capture-audit", let url = URL(string: args[1]) {
            let destination = URL(fileURLWithPath: args[2], isDirectory: true)
            try createDestination(destination)
            let journal = CaptureProbeJournal(directory: destination)
            let result = try await PublicFoodSourceCapture(observe: { try journal.record($0) }).capture(url)
            try encode(result).write(to: destination.appendingPathComponent("document.json"), options: .withoutOverwriting)
            print("Captured source and unauthenticated response evidence without provider calls.")
        } else if args.count == 3, args[0] == "capture", let url = URL(string: args[1]) {
            let result = try await PublicFoodSourceCapture().capture(url)
            try encode(result).write(to: URL(fileURLWithPath: args[2]), options: .withoutOverwriting)
            print("Captured \(result.blocks.count) blocks; no provider call or credential access.")
        } else if args.count == 5, args[0] == "project", let url = URL(string: args[2]) {
            let result = try GenericFoodDocumentProjector.project(Data(contentsOf: URL(fileURLWithPath: args[1])),
                url: url, mediaType: args[3], retrievedAt: Date(timeIntervalSince1970: 1_791_072_000), origin: "authored_development_fixture")
            try encode(result).write(to: URL(fileURLWithPath: args[4]), options: .withoutOverwriting)
            print("Projected local fixture without network or credential access.")
        } else if args.count == 5, args[0] == "reproject" {
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let original = try decoder.decode(CapturedFoodDocument.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            try original.validate()
            let raw = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard SHA256.hash(data: raw).map({ String(format: "%02x", $0) }).joined() == original.rawSha256,
                  let url = URL(string: original.url), let retrieved = ISO8601DateFormatter().date(from: original.retrievedAt) else {
                throw GenericFoodProposalError.invalidDocument
            }
            let result = try GenericFoodDocumentProjector.project(raw, url: url, mediaType: args[3],
                retrievedAt: retrieved, origin: "publisher_http_reprojected_offline")
            try encode(result).write(to: URL(fileURLWithPath: args[4]), options: .withoutOverwriting)
            print("Reprojected retained source bytes without network or credential access.")
        } else if args.count == 3, args[0] == "review-smoke" {
            guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], FoodWebKeySyntax.isValid(key) else { throw FoodWebDiscoveryError.credentialRejected }
            let destination = URL(fileURLWithPath: args[2], isDirectory: true)
            try createDestination(destination)
            let started = ContinuousClock.now
            let requests = ProbeJournal(directory: destination, key: key, maximumRequests: 6)
            let stages = ReviewSmokeJournal(directory: destination)
            let captures = CaptureProbeJournal(directory: destination)
            let provider = SmokeProvider(provider: OpenRouterFoodProvider(extractionRoute: .grok, selectionRoute: .applicability,
                transport: { try await requests.call($0) }), journal: stages)
            let capture = SmokeCapture(capture: PublicFoodSourceCapture(observe: { try captures.record($0) }), journal: stages)
            let reviewer = GenericFoodProposalReviewer(discovery: provider, capture: capture,
                extraction: provider, sourceSelection: provider, selection: provider, timeout: .seconds(150))
            var result: [String: Any] = ["query": args[1], "maximum_provider_requests": 6,
                "reviewer_deadline_seconds": 150, "save_authorised": false, "numeric_accuracy_scored": false,
                "review_required": true, "allowed_confirmation_ids": [] as [String]]
            do {
                let review = try await reviewer.review(foodTerms: args[1], sourceURL: nil, key: key)
                result["status"] = "completed"
                result["attempted_source_url"] = review.attemptedSourceURL?.absoluteString
                result["suggested_choice"] = review.suggestedChoice
                result["source_attempts"] = review.sourceAttempts.map(\.absoluteString)
                result["representative_source_only"] = review.representativeSourceOnly
                result["bound_candidate_ids"] = review.validation.candidates.map(\.id)
                result["eligible_candidate_ids"] = review.validation.candidates.filter(\.selectionEligible).map(\.id)
                result["allowed_confirmation_ids"] = review.validation.candidates.filter { review.permitsConfirmation(of: $0) }.map(\.id)
                result["rejected"] = review.validation.rejected.map { ["id": $0.id, "reason": String(describing: $0.reason)] }
                result["ranking_unavailable"] = review.rankingUnavailable
            } catch {
                result["status"] = "failed"
                result["closed_error"] = smokeError(error)
                if let partial = error as? GenericFoodProposalPartialFailure {
                    result["attempted_source_url"] = partial.attemptedSourceURL?.absoluteString
                    result["partial_discovery_preserved"] = partial.discovery != nil
                    result["source_attempts"] = partial.sourceAttempts.map(\.absoluteString)
                }
            }
            let elapsed = started.duration(to: .now).components
            result["review_elapsed_seconds"] = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            try stages.write(result, name: "result.json")
            print("Bounded full reviewer smoke finished; inspect retained stage results and receipt.")
        } else if args.count == 3, args[0] == "discover" {
            guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], FoodWebKeySyntax.isValid(key) else { throw FoodWebDiscoveryError.credentialRejected }
            let destination = URL(fileURLWithPath: args[2], isDirectory: true)
            try createDestination(destination)
            let journal = ProbeJournal(directory: destination, key: key, maximumRequests: 1)
            let provider = OpenRouterFoodProvider(transport: { try await journal.call($0) })
            let discovery = try await provider.discover(foodTerms: args[1], key: key)
            let result: [String: Any] = ["query": args[1], "leads": discovery.leads.map {
                ["title": $0.title, "url": $0.url.absoluteString, "cited_text": $0.citedText ?? ""]
            }, "response_text": discovery.responseText, "nutrition_admitted": false]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: destination.appendingPathComponent("discovery.json"))
            print("Completed one bounded discovery request; native links saved.")
        } else if (args.count == 4 && args[0] == "extract-and-select") || (args.count == 5 && ["extract-only", "extract-and-check"].contains(args[0])) {
            let checking = args[0] == "extract-and-check"
            let selectionEnabled = args[0] == "extract-and-select" || checking
            let offset = args[0] == "extract-and-select" ? 0 : 1
            guard let route = OpenRouterFoodExtractionRoute(rawValue: args[0] == "extract-and-select" ? "luna" : args[1]) else {
                throw GenericFoodProposalError.invalidSchema
            }
            guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], FoodWebKeySyntax.isValid(key) else { throw FoodWebDiscoveryError.credentialRejected }
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let input = try Data(contentsOf: URL(fileURLWithPath: args[1 + offset]))
            let documents: [CapturedFoodDocument]
            if input.first == UInt8(ascii: "[") { documents = try decoder.decode([CapturedFoodDocument].self, from: input) }
            else { documents = [try decoder.decode(CapturedFoodDocument.self, from: input)] }
            guard !documents.isEmpty, documents.count <= 3 else { throw GenericFoodProposalError.invalidDocument }
            for document in documents { try document.validate() }
            let destination = URL(fileURLWithPath: args[3 + offset], isDirectory: true)
            try createDestination(destination)
            let journal = ProbeJournal(directory: destination, key: key, maximumRequests: selectionEnabled ? 2 : 1)
            let provider = OpenRouterFoodProvider(extractionRoute: route, selectionRoute: checking ? .applicability : .jev, transport: { try await journal.call($0) })
            let extraction = try await provider.extract(foodTerms: args[2 + offset], documents: documents, key: key)
            try encode(extraction).write(to: destination.appendingPathComponent("extraction.json"))
            let bound = try FoodProposalBinding.validate(extraction, documents: documents)
            var result: [String: Any] = ["preferred_id": extraction.preferredId,
                "bound_candidate_ids": bound.candidates.map(\.id),
                "eligible_candidate_ids": bound.candidates.filter(\.selectionEligible).map(\.id),
                "rejected": bound.rejected.map { ["id": $0.id, "reason": String(describing: $0.reason)] },
                "save_authorised": false, "review_required": true]
            // Persist extraction/binding even when the optional selector fails.
            try writeResult(result, to: destination)
            if !selectionEnabled { result["selection_status"] = "disabled_for_extractor_comparison" }
            else if bound.candidates.contains(where: \.selectionEligible) {
                do {
                    let decision = try await provider.select(foodTerms: args[2 + offset], documents: documents, validation: bound, key: key)
                    let review = GenericFoodProposalReview(foodTerms: args[2 + offset], discovery: nil, documents: documents,
                        validation: bound, selection: decision)
                    result["choice"] = checking ? review.suggestedChoice : decision.choice
                    result["selector_route"] = checking ? "luna_applicability" : "jev"
                    result["allowed_confirmation_ids"] = bound.candidates.filter { review.permitsConfirmation(of: $0) }.map(\.id)
                    result["probabilities"] = decision.probabilities
                    result["raw_confidence"] = decision.rawConfidence.map { $0 as Any } ?? NSNull()
                    result["calibration"] = decision.calibration; result["selection_status"] = "completed"
                } catch {
                    result["selection_status"] = "failed"
                    result["selection_error"] = (error as? FoodWebDiscoveryError).map { String(describing: $0) } ?? "invalid_selection"
                    try writeResult(result, to: destination)
                    throw error
                }
            } else { result["selection_status"] = "skipped_no_eligible_candidates" }
            try writeResult(result, to: destination)
            print("Completed bounded Swift extraction and optional selection; evidence and receipt saved.")
        } else { throw GenericFoodProposalError.invalidSchema }
    }
    private static func createDestination(_ destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw GenericFoodProposalError.invalidSchema }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }
    private static func writeResult(_ result: [String: Any], to destination: URL) throws {
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("result.json"))
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}

private final class CaptureProbeJournal: @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private var rows: [[String: Any]] = []
    init(directory: URL) { self.directory = directory }
    func record(_ response: PublicFoodSourceCapture.ResponseObservation) throws {
        try lock.withLock {
            let filename = "source-body-\(rows.count + 1).bin"
            try response.body.write(to: directory.appendingPathComponent(filename), options: .withoutOverwriting)
            rows.append(["url": response.url.absoluteString, "status": response.status,
                         "media_type": response.mediaType ?? "", "body_file": filename, "body_bytes": response.body.count,
                         "body_sha256": SHA256.hash(data: response.body).map { String(format: "%02x", $0) }.joined(),
                         "observed_at": ISO8601DateFormatter().string(from: Date())])
            try JSONSerialization.data(withJSONObject: ["responses": rows], options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("capture-receipt.json"), options: .atomic)
        }
    }
}

private actor ProbeJournal {
    private let directory: URL
    private let key: String
    private let maximumRequests: Int
    private var rows: [[String: Any]] = []
    private var knownCost = 0.0
    private var canContinue = true
    init(directory: URL, key: String, maximumRequests: Int) {
        self.directory = directory; self.key = key; self.maximumRequests = maximumRequests
    }

    func call(_ request: URLRequest) async throws -> OpenRouterFoodHTTPReply {
        guard canContinue, rows.count < maximumRequests, knownCost < 0.05,
              request.url?.host == "openrouter.ai", request.httpMethod == "POST",
              ["/api/v1/chat/completions", "/api/alpha/decisions"].contains(request.url?.path ?? ""),
              let body = request.httpBody, let text = String(data: body, encoding: .utf8), !text.contains(key) else {
            throw FoodWebDiscoveryError.requestRejected
        }
        canContinue = false
        let index = rows.count
        rows.append(["request": index + 1, "endpoint": request.url!.path, "status": "started",
                     "request_sha256": hash(body), "started_at": ISO8601DateFormatter().string(from: Date())])
        try body.write(to: directory.appendingPathComponent("request-\(index + 1).json"))
        try save()
        let start = ContinuousClock.now
        let reply: OpenRouterFoodHTTPReply
        do { reply = try await OpenRouterFoodProvider.liveTransport(request) }
        catch {
            let elapsed = start.duration(to: .now).components
            rows[index]["latency_seconds"] = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            rows[index]["status"] = "transport_failed_cost_unknown"
            try save()
            throw error
        }
        let elapsed = start.duration(to: .now).components
        rows[index]["latency_seconds"] = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        rows[index]["http_status"] = reply.status
        guard let payload = try? JSONSerialization.jsonObject(with: reply.data), !containsKey(payload) else {
            rows[index]["status"] = "invalid_or_sensitive_response"; try save(); throw FoodWebDiscoveryError.invalidResponse
        }
        try reply.data.write(to: directory.appendingPathComponent("response-\(index + 1).json"))
        rows[index]["response_sha256"] = hash(reply.data)
        if let object = payload as? [String: Any] {
            rows[index]["observed_model"] = object["model"]
            rows[index]["observed_provider"] = object["provider"]
            if let cost = (object["usage"] as? [String: Any])?["cost"] as? Double, cost.isFinite, cost >= 0 {
                knownCost += cost; rows[index]["reported_cost_usd"] = cost
                canContinue = reply.status == 200
            }
        }
        rows[index]["status"] = canContinue ? "received" : "stopped"
        try save()
        return reply
    }
    private func containsKey(_ value: Any) -> Bool {
        if let text = value as? String { return text.contains(key) }
        if let items = value as? [Any] { return items.contains(where: containsKey) }
        if let object = value as? [String: Any] { return object.keys.contains(where: { $0.contains(key) }) || object.values.contains(where: containsKey) }
        return false
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func save() throws {
        let receipt: [String: Any] = ["requests": rows, "known_reported_cost_usd": knownCost,
            "cost_known_requests": rows.filter { $0["reported_cost_usd"] != nil }.count,
            "maximum_requests": maximumRequests, "reported_cost_stop_usd": 0.05, "automatic_retries": 0,
            "cost_stop_is_not_a_prepaid_hard_cap": true]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("receipt.json"), options: .atomic)
    }
}

/// Evaluation-only decorators record the real application ports without changing
/// selection, capture, extraction or reviewer behaviour. Capture receives no key.
private final class ReviewSmokeJournal: @unchecked Sendable {
    private let lock = NSLock()
    private let directory: URL
    private var stages: [[String: Any]] = []
    init(directory: URL) { self.directory = directory }
    func begin(_ stage: String) throws {
        try lock.withLock {
            stages.append(["stage": stage, "status": "started", "started_at": ISO8601DateFormatter().string(from: Date())])
            try persist()
        }
    }
    func end(_ stage: String, error: Error? = nil) throws {
        try lock.withLock {
            guard let index = stages.lastIndex(where: { $0["stage"] as? String == stage }) else { throw GenericFoodProposalError.invalidSchema }
            stages[index]["status"] = error == nil ? "completed" : "failed"
            stages[index]["finished_at"] = ISO8601DateFormatter().string(from: Date())
            if let error { stages[index]["closed_error"] = smokeError(error) }
            try persist()
        }
    }
    func write(_ value: [String: Any], name: String) throws {
        try writeData(JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), name: name)
    }
    func encode<T: Encodable>(_ value: T, name: String) throws {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeData(encoder.encode(value), name: name)
    }
    private func writeData(_ data: Data, name: String) throws {
        try lock.withLock {
            var target = directory.appendingPathComponent(name)
            var index = 2
            while FileManager.default.fileExists(atPath: target.path) {
                let stem = (name as NSString).deletingPathExtension
                target = directory.appendingPathComponent("\(stem)-\(index).json"); index += 1
            }
            try data.write(to: target, options: .withoutOverwriting)
        }
    }
    func discovery(_ found: FoodWebDiscoveryResult) throws {
        try write(["leads": found.leads.map { ["title": $0.title, "url": $0.url.absoluteString,
                       "cited_text": $0.citedText ?? ""] }, "response_text": found.responseText], name: "discovery.json")
    }
    private func persist() throws {
        try JSONSerialization.data(withJSONObject: ["stages": stages], options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("stages.json"), options: .atomic)
    }
}

private func smokeError(_ error: Error) -> String {
    if let partial = error as? GenericFoodProposalPartialFailure {
        switch partial.reason {
        case let .acquisition(reason): return "capture_\(reason)"
        case let .provider(reason): return "provider_\(reason)"
        case .invalidProposal: return "proposal_invalid"
        case .sourceNotSuggested: return "source_not_suggested"
        case .sourceMarketConflict: return "source_market_conflict"
        }
    }
    if let error = error as? FoodSourceAcquisitionError { return "capture_\(error)" }
    if let error = error as? FoodWebDiscoveryError { return "provider_\(error)" }
    if let error = error as? GenericFoodProposalError { return "proposal_\(error)" }
    if error is CancellationError { return "cancelled" }
    if let error = error as? GenericFoodProposalReviewError {
        switch error { case .noSourceLinks: return "no_source_links"; case .alreadyRunning: return "already_running" }
    }
    return "local_run_failed"
}

private struct SmokeProvider: FoodWebDiscovering, FoodSourceLeadSelecting, FoodProposalExtracting, FoodProposalSelecting {
    func select(foodTerms: String, documents: [CapturedFoodDocument], validation: FoodProposalValidation, key: String) async throws -> FoodProposalSelection {
        try journal.begin("applicability")
        do {
            let value = try await provider.select(foodTerms: foodTerms, documents: documents, validation: validation, key: key)
            try journal.write(["choice": value.choice, "calibration": value.calibration], name: "applicability.json")
            try journal.end("applicability"); return value
        } catch { try journal.end("applicability", error: error); throw error }
    }
    let provider: OpenRouterFoodProvider
    let journal: ReviewSmokeJournal
    func validate(key: String) async throws { try await provider.validate(key: key) }
    func discover(foodTerms: String, key: String) async throws -> FoodWebDiscoveryResult {
        try journal.begin("discovery")
        do {
            let value = try await provider.discover(foodTerms: foodTerms, key: key)
            try journal.discovery(value); try journal.end("discovery"); return value
        } catch { try journal.end("discovery", error: error); throw error }
    }
    func chooseSource(foodTerms: String, leads: [FoodWebLead], key: String) async throws -> FoodSourceLeadDecision {
        try journal.begin("source_selection")
        do {
            let value = try await provider.chooseSource(foodTerms: foodTerms, leads: leads, key: key)
            switch value {
            case let .selected(index, purpose, reason):
                try journal.write(["decision": "selected", "index": index, "reason": reason,
                    "purpose": purpose == .representativeEstimate ? "representative_estimate" : "primary_product",
                    "offered_urls": leads.map { $0.url.absoluteString }], name: "source-selection.json")
            case let .abstain(reason):
                try journal.write(["decision": "abstain", "reason": reason,
                    "offered_urls": leads.map { $0.url.absoluteString }], name: "source-selection.json")
            }
            try journal.end("source_selection"); return value
        } catch { try journal.end("source_selection", error: error); throw error }
    }
    func extract(foodTerms: String, documents: [CapturedFoodDocument], key: String) async throws -> FoodProposalExtraction {
        try journal.begin("extraction")
        do {
            let value = try await provider.extract(foodTerms: foodTerms, documents: documents, key: key)
            try journal.encode(value, name: "extraction.json"); try journal.end("extraction"); return value
        } catch { try journal.end("extraction", error: error); throw error }
    }
}

private struct SmokeCapture: FoodDocumentCapturing {
    let capture: PublicFoodSourceCapture
    let journal: ReviewSmokeJournal
    func capture(_ url: URL) async throws -> CapturedFoodDocument {
        try journal.begin("capture")
        try journal.write(["url": url.absoluteString, "provider_credentials_supplied": false], name: "capture-attempt.json")
        do {
            let value = try await capture.capture(url)
            try journal.encode(value, name: "document.json"); try journal.end("capture"); return value
        } catch { try journal.end("capture", error: error); throw error }
    }
}
