import ConfirmEnrichmentEvalCore
import ConfirmEnrichmentEvalHarness
import FoodConfirmEnrichment
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import XCTest

/// The evaluation harness over a fake transport (docs/confirm-enrichment-openrouter-v1-phase.md sections
/// 3.3 item 5 and 9, G11). Synthetic records only; nothing is sent and no key is read.
final class EvalHarnessTests: XCTestCase {
    static let name = "Synthetic oat crunch"
    static let brand = "Examplebrand"
    static let code = "3274080005003"
    nonisolated(unsafe) static let product: [String: Any] = [
        "code": code, "product_name": name, "brands": brand, "quantity": "500 g", "nutrition_data_per": "100g",
        "nutriments": ["energy-kcal_100g": 120, "energy-kcal_unit": "kcal", "proteins_100g": 8, "proteins_unit": "g",
                       "fat_100g": 1, "fat_unit": "g"],
    ]

    func privateFolder(shape: EvalCase.Shape = .barcode) throws -> (URL, EvalCaseList) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ce1-eval-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("records"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try JSONSerialization.data(withJSONObject: Self.product, options: [.sortedKeys])
            .write(to: folder.appendingPathComponent("records/synthetic.json"))
        let list = EvalCaseList(cases: [EvalCase(kind: .openFoodFacts, record: "records/synthetic.json", shape: shape,
                                                 retrievedAt: "2026-11-21T10:00:00Z", hidden: [.fatTotal])])
        return (folder, list)
    }

    static func catalogue(_ request: ConfirmEnrichmentHTTPRequest, prompt: String = "0.0000002") -> ConfirmEnrichmentHTTPResponse? {
        guard request.method == "GET" else { return nil }
        let routes = [ConfirmEnrichmentRoutes.details, ConfirmEnrichmentRoutes.nutrients]
        if request.url.path.hasSuffix("/endpoints/zdr") {
            let entries = routes.map { ["model_id": $0.model, "tag": $0.providerEndpoint] }
            return .init(status: 200, headers: [:], body: try! JSONSerialization.data(withJSONObject: ["data": entries]), exceededLimit: false)
        }
        guard let route = routes.first(where: { request.url.path.contains($0.model) }) else {
            return .init(status: 404, headers: [:], body: Data(), exceededLimit: false)
        }
        let listing: [String: Any] = ["data": ["id": route.model, "endpoints": [[
            "tag": route.providerEndpoint, "pricing": ["prompt": prompt, "completion": "0.0000008"]]]]]
        return .init(status: 200, headers: [:], body: try! JSONSerialization.data(withJSONObject: listing), exceededLimit: false)
    }

    /// Answers as the routes would, naming the live routes' models and providers.
    static func answering(prompt: String = "0.0000002", promptTokens: Int = 200) -> FakeTransport {
        FakeTransport { request in
            if let response = catalogue(request, prompt: prompt) { return response }
            let body = String(decoding: request.body ?? Data(), as: UTF8.self)
            if request.url.absoluteString == ConfirmEnrichmentRoutes.detailsURL, let inputs = ConfirmDetailsRequestInputs.decode(requestBody: body) {
                var answers: [String: Any] = [:]
                for fact in inputs.asked {
                    answers[fact.rawValue] = ["type": "choice", "choice": "unknown", "confidence": 0.9, "probabilities": ["unknown": 0.9]]
                }
                let reply: [String: Any] = ["id": "gen-eval", "model": ConfirmEnrichmentRoutes.details.model,
                                            "provider": ConfirmEnrichmentRoutes.details.provider, "answers": answers,
                                            "usage": ["cost": 0.0003, "input_tokens": promptTokens]]
                return .init(status: 200, headers: [:], body: try! JSONSerialization.data(withJSONObject: reply), exceededLimit: false)
            }
            if request.url.absoluteString == ConfirmEnrichmentRoutes.nutrientURL, let inputs = ConfirmNutrientRequestInputs.decode(requestBody: body) {
                let rows = inputs.eligible.prefix(2).map { ["nutrient": $0.nutrient, "value": 1, "unit": $0.unit] as [String: Any] }
                let content = String(decoding: try! JSONSerialization.data(withJSONObject: [
                    "schema": ConfirmEnrichmentVersions.nutrientSchema, "basis": inputs.basis.rawValue, "values": rows]), as: UTF8.self)
                let reply: [String: Any] = [
                    "id": "gen-eval", "model": ConfirmEnrichmentRoutes.nutrients.model, "provider": ConfirmEnrichmentRoutes.nutrients.provider,
                    "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": content]]],
                    "usage": ["cost": 0.0011, "prompt_tokens": 600]]
                return .init(status: 200, headers: [:], body: try! JSONSerialization.data(withJSONObject: reply), exceededLimit: false)
            }
            return .init(status: 400, headers: [:], body: Data(), exceededLimit: false)
        }
    }

    func sender(_ part: ConfirmEnrichmentPart, transport: FakeTransport, folder: URL, ledger: EvalSpendLedger? = nil) -> EvalSender {
        EvalSender(part: part, transport: transport, keys: FixedEvalKey(),
                   ledger: ledger ?? EvalSpendLedger(url: folder.appendingPathComponent("ledger.json")), privateFolder: folder,
                   wait: { _ in })
    }

    // MARK: G11

    func testTheConsoleNamesCasesByHashOnlyAndOnlyTheRouteDestinationsAreReached() async throws {
        let (folder, list) = try privateFolder()
        let transport = Self.answering()
        var lines: [String] = []
        for part in ConfirmEnrichmentPart.allCases {
            lines += await sender(part, transport: transport, folder: folder).run(list)
        }
        let hash = try EvalHashes.hash(list.cases[0])
        XCTAssertTrue(lines.contains("case \(hash.prefix(12)) part details outcome answered attempts 1"), "\(lines)")
        XCTAssertTrue(lines.contains("case \(hash.prefix(12)) part nutrients outcome answered attempts 1"), "\(lines)")
        let output = lines.joined(separator: "\n")
        for secret in [Self.name, Self.brand, Self.code, "messages", "\"state\"", "answers", "choices", "schema", "Bearer", "sk-or"] {
            XCTAssertFalse(output.contains(secret), "the console holds \(secret)")
        }
        let allowed: Set<String> = [
            ConfirmEnrichmentRoutes.detailsURL, ConfirmEnrichmentRoutes.nutrientURL, ConfirmEnrichmentRoutes.detailsEndpointsURL,
            ConfirmEnrichmentRoutes.nutrientEndpointsURL, ConfirmEnrichmentRoutes.zeroDataRetentionURL,
        ]
        XCTAssertFalse(transport.sent.isEmpty)
        for sent in transport.sent {
            XCTAssertTrue(allowed.contains(sent.url.absoluteString), sent.url.absoluteString)
            XCTAssertEqual(sent.method == "POST", sent.headerNames.contains("Authorization"), "only the POSTs carry the key")
        }
        let responses = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("responses").path)
        XCTAssertEqual(responses.filter { !$0.hasSuffix("-evidence.json") }.count, 2)
        XCTAssertEqual(responses.filter { $0.hasSuffix("-evidence.json") }.count, 2)
    }

    func testDetailsScoreRebuildsTheRequestAndRejectsChangedResponseBytes() async throws {
        let (folder, list) = try privateFolder()
        let transport = Self.answering()
        let lines = await sender(.details, transport: transport, folder: folder).run(list, firstRequestOnly: true)
        let posts = transport.sent.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 1)
        let body = try XCTUnwrap(posts.first?.body)
        let digest = try SHA256Digester().sha256(body).value
        XCTAssertTrue(lines.contains("first_request details accepted max_tokens_sent true sha256 " + digest))

        let hash = try EvalHashes.hash(list.cases[0])
        let row = [hash, "Synthetic, \"quoted\"\rrecord", Self.brand, Self.code, "yes",
                   "as_sold", "unknown", "unknown", "unknown", "unknown", "fortified"]
        let csv = [EvalSelection.reviewSheetHeader, row]
            .map { $0.map(EvalSelection.csvField).joined(separator: ",") }
            .joined(separator: "\r\n")
        let sheet = folder.appendingPathComponent("review.csv")
        try Data(csv.utf8).write(to: sheet)
        let scorer = EvalScorer()
        let probe = scorer.score(list, part: .details, folder: folder, reviewSheet: sheet)
        XCTAssertEqual(probe.map { EvalConsole.scoreLine($0) }, ["details evidence fail within 0 outside 1"])
        _ = await sender(.details, transport: transport, folder: folder).run(list)
        let score = scorer.score(list, part: .details, folder: folder, reviewSheet: sheet)
        XCTAssertEqual(score.first { $0.bar == .coverage }?.passed, false)
        XCTAssertEqual(score.first { $0.bar == .cost }?.passed, true)
        XCTAssertEqual(score.first { $0.bar == .unfortifiedOnFortified }?.within, 1)
        XCTAssertEqual(score.first { $0.bar == .unfortifiedOnFortified }?.passed, false)
        XCTAssertTrue(scorer.verifyDetailsFreeze(list, folder: folder, expectedSHA256: digest))
        XCTAssertFalse(scorer.verifyDetailsFreeze(list, folder: folder, expectedSHA256: nil))
        let response = folder.appendingPathComponent("responses/\(hash)-details-1.json")
        try Data("unbound response".utf8).write(to: response)
        let invalid = scorer.score(list, part: .details, folder: folder, reviewSheet: sheet)
        XCTAssertEqual(invalid.map { EvalConsole.scoreLine($0) }, ["details evidence fail within 0 outside 1"])
    }

    func testBVariantsKeepReferencesOutOfTheWireAndScoreMissingClasses() async throws {
        let (folder, list) = try privateFolder()
        var product = Self.product
        var declared = try XCTUnwrap(product["nutriments"] as? [String: Any])
        declared["salt_100g"] = "1.25"
        product["nutriments"] = declared
        try JSONSerialization.data(withJSONObject: product).write(to: folder.appendingPathComponent("records/synthetic.json"))

        let item = list.cases[0]
        let unhidden = EvalCase(kind: item.kind, record: item.record, shape: item.shape, retrievedAt: item.retrievedAt)
        let inputs = EvalCaseList(cases: [unhidden])
        let transport = Self.answering()
        _ = await sender(.nutrients, transport: transport, folder: folder).run(inputs)
        let posts = transport.sent.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 3)
        for (post, hidden) in zip(posts, [NutrientKey.energyConsumed, .fatTotal, .sodium]) {
            let bytes = try XCTUnwrap(post.body)
            let request = try XCTUnwrap(ConfirmNutrientRequestInputs.decode(requestBody: String(decoding: bytes, as: UTF8.self)))
            XCTAssertTrue(request.eligibleKeys.contains(hidden))
            XCTAssertNil(request.knownAmounts[hidden])
            XCTAssertNil(request.knownAmounts[.sodium])
        }
        let score = EvalScorer().score(inputs, part: .nutrients, folder: folder, reviewSheet: nil)
        XCTAssertEqual(score.first { $0.bar == .knownReplaced }?.passed, true)
        XCTAssertEqual(score.first { $0.bar == .micronutrients }?.passed, false)
        XCTAssertEqual(score.first { $0.bar == .cost }?.within, 3)
    }

    func testAnUnreadablePlannedCasePreventsSendingEitherPart() async throws {
        let (folder, valid) = try privateFolder()
        let missing = EvalCase(kind: .openFoodFacts, record: "records/missing.json", shape: .barcode,
                               retrievedAt: "2026-11-21T10:00:00Z")
        let list = EvalCaseList(cases: valid.cases + [missing])
        for part in ConfirmEnrichmentPart.allCases {
            let transport = Self.answering()
            let lines = await sender(part, transport: transport, folder: folder).run(list)
            XCTAssertEqual(lines, ["stop request_plan_unavailable"])
            XCTAssertTrue(transport.sent.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("completed-\(part.rawValue).json").path))
        }
    }

    func testAnExplicitBVariantScoresAndFakeRunCannotBeReadAsLive() async throws {
        let (folder, list) = try privateFolder()
        let transport = Self.answering()
        let evidence = folder.appendingPathComponent("fake", isDirectory: true)
        let ledger = EvalSpendLedger(url: evidence.appendingPathComponent("ledger.json"))
        let sender = EvalSender(part: .nutrients, transport: transport, keys: FixedEvalKey(), ledger: ledger,
                                privateFolder: folder, evidenceFolder: evidence, fake: true)
        _ = await sender.run(list)
        XCTAssertEqual(transport.sent.filter { $0.method == "POST" }.count, 1)
        let scorer = EvalScorer()
        let score = scorer.score(list, part: .nutrients, folder: folder, reviewSheet: nil, evidenceFolder: evidence, fake: true)
        XCTAssertEqual(score.first { $0.bar == .cost }?.within, 1)
        XCTAssertTrue(score.allSatisfy { EvalConsole.scoreLine($0, fake: true).hasPrefix("fake nutrients ") })
        let unmarked = scorer.score(list, part: .nutrients, folder: folder, reviewSheet: nil, evidenceFolder: evidence)
        XCTAssertEqual(unmarked.map { $0.bar }, [.evidence])
    }

    func testTheLiveSpendLedgerHasOneProcessLockForBothParts() throws {
        let (folder, _) = try privateFolder()
        let first = try XCTUnwrap(EvalLiveRunLock.acquire(in: folder))
        XCTAssertNil(EvalLiveRunLock.acquire(in: folder))
        try first.close()
        let second = try XCTUnwrap(EvalLiveRunLock.acquire(in: folder))
        try second.close()
    }

    func testSealedPartCanSendOnceAndItsSheetCannotOverwriteEitherSheet() async throws {
        let (folder, list) = try privateFolder()
        let development = folder.appendingPathComponent("review-sheet-development.csv")
        let sentinel = Data("development sentinel".utf8)
        try sentinel.write(to: development)
        XCTAssertEqual(try EvalReviewSheet.writeSealed(list, folder: folder), 1)
        XCTAssertThrowsError(try EvalReviewSheet.writeSealed(list, folder: folder))
        XCTAssertEqual(try Data(contentsOf: development), sentinel)
        let sealedSheet = folder.appendingPathComponent("review-sheet-sealed.csv")
        let hash = try EvalHashes.hash(list.cases[0])
        XCTAssertTrue(try String(contentsOf: sealedSheet, encoding: .utf8).contains(hash))

        let transport = Self.answering()
        let sender = sender(.nutrients, transport: transport, folder: folder)
        let first = await sender.run(list, sealed: true)
        let second = await sender.run(list, sealed: true)
        XCTAssertFalse(first.contains { $0.hasPrefix("stop ") })
        XCTAssertEqual(second, ["stop sealed_run_already_claimed_or_unwritable"])
        XCTAssertEqual(transport.sent.filter { $0.method == "POST" }.count, 1)
    }

    /// Freeze item 1: a sealed part is claimed only when the programme stop leaves room for its whole run at
    /// worst, so a budget stop can never use up a sealed part.
    func testASealedPartIsNotClaimedWhenTheBudgetCannotCoverItsWholeRun() async throws {
        let (folder, list) = try privateFolder()
        let ledger = EvalSpendLedger(url: folder.appendingPathComponent("ledger.json"))
        // Leave $0.001 of headroom: below one nutrient request at W.
        while (try? ledger.reserve(part: "nutrients", caseHash: "earlier", worstCaseMicroUSD: 50_000)) != nil {}
        while (try? ledger.reserve(part: "nutrients", caseHash: "earlier", worstCaseMicroUSD: 1_000)) != nil {}
        let headroom = try ledger.headroomMicroUSD()
        XCTAssertLessThan(headroom, 1_000)
        let transport = Self.answering()
        let lines = await sender(.nutrients, transport: transport, folder: folder, ledger: ledger).run(list, sealed: true)
        XCTAssertEqual(lines.last, "stop sealed_budget_insufficient", "\(lines)")
        XCTAssertTrue(lines.first?.hasPrefix("budget sealed part nutrients needs_microusd ") == true, "\(lines)")
        XCTAssertTrue(lines.first?.hasSuffix(" headroom_microusd \(headroom)") == true, "\(lines)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("claimed-nutrients").path),
                       "the part stays unclaimed")
        XCTAssertFalse(transport.sent.contains { $0.method == "POST" })
    }

    /// A retried attempt that reports less than W lets another attempt start, so the bound per request is
    /// the smaller of three attempts at W and the whole-request cap, not whole multiples of W within the cap.
    func testTheSealedWorstCaseCoversRetriesThatReportLessThanW() {
        let details = ConfirmEnrichmentPart.details.perRequestCapMicroUSD
        let nutrients = ConfirmEnrichmentPart.nutrients.perRequestCapMicroUSD
        // W of 60 % of the cap: a sub-W report then a timeout at W charges up to the cap.
        XCTAssertEqual(EvalSender.sealedWorstCase(requests: 10, w: details * 6 / 10, part: .details), 10 * details)
        // W of 35 % of the cap: three attempts can start, up to the cap.
        XCTAssertEqual(EvalSender.sealedWorstCase(requests: 1, w: nutrients * 35 / 100, part: .nutrients), nutrients)
        // A small W: three attempts at W.
        XCTAssertEqual(EvalSender.sealedWorstCase(requests: 4, w: 100, part: .nutrients), 4 * 3 * 100)
        XCTAssertEqual(EvalSender.sealedWorstCase(requests: 5, w: 0, part: .details), 0)
        XCTAssertNil(EvalSender.sealedWorstCase(requests: Int.max, w: 100, part: .details))
        XCTAssertNil(EvalSender.sealedWorstCase(requests: 1, w: -1, part: .details))
    }

    func testAStoppedLedgerRefusesASealedClaim() async throws {
        let (folder, list) = try privateFolder()
        let ledger = EvalSpendLedger(url: folder.appendingPathComponent("ledger.json"))
        let id = try ledger.reserve(part: "nutrients", caseHash: "earlier", worstCaseMicroUSD: 1_000)
        try ledger.settle(id, reportedMicroUSD: -1)
        let lines = await sender(.nutrients, transport: Self.answering(), folder: folder, ledger: ledger).run(list, sealed: true)
        XCTAssertEqual(lines, ["stop ledger_stopped"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("claimed-nutrients").path))
    }

    /// Freeze item 3 (owner decision, 22 November 2026): a sealed part whose send fails after the claim stays used up. The
    /// model may already have seen some of its requests, so it is never sent again.
    func testASealedPartThatFailsAfterItsClaimStaysUsedUp() async throws {
        let (folder, list) = try privateFolder()
        struct Offline: ConfirmEnrichmentHTTPTransporting {
            func send(_ request: ConfirmEnrichmentHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws
                -> ConfirmEnrichmentHTTPResponse {
                if let response = EvalHarnessTests.catalogue(request, prompt: "0.0000002") { return response }
                throw ConfirmEnrichmentTransportError.offline
            }
        }
        let failing = EvalSender(part: .details, transport: Offline(), keys: FixedEvalKey(),
                                 ledger: EvalSpendLedger(url: folder.appendingPathComponent("ledger.json")), privateFolder: folder,
                                 wait: { _ in })
        let first = await failing.run(list, sealed: true)
        XCTAssertTrue(first.contains("stop first_request_transport_failed"), "\(first)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("claimed-details").path))
        let transport = Self.answering()
        let second = await sender(.details, transport: transport, folder: folder).run(list, sealed: true)
        XCTAssertEqual(second, ["stop sealed_run_already_claimed_or_unwritable"])
        XCTAssertFalse(transport.sent.contains { $0.method == "POST" }, "a used-up sealed part is never sent again")
    }

    /// Freeze item 2: the offline plan check builds both parts' plans with nothing sent.
    func testThePlanCheckCountsBothPartsAndStopsOnACaseItCannotBuild() throws {
        let (folder, list) = try privateFolder()
        let lines = EvalPlanCheck.lines(list, set: "sealed", privateFolder: folder)
        XCTAssertEqual(lines.count, 1, "\(lines)")
        XCTAssertTrue(lines[0].hasPrefix("plan sealed details_requests "), "\(lines)")
        XCTAssertFalse(lines[0].contains(Self.name) || lines[0].contains(Self.code), "counts only")
        let missing = EvalCaseList(cases: list.cases + [EvalCase(kind: .openFoodFacts, record: "records/missing.json", shape: .barcode,
                                                                  retrievedAt: "2026-11-21T10:00:00Z", hidden: [.fatTotal])])
        XCTAssertEqual(EvalPlanCheck.lines(missing, set: "sealed", privateFolder: folder), ["stop plan_details_unavailable"])
    }

    func testTheRunStopsAtTheProgrammeStop() async throws {
        let (folder, list) = try privateFolder()
        let ledger = EvalSpendLedger(url: folder.appendingPathComponent("ledger.json"))
        while (try? ledger.reserve(part: "nutrients", caseHash: "earlier", worstCaseMicroUSD: 50_000)) != nil {}
        let transport = Self.answering()
        let lines = await sender(.nutrients, transport: transport, folder: folder, ledger: ledger).run(list)
        XCTAssertTrue(lines.contains("stop programme_stop"), "\(lines)")
        XCTAssertFalse(transport.sent.contains { $0.method == "POST" }, "nothing is sent past the stop")
    }

    /// Section 9's first request stop (invariant review of PR 3).
    func testAFirstRequestThatIsNotAcceptedStopsTheRunAfterOneCase() async throws {
        let (folder, list) = try privateFolder()
        let refusing = FakeTransport { request in
            Self.catalogue(request, prompt: "0.0000002") ?? .init(status: 400, headers: [:], body: Data("{}".utf8), exceededLimit: false)
        }
        let lines = await sender(.details, transport: refusing, folder: folder).run(list)
        XCTAssertTrue(lines.contains("stop first_request_not_accepted"), "\(lines)")
        XCTAssertEqual(refusing.sent.filter { $0.method == "POST" }.count, 1, "nothing more after the first case")
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("first-request-details.json")))
                                   as? [String: Any])
        XCTAssertEqual(record["accepted"] as? Bool, false)
        XCTAssertEqual(record["max_tokens_sent"] as? Bool, ConfirmEnrichmentRoutes.details.sendsMaxTokens)
        XCTAssertNil(record["body"]); XCTAssertNil(record["response"])
    }

    func testAFirstRequestTransportFailureHasItsOwnStopAndANegativeCostStopsTheLedger() async throws {
        let (folder, list) = try privateFolder()
        struct Offline: ConfirmEnrichmentHTTPTransporting {
            func send(_ request: ConfirmEnrichmentHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws
                -> ConfirmEnrichmentHTTPResponse {
                if let response = EvalHarnessTests.catalogue(request, prompt: "0.0000002") { return response }
                throw ConfirmEnrichmentTransportError.offline
            }
        }
        let lines = await EvalSender(part: .details, transport: Offline(), keys: FixedEvalKey(),
                                     ledger: EvalSpendLedger(url: folder.appendingPathComponent("ledger.json")), privateFolder: folder,
                                     wait: { _ in }).run(list)
        XCTAssertTrue(lines.contains("stop first_request_transport_failed"), "\(lines)")
        XCTAssertEqual(EvalSender.reportedCost(Data(#"{"usage":{"cost":-0.01}}"#.utf8)), -1)
    }

    func testAFirstRequestReportingPromptTokensAboveTheCeilingStopsTheRun() async throws {
        let (folder, list) = try privateFolder()
        let transport = Self.answering(promptTokens: ConfirmEnrichmentRoutes.details.promptCeilingTokens + 1)
        let lines = await sender(.details, transport: transport, folder: folder).run(list)
        XCTAssertTrue(lines.contains("stop first_request_prompt_over_ceiling"), "\(lines)")
        XCTAssertEqual(transport.sent.filter { $0.method == "POST" }.count, 1)
    }

    /// Defect review of PR 3: the tool's retries follow the app's whole-request cap. W of about $0.0104 on
    /// B fits the $0.02 cap once, so after a 503 no second attempt starts.
    func testRetriesStopWhereTheAppsWholeRequestCapWould() async throws {
        let (folder, list) = try privateFolder()
        // prompt 0.0000015, completion 0.0000008: W = 6,000 * 1.5e-6 + 1,700 * 8e-7 = 0.01036, under the $0.02 cap once.
        let transport = FakeTransport { request in
            if let response = Self.catalogue(request, prompt: "0.0000015") { return response }
            return .init(status: 503, headers: [:], body: Data(), exceededLimit: false)
        }
        let ledger = EvalSpendLedger(url: folder.appendingPathComponent("ledger.json"))
        let sender = EvalSender(part: .nutrients, transport: transport, keys: FixedEvalKey(), ledger: ledger,
                                privateFolder: folder, wait: { _ in XCTFail("A blocked retry must not wait") })
        _ = await sender.run(list)
        let posts = transport.sent.filter { $0.method == "POST" }.count
        let w = ConfirmEnrichmentSpendPolicy.worstCase(ConfirmEnrichmentRoutes.nutrients,
            prices: ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.0000015")!, completionPerTokenUSD: Decimal(string: "0.0000008")!))
        XCTAssertGreaterThan(2 * w, ConfirmEnrichmentPart.nutrients.perRequestCapMicroUSD, "the fixture needs W above half the cap")
        XCTAssertEqual(posts, 1, "one attempt, as the app's session would make")
    }

    func testAWorstCaseAboveTheAppCapStopsBeforeAnyPost() async throws {
        let (folder, list) = try privateFolder()
        let transport = Self.answering(prompt: "0.001")
        let lines = await sender(.details, transport: transport, folder: folder).run(list)
        XCTAssertEqual(lines, ["stop worst_case_above_app_cap"])
        XCTAssertFalse(transport.sent.contains { $0.method == "POST" })
    }

    func testARouteCheckThatFailsSendsNothing() async throws {
        let (folder, list) = try privateFolder()
        let transport = FakeTransport { _ in .init(status: 503, headers: [:], body: Data(), exceededLimit: false) }
        let lines = await sender(.nutrients, transport: transport, folder: folder).run(list)
        XCTAssertEqual(lines, ["stop route_unavailable"])
        XCTAssertFalse(transport.sent.contains { $0.method == "POST" })
    }

    // MARK: The app's candidates

    func testTheBarcodeAndSearchCandidatesOfOneRecordGiveTheSameRequestBytes() throws {
        let candidates = EvalCandidates()
        var bodies: [EvalCase.Shape: (Data, Data)] = [:]
        for shape in [EvalCase.Shape.barcode, .search] {
            let (folder, list) = try privateFolder(shape: shape)
            let state = try candidates.state(for: list.cases[0], privateFolder: folder)
            let details = try XCTUnwrap(EvalRequests.details(state, route: ConfirmEnrichmentRoutes.details))
            let nutrients = try XCTUnwrap(EvalRequests.nutrients(state, route: ConfirmEnrichmentRoutes.nutrients))
            XCTAssertTrue(nutrients.inputs.eligibleKeys.contains(.fatTotal), "a hidden key is asked")
            XCTAssertFalse(nutrients.inputs.known.contains { $0.nutrient == "fat_total" }, "and never sent as known")
            bodies[shape] = (details.body, nutrients.body)
        }
        XCTAssertEqual(bodies[.barcode]?.0, bodies[.search]?.0)
        XCTAssertEqual(bodies[.barcode]?.1, bodies[.search]?.1)
        let body = String(decoding: try XCTUnwrap(bodies[.barcode]?.1), as: UTF8.self)
        XCTAssertFalse(body.contains(Self.code), "the barcode is never sent")
    }

    func testABundledRowCaseSelectsTheAppSearchsCandidateForThatRecord() throws {
        let table = try CoFIDGenericFoodSearch(ids: RandomLedgerIDGenerator())
        let at = Date(timeIntervalSince1970: 1_795_000_000)
        let request = GenericFoodSearchRequest(text: try LedgerText("lentils boiled"), capturedAt: at, locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try table.search(request), let app = route.confirmation.candidates.first else {
            return XCTFail("the bundled CoFID table finds boiled lentils")
        }
        let candidates = EvalCandidates(tables: { _ in table })
        let input = try candidates.bundledInput(table: .cofid, search: "lentils boiled", recordID: app.candidate.recordID.value, retrievedAt: at)
        let chosen = try XCTUnwrap(input.candidates.first)
        XCTAssertEqual(input.candidates.count, 1)
        XCTAssertEqual(chosen.candidate.recordID, app.candidate.recordID)
        XCTAssertEqual(chosen.candidate.nutrients, app.candidate.nutrients)
        XCTAssertEqual(chosen.candidate.identity, app.candidate.identity)
        XCTAssertEqual(chosen.name, app.name)
        XCTAssertEqual(chosen.variant, app.variant)
        XCTAssertThrowsError(try candidates.bundledInput(table: .cofid, search: "lentils boiled", recordID: "cofid:absent", retrievedAt: at)) {
            XCTAssertEqual($0 as? EvalCandidates.Problem, .rowAbsent)
        }
    }

    // MARK: The gate and the key

    func testTheToolGatePermitsTheFourConfirmUsesOnly() {
        for use in OpenRouterUse.allCases {
            XCTAssertEqual(EvalGate().permits(use), EvalGate.uses.contains(use), "\(use)")
        }
        XCTAssertEqual(EvalGate.uses.count, 4)
    }

    func testTheEnvironmentKeyIsNeverShown() throws {
        let key = try EnvironmentKey(environment: [EnvironmentKey.variable: "sk-or-v1-0123456789abcdef0123456789abcdef"])
        XCTAssertFalse("\(key)".contains("sk-or"))
        XCTAssertFalse(String(reflecting: key).contains("sk-or"))
        XCTAssertThrowsError(try EnvironmentKey(environment: [:]))
    }
}
