import FoodLedgerApplication
import FoodLedgerDomain

/// Native display copy from accepted orchestration facts, never inferred provider activity.
public struct FoodSearchStatusPresentation: Equatable, Sendable {
    public let title: String
    public let summary: String
    public let details: [String]
    public let isSearching: Bool

    public init(reports: [FoodSearchStageReport], pending: FoodSearchStage?, stopped: Bool, services: FoodSearchServiceAvailability? = nil,
                configuredStages: [FoodSearchStage] = [.local, .onlineDatabase, .gemini]) {
        let count = reports.flatMap(\.addedCandidateIDs).count
        let online = reports.filter { $0.stage != .local }.flatMap(\.addedCandidateIDs).count
        let matches = "\(count) \(count == 1 ? "match" : "matches")"
        isSearching = pending != nil && !stopped
        if stopped {
            title = "Search stopped"
            summary = "\(matches) kept"
        } else if let pending {
            switch pending {
            case .local: title = "Searching on-device foods…"
            case .onlineDatabase: title = "Searching Open Food Facts…"
            case .gemini: title = "Checking web nutrition with Gemini…"
            }
            summary = count == 0 ? "Looking for a match" : "\(matches) ready to choose"
        } else {
            title = "Search finished"
            if let failed = reports.last(where: { $0.failure != nil }), let failure = failed.failure {
                summary = "\(Self.name(failed.stage)): \(Self.failureLabel(failure)) · \(matches) kept"
            } else if let last = reports.last, last.stage != .local, last.addedCandidateIDs.isEmpty {
                summary = "\(matches) · " + (last.hasSourceLinks || last.sourceReviewFailure != nil
                    ? "Web nutrition not verified" : "No extra matches from \(Self.name(last.stage))")
            } else {
                summary = matches + (online > 0 ? " · \(online) added online" : " · on device")
            }
        }
        // Omit providers that are not composed, while always retaining actual
        // activity/failures if a caller supplies historical reports.
        details = [FoodSearchStage.local, .onlineDatabase, .gemini].filter { stage in
            configuredStages.contains(stage) || pending == stage || reports.contains { $0.stage == stage }
        }.map { stage in
            let result: String
            if pending == stage && !stopped { result = "Searching" }
            else if let report = reports.first(where: { $0.stage == stage }) {
                if let failure = report.failure {
                    result = Self.failureLabel(failure)
                } else if report.addedCandidateIDs.isEmpty {
                    if let failure = report.sourceReviewFailure {
                        switch failure {
                        case .unsupportedSource: result = "Source found; website not supported"
                        case .invalidContent: result = "Source nutrition could not be verified"
                        case .unavailable: result = "Source page unavailable"
                        case .timedOut: result = "Source check timed out"
                        case .quotaExceeded: result = "Source check limit reached"
                        }
                    } else { result = report.hasSourceLinks ? "Source links found; no verified nutrition added" : "No extra matches" }
                } else {
                    let count = report.addedCandidateIDs.count
                    result = "\(count) \(stage == .local ? "" : "new ")\(count == 1 ? "match" : "matches")"
                }
            } else if stopped { result = pending == stage ? "Stopped" : "Not searched" }
            else if let services, stage != .local {
                let access = stage == .gemini ? services.gemini : services.onlineDatabase
                switch access {
                case .disabled: result = "Off"
                case .unavailable: result = stage == .gemini ? "Key needs validation" : "Unavailable"
                case .ready: result = "Not searched"
                }
            } else { result = "Not searched" }
            return "\(Self.name(stage)): \(result)"
        }
    }

    public static func failureLabel(_ failure: FoodSearchEnrichmentError) -> String {
        switch failure {
        case .credentialRejected: "Key needs validation"
        case .quotaExceeded: "Usage limit reached"
        case .permissionDenied: "Access unavailable"
        case .timedOut: "Search timed out"
        case .connectionFailed: "Connection failed"
        case .requestRejected: "Request rejected"
        case .invalidResponse: "Response could not be read"
        case .invalidQuery: "Search terms not accepted"
        case .unavailable: "Unavailable"
        }
    }

    public static func recoveryMessage(_ failure: FoodSearchEnrichmentError, stage: FoodSearchStage) -> String {
        let service = name(stage)
        switch failure {
        case .timedOut: return "\(service) timed out. You can search again."
        case .connectionFailed: return "\(service) could not connect. Check your connection and search again."
        case .unavailable: return "\(service) could not complete the search. You can try again."
        case .credentialRejected: return "\(service) rejected the API key. Revalidate it in Search settings."
        case .permissionDenied: return "\(service) refused access. Check your provider permissions."
        case .quotaExceeded: return "\(service) reached a usage limit. Check your provider quota before searching again."
        case .requestRejected: return "\(service) rejected the request or model. Check provider availability before searching again."
        case .invalidResponse: return "\(service) returned a response the app could not read. No nutrition was added from it."
        case .invalidQuery: return "\(service) did not accept these search terms. Review the description."
        }
    }

    public static func isRetryable(_ failure: FoodSearchEnrichmentError) -> Bool {
        switch failure {
        case .timedOut, .connectionFailed, .unavailable: true
        default: false
        }
    }

    public static func name(_ stage: FoodSearchStage) -> String {
        switch stage { case .local: "On-device foods"; case .onlineDatabase: "Open Food Facts"; case .gemini: "Gemini" }
    }
}

/// Only material selection cautions belong in a compact result row.
public enum FoodSearchResultText {
    public static func basisLabel(_ basis: ResolutionBasis) -> String {
        switch basis {
        case .per100Grams: "per 100 g"
        case .per100Millilitres: "per 100 mL"
        case let .perServing(quantity): "per serving (\(quantity.value.formatted()) \(quantity.unit.rawValue))"
        case let .perUnit(quantity): "per unit (\(quantity.value.formatted()) \(quantity.unit.rawValue))"
        case let .named(label, _): "per \(label.value)"
        case .unknown: "basis not specified"
        }
    }
    public static func caution(query: ParsedFoodQuery?, candidate: PopulatedFoodCandidate,
                               requestedPreparation: PreparationKind?, isRecipe: Bool) -> String? {
        if isRecipe { return "Representative recipe · cooked serving weight unknown" }
        guard let query else { return nil }
        var notes: [String] = []
        if let literal = query.attributes["unspecified_percent"] { notes.append("\(literal)% meaning needs review") }
        let requested = Set(GenericFoodRankingPolicy.terms(query.food ?? query.original))
        let actual = Set(GenericFoodRankingPolicy.terms(candidate.name.value))
        if requested.contains("greek"), requested.contains("style") != actual.contains("style") {
            notes.append(actual.contains("style") ? "Greek-style alternative" : "Greek yoghurt alternative")
        }
        if let percent = query.attributes["fat_percent"] {
            if let fat = FoodQueryCandidateAssessment.fatPer100Grams(candidate) {
                notes.append(FoodQueryCandidateAssessment.matchesFat(query: query, candidate: candidate)
                    ? "\(fat.formatted()) g fat / 100 g"
                    : "\(fat.formatted()) g fat / 100 g · requested \(percent)% fat")
            } else { notes.append("Requested \(percent)% fat not verified") }
        }
        if let preparation = requestedPreparation ?? FoodQueryPreparationPolicy.kind(for: query), preparation != .unknown,
           candidate.candidate.identity.preparation.kind == .unknown {
            notes.append("\(preparation.rawValue.capitalized) preparation not verified")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }
}
