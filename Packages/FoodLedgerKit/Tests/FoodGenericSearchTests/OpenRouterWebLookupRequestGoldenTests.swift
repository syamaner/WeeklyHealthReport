import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodGenericSearch
import FoodLedgerTestSupport
import XCTest

/// O1.6 test 3 (docs/openrouter-single-consent-v1-amendment.md): with OpenRouter turned on, every web
/// lookup request (method, address, timeout, headers and body bytes) equals the committed golden
/// captured from `main` before the consent gate was added. The key is replaced by `<key>`. Synthetic
/// data only. Set `RECORD_OPENROUTER_GOLDENS=1` to rewrite the fixture (a reviewed change).
final class OpenRouterWebLookupRequestGoldenTests: XCTestCase {
    private let key = "synthetic-golden-key-never-real-12345"

    func testEveryWebLookupRequestMatchesTheCommittedGolden() async throws {
        var captured: [String: [String: Any]] = [:]
        for (name, run) in try requests() {
            let box = RequestBox()
            let provider = makeProvider(name: name) { request in
                box.requests.append(request)
                return OpenRouterFoodHTTPReply(status: 500, data: Data())
            }
            _ = try? await run(provider)
            XCTAssertEqual(box.requests.count, 1, name)
            let request = try XCTUnwrap(box.requests.first, name)
            captured[name] = try canonical(request)
        }
        let data = try JSONSerialization.data(withJSONObject: captured, options: [.sortedKeys, .prettyPrinted])
        if ProcessInfo.processInfo.environment["RECORD_OPENROUTER_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: Self.fixture.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (data + Data("\n".utf8)).write(to: Self.fixture)
            return
        }
        let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.fixture)) as? [String: [String: Any]]
        let expected = try XCTUnwrap(golden)
        XCTAssertEqual(Set(expected.keys), Set(captured.keys))
        for (name, value) in captured {
            XCTAssertEqual(value as NSDictionary, expected[name] as NSDictionary?, name)
        }
    }

    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/openrouter-web-lookup-requests-v1.json")

    private func canonical(_ request: URLRequest) throws -> [String: Any] {
        var headers = request.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["Authorization"], "Bearer " + key)
        headers["Authorization"] = headers["Authorization"].map { $0.replacingOccurrences(of: key, with: "<key>") }
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) }
        XCTAssertFalse(body?.contains(key) == true)
        return ["method": request.httpMethod ?? "", "url": request.url?.absoluteString ?? "",
                "timeout": request.timeoutInterval, "headers": headers, "body": body as Any? ?? NSNull()]
    }

    private typealias Run = @Sendable (OpenRouterFoodProvider) async throws -> Void

    private func requests() throws -> [(String, Run)] {
        let key = self.key
        let document = try Self.document()
        let (milk, validation) = try Self.milkValidation()
        let leads = [FoodWebLead(title: "Plain yoghurt nutrition", url: URL(string: "https://example.com/yoghurt")!,
                                 citedText: "Per 100g energy 61kcal"),
                     FoodWebLead(title: "Yoghurt", url: URL(string: "https://example.org/yoghurt")!, citedText: nil)]
        return [
            ("keyValidation", { try await $0.validate(key: key) }),
            ("discovery", { _ = try await $0.discover(foodTerms: "Plain yoghurt [market: Taiwan]", key: key) }),
            ("leadSelection", { _ = try await $0.chooseSource(foodTerms: "Plain yoghurt", leads: leads, key: key) }),
            ("extraction", { _ = try await $0.extract(foodTerms: "Plain yoghurt", documents: [document], key: key) }),
            ("extractionGrok", { _ = try await $0.extract(foodTerms: "Plain yoghurt", documents: [document], key: key) }),
            ("applicability", { _ = try await $0.select(foodTerms: "Milk per 100ml", documents: [milk], validation: validation, key: key) }),
            ("jevSelection", { _ = try await $0.select(foodTerms: "Milk per 100ml", documents: [milk], validation: validation, key: key) })
        ]
    }

    private func makeProvider(name: String, transport: @escaping OpenRouterFoodProvider.Transport) -> OpenRouterFoodProvider {
        switch name {
        case "extractionGrok", "applicability":
            OpenRouterFoodProvider(egress: PermittingOpenRouterEgress(), extractionRoute: .grok, selectionRoute: .applicability, transport: transport)
        default:
            OpenRouterFoodProvider(egress: PermittingOpenRouterEgress(), transport: transport)
        }
    }

    private static func document() throws -> CapturedFoodDocument {
        try GenericFoodDocumentProjector.project(Data("<h1>Plain yoghurt</h1><p>Per 100g energy 61kcal</p>".utf8),
            url: URL(string: "https://example.com/yoghurt")!, mediaType: "text/html", retrievedAt: Date(timeIntervalSince1970: 0),
            origin: "synthetic_fixture")
    }

    static func milkValidation() throws -> (CapturedFoodDocument, FoodProposalValidation) {
        let text = "Milk Per 100ml Protein 3g"
        let document = try CapturedFoodDocument(id: "d1", url: "https://example.com/milk", rawSha256: String(repeating: "a", count: 64),
            captureOrigin: "synthetic", retrievedAt: "2026-10-04T00:00:00Z", blocks: [.init(id: "b1", kind: "p", text: text, locator: "p1")])
        let refs: [[String: Any]] = [["block_id": "b1", "quote": text]]
        let nutrients: [[String: Any]] = FoodProposalNutrientKey.allCases.map { key in
            ["key": key.rawValue, "state": key == .protein ? "declared" : "unknown",
             "value": key == .protein ? "3" as Any : NSNull(), "unit": key == .protein ? "g" as Any : NSNull(),
             "evidence": key == .protein ? refs : [], "unknown_reason": key == .protein ? NSNull() : "not_observed" as Any]
        }
        let candidate: [String: Any] = ["id": "c1", "document_id": "d1", "name": "Milk", "brand": NSNull(), "preparation": NSNull(),
            "identity_evidence": refs, "panel_evidence": refs, "basis": ["amount": "100", "unit": "ml", "label": "Per 100ml", "evidence": refs],
            "nutrients": nutrients, "limitations": []]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let extraction = try decoder.decode(FoodProposalExtraction.self, from: JSONSerialization.data(withJSONObject:
            ["version": FoodProposalExtraction.schemaVersion, "candidates": [candidate], "preferred_id": "c1"]))
        return (document, try FoodProposalBinding.validate(extraction, documents: [document]))
    }
}

private final class RequestBox: @unchecked Sendable {
    var requests: [URLRequest] = []
}
