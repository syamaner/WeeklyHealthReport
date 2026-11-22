#if DEBUG
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

// Debug-only scripted Confirm enrichment (docs/confirm-enrichment-openrouter-v1-phase.md section 6, "The
// Debug scripted journey"). Everything in this file is compiled only in Debug builds: the scripted gate,
// the scripted adapters and route checker, the in-memory cache and day ledger, and the scripted key
// state. The composition root builds them only together, under the `-ConfirmEnrichmentRoute scripted`
// launch argument, and never beside a live adapter. Nothing here makes a network call or holds a key.

/// Permits the four Confirm enrichment uses only while both switches are on, and nothing else.
public struct ScriptedConfirmEnrichmentGate: OpenRouterEgressPermitting {
    public static let uses: Set<OpenRouterUse> = [
        .confirmEnrichmentDetails, .confirmEnrichmentNutrients,
        .confirmEnrichmentDetailsCatalogueCheck, .confirmEnrichmentNutrientsCatalogueCheck,
    ]
    private let openRouterOn: @Sendable () -> Bool
    private let enrichmentOn: @Sendable () -> Bool

    public init(openRouterOn: @escaping @Sendable () -> Bool, enrichmentOn: @escaping @Sendable () -> Bool) {
        self.openRouterOn = openRouterOn; self.enrichmentOn = enrichmentOn
    }

    public func permits(_ use: OpenRouterUse) -> Bool {
        Self.uses.contains(use) && openRouterOn() && enrichmentOn()
    }
}

/// The scripted branch's key state: valid, holding no key (as O1's scripted label photo mode).
public enum ScriptedConfirmEnrichmentKeySource {
    public static let state: OpenRouterKeyState = .valid
}

/// Scripted A answers: a fixed, confident choice for each asked fact, naming the live route's model and
/// provider so the response checks pass.
public struct ScriptedFoodDetailsSuggester: FoodDetailsSuggesting {
    public static let choices: [String: (String, Double)] = [
        "preparation": ("as_sold", 0.95), "bone": ("not_applicable", 0.95), "skin": ("not_applicable", 0.95),
        "drained": ("not_applicable", 0.92), "packing_medium": ("as sold", 0.9), "fortification": ("unfortified", 0.9),
    ]
    private let egress: any OpenRouterEgressPermitting
    private let route: ConfirmEnrichmentRoute

    public init(egress: any OpenRouterEgressPermitting, route: ConfirmEnrichmentRoute = ConfirmEnrichmentRoutes.details) {
        self.egress = egress; self.route = route
    }

    public func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult {
        guard egress.permits(.confirmEnrichmentDetails) else { return .notSent(.notPermitted) }
        guard !Task.isCancelled else { return .notSent(.cancelled) }
        guard let inputs = ConfirmDetailsRequestInputs.decode(requestBody: String(decoding: body, as: UTF8.self)) else {
            return .sent(status: 400, body: Data(), retryAfter: nil)
        }
        var answers: [String: Any] = [:]
        for fact in inputs.asked {
            let (choice, confidence) = Self.choices[fact.rawValue] ?? ("unknown", 0.5)
            answers[fact.rawValue] = ["type": "choice", "choice": choice, "confidence": confidence, "probabilities": [choice: confidence]]
        }
        let reply: [String: Any] = ["id": "gen-scripted-details", "model": route.model, "provider": route.provider, "answers": answers,
                                    "usage": ["cost": 0.0004, "input_tokens": 300]]
        let bytes = (try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])) ?? Data()
        return .sent(status: 200, body: bytes, retryAfter: nil)
    }
}

/// Scripted B answers: one plausible value for each eligible key outside energy and the macronutrients,
/// so the scripted journey shows kept rows with `est.` and Leave out.
public struct ScriptedNutrientEstimateSuggester: NutrientEstimateSuggesting {
    public static let values: [String: Double] = [
        "fiber": 3.1, "sodium": 120, "sugar": 0.5, "fat_saturated": 0.4, "fat_monounsaturated": 0.3, "fat_polyunsaturated": 0.2,
        "calcium": 45, "iron": 1.2, "potassium": 180, "magnesium": 20, "vitamin_c": 2,
    ]
    private let egress: any OpenRouterEgressPermitting
    private let route: ConfirmEnrichmentRoute

    public init(egress: any OpenRouterEgressPermitting, route: ConfirmEnrichmentRoute = ConfirmEnrichmentRoutes.nutrients) {
        self.egress = egress; self.route = route
    }

    public func attempt(_ body: Data, timeout: TimeInterval) async -> ConfirmEnrichmentAttemptResult {
        guard egress.permits(.confirmEnrichmentNutrients) else { return .notSent(.notPermitted) }
        guard !Task.isCancelled else { return .notSent(.cancelled) }
        guard let inputs = ConfirmNutrientRequestInputs.decode(requestBody: String(decoding: body, as: UTF8.self)) else {
            return .sent(status: 400, body: Data(), retryAfter: nil)
        }
        let rows: [[String: Any]] = inputs.eligible.compactMap { eligible in
            Self.values[eligible.nutrient].map { ["nutrient": eligible.nutrient, "value": $0, "unit": eligible.unit] }
        }
        let content = (try? JSONSerialization.data(withJSONObject: [
            "schema": ConfirmEnrichmentVersions.nutrientSchema, "basis": inputs.basis.rawValue, "values": rows,
        ], options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let reply: [String: Any] = [
            "id": "gen-scripted-nutrients", "model": route.model, "provider": route.provider,
            "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": content]]],
            "usage": ["cost": 0.0011, "prompt_tokens": 600],
        ]
        let bytes = (try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])) ?? Data()
        return .sent(status: 200, body: bytes, retryAfter: nil)
    }
}

/// A scripted route check that asks the gate for the catalogue use, as the live checker does before
/// each fetch, and passes at prices well inside both caps.
public struct ScriptedConfirmEnrichmentRouteChecker: ConfirmEnrichmentRouteChecking {
    public static let prices = ConfirmEnrichmentPrices(promptPerTokenUSD: Decimal(string: "0.0000002")!,
                                                       completionPerTokenUSD: Decimal(string: "0.0000008")!)
    private let egress: any OpenRouterEgressPermitting

    public init(egress: any OpenRouterEgressPermitting) { self.egress = egress }

    public func check(_ part: ConfirmEnrichmentPart, catalogueUse: OpenRouterUse) async -> ConfirmEnrichmentRouteCheckResult {
        guard egress.permits(catalogueUse) else { return .notPermitted }
        return .passed(Self.prices)
    }
}

/// The scripted branch's cache, kept in memory under the same policy, so a scripted answer is never a
/// hit for a live request.
public final class InMemoryConfirmEnrichmentCache: ConfirmEnrichmentCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [ConfirmEnrichmentCachedAnswer] = []

    public init() {}

    public func answer(subject: String, part: ConfirmEnrichmentPart, now: Date) -> ConfirmEnrichmentCachedAnswer? {
        lock.withLock { ConfirmEnrichmentCachePolicy.lookup(answers, subject: subject, part: part, now: now) }
    }

    public func store(_ answer: ConfirmEnrichmentCachedAnswer, now: Date) {
        lock.withLock { answers = ConfirmEnrichmentCachePolicy.storing(answer, in: answers, now: now) }
    }

    public func remove(subject: String, part: ConfirmEnrichmentPart) {
        lock.withLock { answers = ConfirmEnrichmentCachePolicy.removing(subject: subject, part: part, from: answers) }
    }

    public func clear() { lock.withLock { answers = [] } }
}

/// The scripted branch's day record, kept in memory, so scripted requests never use up or pause the
/// live day.
public final class InMemoryConfirmEnrichmentDayLedger: ConfirmEnrichmentSpendLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ConfirmEnrichmentSpendPolicy.Stored

    public init(_ stored: ConfirmEnrichmentSpendPolicy.Stored = .absent) { self.stored = stored }

    public func read() -> ConfirmEnrichmentSpendPolicy.Stored { lock.withLock { stored } }

    @discardableResult
    public func update(_ transform: (ConfirmEnrichmentSpendPolicy.Stored) throws -> ConfirmEnrichmentSpendPolicy.Day) throws
        -> ConfirmEnrichmentSpendPolicy.Day {
        try lock.withLock {
            let day = try transform(stored)
            stored = .day(day)
            return day
        }
    }
}
#endif
