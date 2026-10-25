import FoodLedgerApplication
import Foundation

/// The synthetic Taiwan label the fake route reads (docs/label-photo-ai-prefill-v1.md 14, L4).
/// Rendered on device by the UI target from `lines`; never a real photo. The scripted answer
/// reads two values differently from what is printed (protein per 100 g as 5.8, sodium per serving
/// as 90), so the locator cannot find them and Confirm shows two attention items.
public enum LabelPhotoSyntheticLabel {
    /// The printed table, one line per row: label, then each column's value.
    public static let lines: [[String]] = [
        ["營養標示"],
        ["每一份量30公克"],
        ["本包裝含10份"],
        ["", "每份", "每100公克"],
        ["熱量", "111大卡", "370大卡"],
        ["蛋白質", "1.6公克", "5.2公克"],
        ["脂肪", "2.0公克", "6.7公克"],
        ["碳水化合物", "18.0公克", "60.1公克"],
        ["鈉", "80毫克", "267毫克"],
    ]

    static func row(_ label: String, _ nutrient: String, _ perServing: String, _ per100: String) -> String {
        #"{"printed_label":"\#(label)","nutrient":"\#(nutrient)","parent_nutrient":"none","values":[{"header_id":"h1","printed_text":"\#(perServing)"},{"header_id":"h2","printed_text":"\#(per100)"}]}"#
    }

    /// The wire answer the scripted model gives for the label.
    public static let wireText: String = {
        let rows = [row("熱量", "energy_kcal", "111大卡", "370大卡"), row("蛋白質", "protein", "1.6公克", "5.8公克"),
                    row("脂肪", "fat", "2.0公克", "6.7公克"), row("碳水化合物", "carbohydrate", "18.0公克", "60.1公克"),
                    row("鈉", "sodium", "90毫克", "267毫克")]
        return #"{"declined":false,"decline_reasons":[],"language":"zh-Hant","serving_size_text":"每一份量30公克","servings_per_pack_text":"本包裝含10份","headers":[{"header_id":"h1","printed_text":"每份","basis":"per_serving"},{"header_id":"h2","printed_text":"每100公克","basis":"per_100g"}],"rows":["# + rows.joined(separator: ",") + "]}"
    }()

    /// A model decline for a label in another language.
    public static let languageDeclineWireText =
        #"{"declined":true,"decline_reasons":["unsupported_language"],"language":"unknown","serving_size_text":"unknown","servings_per_pack_text":"unknown","headers":[],"rows":[]}"#
}

/// A transport that never touches the network (L4: the route stays off until L5). It answers the
/// catalogue check and each image request from a script, for the simulator journeys selected by a
/// launch argument. It records nothing it is sent beyond a count.
public final class ScriptedLabelPhotoTransport: LabelPhotoHTTPTransporting, @unchecked Sendable {
    public enum Scenario: String, CaseIterable, Sendable {
        /// Two values not found on the photo.
        case answer
        /// A busy reply, then the answer: shows Retrying with the attempt count.
        case busyThenAnswer = "busy-then-answer"
        case declineLanguage = "decline-language"
        case timeout
        case keyRejected = "key-rejected"
        case quota
        case unusable
        case routeUnavailable = "route-unavailable"
        /// Waits until cancelled: Reading with Cancel.
        case slow
    }

    public let scenario: Scenario
    private let lock = NSLock()
    private var imageRequests = 0

    public init(scenario: Scenario) { self.scenario = scenario }

    public func send(_ request: LabelPhotoHTTPRequest, timeout: TimeInterval, maximumBodyBytes: Int) async throws -> LabelPhotoHTTPResponse {
        if request.method == "GET" { return try catalogue(request) }
        let attempt: Int = lock.withLock { imageRequests += 1; return imageRequests }
        switch scenario {
        case .answer: return Self.reply(Self.answer(LabelPhotoSyntheticLabel.wireText))
        case .busyThenAnswer:
            if attempt == 1 { return Self.reply(status: 503, ["error": ["code": 503, "message": "busy"]], headers: ["Retry-After": "1"]) }
            return Self.reply(Self.answer(LabelPhotoSyntheticLabel.wireText))
        case .declineLanguage: return Self.reply(Self.answer(LabelPhotoSyntheticLabel.languageDeclineWireText))
        case .timeout: throw LabelPhotoTransportError.timedOut
        case .keyRejected: return Self.reply(status: 401, ["error": ["code": 401, "message": "no"]])
        case .quota: return Self.reply(status: 429, ["error": ["code": 429, "message": "quota"]])
        case .unusable: return Self.reply(Self.answer(#"{"not":"the schema"}"#))
        case .routeUnavailable: return Self.reply(Self.answer(LabelPhotoSyntheticLabel.wireText))
        case .slow:
            do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { throw LabelPhotoTransportError.cancelled }
            return Self.reply(Self.answer(LabelPhotoSyntheticLabel.wireText))
        }
    }

    func catalogue(_ request: LabelPhotoHTTPRequest) throws -> LabelPhotoHTTPResponse {
        let route = LabelPhotoRoute.v1
        if request.url == OpenRouterLabelRouteChecker.zeroDataRetentionURL {
            let tag = scenario == .routeUnavailable ? "another-endpoint" : route.endpoint
            return Self.reply(["data": [["model_id": route.model, "tag": tag]]])
        }
        return Self.reply(["data": ["id": route.model, "architecture": ["input_modalities": ["text", "image"]],
                                    "endpoints": [["tag": route.endpoint, "provider_name": "Google Vertex",
                                                   "pricing": ["prompt": "0.000002", "completion": "0.00001"]]]]])
    }

    static func answer(_ wire: String) -> [String: Any] {
        ["id": "gen-scripted", "model": LabelPhotoRoute.v1.model, "provider": "Google Vertex",
         "choices": [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": wire]]],
         "usage": ["prompt_tokens": 2_100, "completion_tokens": 600, "cost": 0.01]]
    }

    static func reply(status: Int = 200, _ object: [String: Any], headers: [String: String] = [:]) -> LabelPhotoHTTPResponse {
        LabelPhotoHTTPResponse(status: status, headers: headers,
                               body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), exceededLimit: false)
    }
}
