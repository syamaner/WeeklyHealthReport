import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

/// What the composition root gives one Confirm for enrichment (docs/confirm-enrichment-openrouter-v1-phase.md
/// section 6): the app session, the switch and key state read, the Your food database fields and where
/// the Confirm came from. Nil on every route that does not wire it.
public struct ConfirmEnrichmentContext: Sendable {
    public let session: ConfirmEnrichmentSession
    public let preconditions: @Sendable () -> ConfirmEnrichmentSession.Preconditions
    public let database: (any PersonalFoodDatabaseEntryReading)?
    public let origin: ConfirmEnrichmentPolicy.Origin
    public let encoder: any CanonicalEncoding
    public let digester: any Digesting

    public init(session: ConfirmEnrichmentSession, preconditions: @escaping @Sendable () -> ConfirmEnrichmentSession.Preconditions,
                database: (any PersonalFoodDatabaseEntryReading)?, origin: ConfirmEnrichmentPolicy.Origin,
                encoder: any CanonicalEncoding = FoundationCanonicalJSONEncoder(), digester: any Digesting) {
        self.session = session; self.preconditions = preconditions; self.database = database; self.origin = origin
        self.encoder = encoder; self.digester = digester
    }
}

/// One Confirm's enrichment (CE1.1): after each change of state it works out A's and B's subjects,
/// starts a debounced request for a subject not yet asked, cancels a request whose subject changed,
/// and clears B rows whose subject changed (CE1.6 rule 6). It sends nothing on a reopened log, and a
/// Confirm opened by re-log or quick add reads the cache only. Log never waits on it.
@MainActor
public final class ConfirmEnrichmentController: ObservableObject {
    /// The parts with a request running ("Looking for suggestions…" with Stop).
    @Published public private(set) var loading: Set<ConfirmEnrichmentPart> = []
    /// The one quiet note of CE1 section 6.
    @Published public private(set) var note: String?
    /// O1's blocked row, shown only on the Ask again row.
    @Published public private(set) var blocked: OpenRouterBlockedReason?
    @Published public private(set) var tracker = ConfirmEnrichmentConfirmTracker()

    let context: ConfirmEnrichmentContext
    private let state: @MainActor () -> FoodConfirmationState
    private let apply: @MainActor (FoodConfirmationAction) -> Void
    private var tasks: [ConfirmEnrichmentPart: (subject: String, task: Task<Void, Never>)] = [:]
    private var stopped = false
    private var closed = false
    private var refreshing = false
    private var refreshAgain = false

    init(context: ConfirmEnrichmentContext, state: @escaping @MainActor () -> FoodConfirmationState,
         apply: @escaping @MainActor (FoodConfirmationAction) -> Void) {
        self.context = context; self.state = state; self.apply = apply
    }

    // MARK: Requests

    struct Plan {
        var details: (ConfirmEnrichmentPolicy.DetailsRequest, PersonalFoodDatabaseState?)?
        var nutrients: ConfirmEnrichmentPolicy.NutrientRequest?
        var detailsSettled: Bool
    }

    private func routeAndFields(_ state: FoodConfirmationState) -> (ConfirmEnrichmentPolicy.SourceRoute, PersonalFoodDescriptionFields?)? {
        guard state.reopened == nil,
              let route = ConfirmEnrichmentPolicy.sourceRoute(state.input, candidate: state.selectedCandidate) else { return nil }
        let fields = route == .yourFoodDatabase ? context.database?.descriptionFields(recordID: state.selectedCandidate.candidate.recordID) : nil
        if route == .yourFoodDatabase, fields == nil { return nil }
        return (route, fields)
    }

    func plan(_ state: FoodConfirmationState) -> Plan? {
        guard let (route, fields) = routeAndFields(state) else { return nil }
        let routes = context.session.routeValues
        let description = ConfirmEnrichmentPolicy.description(route, candidate: state.selectedCandidate, database: fields)
        var plan = Plan(details: nil, nutrients: nil, detailsSettled: true)
        if state.enrichment.details == nil, !state.enrichment.detailsFolded,
           let asked = ConfirmEnrichmentPolicy.detailsQuestions(state, route: route, database: fields),
           let inputs = try? ConfirmDetailsRequestInputs(
               description: description, knownDetails: ConfirmEnrichmentPolicy.knownDetails(state.selectedCandidate.candidate.identity),
               asked: asked),
           let request = try? ConfirmEnrichmentPolicy.detailsRequest(inputs, route: routes.details, encoder: context.encoder,
                                                                     digester: context.digester) {
            plan.details = (request, fields?.state.flatMap(PersonalFoodDatabaseState.init(rawValue:)) ?? (fields == nil ? nil : .unknown))
            // B waits until A has returned, failed or is not needed.
            plan.detailsSettled = tracker.asked[.details]?.contains(request.subjectSHA256) == true && tasks[.details] == nil
        }
        if let inputs = ConfirmEnrichmentPolicy.nutrientInputs(state, route: route, description: description,
                                                              identity: state.enrichedIdentity,
                                                              labelLayerKeys: Set(state.enrichment.labelLayer.keys)) {
            plan.nutrients = try? ConfirmEnrichmentPolicy.nutrientRequest(inputs, route: routes.nutrients, encoder: context.encoder,
                                                                         digester: context.digester)
        }
        return plan
    }

    private var mode: ConfirmEnrichmentSession.Mode { context.origin == .fresh ? .automatic : .cacheOnly }

    /// Called after every change of the Confirm state.
    public func refresh() {
        guard !closed else { return }
        // A change made while refreshing (clearing B rows) refreshes once more afterwards.
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            refreshOnce()
        } while refreshAgain
    }

    private func refreshOnce() {
        let state = state()
        let preconditions = context.preconditions()
        guard let plan = plan(state) else {
            cancelAll()
            return
        }
        // B's subject changed after it answered: its rows are cleared and it may be asked again.
        if let rows = state.enrichment.nutrients, rows.subjectSHA256 != plan.nutrients?.subjectSHA256 {
            apply(.clearNutrientSuggestion)
        }
        for part in ConfirmEnrichmentPart.allCases {
            let subject = part == .details ? plan.details?.0.subjectSHA256 : plan.nutrients?.subjectSHA256
            if let running = tasks[part], running.subject != subject {
                running.task.cancel()
                tasks[part] = nil
                loading.remove(part)
            }
        }
        guard !stopped, context.session.mayRun(.details, preconditions: preconditions)
                || context.session.mayRun(.nutrients, preconditions: preconditions) else { return }
        if let (request, entryState) = plan.details, tasks[.details] == nil,
           context.session.mayRun(.details, preconditions: preconditions),
           tracker.mayAskAutomatically(.details, subject: request.subjectSHA256) {
            startDetails(request, entryState: entryState, mode: mode, preconditions: preconditions, debounced: mode == .automatic)
        }
        if plan.detailsSettled, tasks[.details] == nil, let request = plan.nutrients, tasks[.nutrients] == nil,
           state.enrichment.nutrients == nil, context.session.mayRun(.nutrients, preconditions: preconditions),
           tracker.mayAskAutomatically(.nutrients, subject: request.subjectSHA256) {
            startNutrients(request, mode: mode, preconditions: preconditions, debounced: mode == .automatic)
        }
    }

    /// Whether the Ask again row is offered for `part` (once a subject was asked; never on a Confirm
    /// opened by re-log or quick add).
    public func offersAskAgain(_ part: ConfirmEnrichmentPart) -> Bool {
        context.origin == .fresh && tracker.offersAskAgain(part) && tasks[part] == nil
    }

    public func askAgain(_ part: ConfirmEnrichmentPart) {
        guard offersAskAgain(part), let plan = plan(state()) else { return }
        let preconditions = context.preconditions()
        if !preconditions.openRouterOn { blocked = .switchOff; return }
        switch preconditions.keyState {
        case .missing: blocked = .noKey; return
        case .notValidated: blocked = .keyNotValidated; return
        case .valid: blocked = nil
        }
        stopped = false
        switch part {
        case .details:
            if let (request, entryState) = plan.details {
                startDetails(request, entryState: entryState, mode: .askAgain, preconditions: preconditions, debounced: false)
            }
        case .nutrients:
            if let request = plan.nutrients { startNutrients(request, mode: .askAgain, preconditions: preconditions, debounced: false) }
        }
    }

    /// Stop: cancels and sends nothing more until Ask again.
    public func stop() {
        stopped = true
        cancelAll()
    }

    /// Confirm closed: anything in flight is cancelled and its answer discarded.
    public func confirmClosed() {
        closed = true
        cancelAll()
    }

    public func appBecameInactive() {
        cancelAll()
        Task { await context.session.appBecameInactive() }
    }

    public func appBecameActive() {
        Task {
            await context.session.appBecameActive()
            refresh()
        }
    }

    private func cancelAll() {
        for (_, running) in tasks { running.task.cancel() }
        tasks = [:]
        loading = []
    }

    private func locale(_ state: FoodConfirmationState) -> LedgerText {
        ConfirmEnrichmentCaptureBuilder.locale(state.selectedCandidate.candidate, evidence: state.input.evidence)
    }

    private func finish(_ part: ConfirmEnrichmentPart, failure: ConfirmEnrichmentSession.Failure?, mode: ConfirmEnrichmentSession.Mode) {
        tasks[part] = nil
        loading.remove(part)
        guard let failure else { return }
        if mode == .askAgain, failure == .notPermitted || failure == .notPermittedAfterSending { blocked = .switchOff }
        if let text = ConfirmEnrichmentText.note(failure) { note = text }
    }

    private func startDetails(_ request: ConfirmEnrichmentPolicy.DetailsRequest, entryState: PersonalFoodDatabaseState?,
                              mode: ConfirmEnrichmentSession.Mode, preconditions: ConfirmEnrichmentSession.Preconditions, debounced: Bool) {
        let session = context.session
        let locale = locale(state())
        let task = Task { [weak self] in
            if debounced, await !session.debounce() { return }
            guard !Task.isCancelled else { return }
            self?.tracker.recordAsked(.details, subject: request.subjectSHA256)
            if mode != .cacheOnly { self?.loading.insert(.details) }
            let outcome = await session.details(request, mode: mode, preconditions: preconditions, locale: locale, entryState: entryState)
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case let .answered(suggestion):
                self.finish(.details, failure: nil, mode: mode)
                if !suggestion.applied.isEmpty { self.apply(.applyDetailsSuggestion(suggestion)) }
            case let .failed(failure):
                self.finish(.details, failure: failure, mode: mode)
            }
            self.refresh()
        }
        tasks[.details] = (request.subjectSHA256, task)
    }

    private func startNutrients(_ request: ConfirmEnrichmentPolicy.NutrientRequest, mode: ConfirmEnrichmentSession.Mode,
                                preconditions: ConfirmEnrichmentSession.Preconditions, debounced: Bool) {
        let session = context.session
        let locale = locale(state())
        let task = Task { [weak self] in
            if debounced, await !session.debounce() { return }
            guard !Task.isCancelled else { return }
            self?.tracker.recordAsked(.nutrients, subject: request.subjectSHA256)
            if mode != .cacheOnly { self?.loading.insert(.nutrients) }
            let outcome = await session.nutrients(request, mode: mode, preconditions: preconditions, locale: locale)
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case let .answered(suggestion):
                self.finish(.nutrients, failure: nil, mode: mode)
                // The subject still holds: a late answer for an older subject is discarded.
                if self.plan(self.state())?.nutrients?.subjectSHA256 == suggestion.subjectSHA256,
                   suggestion.rows.contains(where: { $0.result == ConfirmNutrientRowResult.kept.rawValue }) {
                    self.apply(.applyNutrientSuggestion(suggestion))
                }
            case let .failed(failure):
                self.finish(.nutrients, failure: failure, mode: mode)
            }
        }
        tasks[.nutrients] = (request.subjectSHA256, task)
    }
}
