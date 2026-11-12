import Foundation
import FoodLedgerDomain

/// The decoded active Your food database, loaded off the main thread (phase 1 plan section 5.1
/// item 7). Search reads the current snapshot under a short lock and never waits for a load.
public final class PersonalFoodDatabaseIndex: @unchecked Sendable {
    public struct Snapshot: Sendable {
        public let file: PersonalFoodDatabaseFile
        public let release: SourceRelease
        /// References whose corpus hash differs from the app's pin or whose record is missing.
        public let unresolvedReferenceCount: Int
        let terms: [EntryTerms]
    }

    struct EntryTerms: Sendable {
        let names: [(alias: String, terms: Set<String>)]
        let variety: Set<String>
        let concept: Set<String>
    }

    private enum Loaded { case none, damaged, ready(Snapshot) }

    private let store: any PersonalFoodDatabaseStoring
    private let resolver: any GenericRecordResolving
    private let lock = NSLock()
    private var generation = 0
    private var loaded: Loaded?

    public init(store: any PersonalFoodDatabaseStoring, resolver: any GenericRecordResolving) {
        self.store = store
        self.resolver = resolver
    }

    /// The current snapshot, or nil when none is installed, the store is locked or damaged, or the
    /// index has not been warmed yet.
    public func snapshot() -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        if case let .ready(snapshot) = loaded { return snapshot }
        return nil
    }

    /// Drops the current snapshot; a load already running cannot install a stale release.
    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        loaded = nil
    }

    /// Loads the active release when nothing is cached. Call it off the main thread. A locked store
    /// is never cached; damaged and none are cached until the next `invalidate()`.
    public func warm() {
        let start: Int
        lock.lock()
        if loaded != nil { lock.unlock(); return }
        start = generation
        lock.unlock()
        let result: Loaded
        do {
            if let installed = try store.activeRelease() {
                result = Self.load(installed, resolver: resolver).map(Loaded.ready) ?? .damaged
            } else {
                result = .none
            }
        } catch PersonalFoodDatabaseStoreError.locked {
            return
        } catch {
            result = .damaged
        }
        lock.lock(); defer { lock.unlock() }
        if generation == start, loaded == nil { loaded = result }
    }

    static func load(_ installed: PersonalFoodDatabaseInstalledRelease, resolver: any GenericRecordResolving) -> Snapshot? {
        guard case let .success(file) = PersonalFoodDatabaseCodec.decode(installed.bytes),
              let release = try? PersonalFoodDatabaseRelease.sourceRelease(
                  fileSHA256: installed.manifest.fileSHA256, generated: installed.manifest.generated),
              release.sourceReleaseID.value == installed.manifest.releaseID else { return nil }
        let unresolved = file.entries.reduce(0) { count, entry in
            guard let reference = entry.genericReference else { return count }
            return resolver.contains(GenericRecordReference(reference)) ? count : count + 1
        }
        let terms = file.entries.map { entry in
            EntryTerms(
                names: ([entry.title] + entry.titles + entry.aliases).map { ($0, Set(GenericFoodRankingPolicy.terms($0))) },
                variety: Set(entry.variety.map(GenericFoodRankingPolicy.terms) ?? []),
                concept: Set(entry.concept.map(GenericFoodRankingPolicy.terms) ?? []))
        }
        return Snapshot(file: file, release: release, unresolvedReferenceCount: unresolved, terms: terms)
    }
}

/// Your food database as a search source (import v1 section 5; phase 1 plan section 5). It never
/// throws into the composite and its no-result carries no guidance; the composite ignores it.
public struct PersonalFoodDatabaseFoodSearch: GenericFoodSearching {
    public static let maximumEntries = 10
    private let index: PersonalFoodDatabaseIndex
    private let resolver: any GenericRecordResolving
    private let ids: any LedgerIDGenerating

    public init(index: PersonalFoodDatabaseIndex, resolver: any GenericRecordResolving, ids: any LedgerIDGenerating) {
        self.index = index
        self.resolver = resolver
        self.ids = ids
    }

    public func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try request.captureEvidence ?? CaptureEvidence(
            evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: request.capturedAt,
            locale: request.locale, captureMethod: LedgerText("typed_generic_food_search"),
            captureMethodVersion: LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion),
            originalPayload: .text(request.text))
        let miss = GenericFoodSearchOutcome.noResult(
            GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence))
        guard let snapshot = index.snapshot() else { return miss }
        do {
            return try route(request, snapshot: snapshot, evidence: [evidence] + request.additionalEvidence) ?? miss
        } catch {
            return miss
        }
    }

    struct Hit {
        let entry: PersonalFoodDatabaseEntry
        let step: PersonalFoodDatabaseMatchContext.Step
        let alias: String
        let exact: Bool
        let preference: GenericFoodRankingPolicy.Preference
    }

    /// Steps: title or alias, then variety, then concept; the best step wins per entry. Order: step,
    /// then `GenericFoodRankingPolicy.preference`, then entry ID (section 5.1 item 6).
    static func hits(_ request: GenericFoodSearchRequest, snapshot: PersonalFoodDatabaseIndex.Snapshot) -> [Hit] {
        let query = Set(GenericFoodRankingPolicy.terms(request.retrievalText))
        guard !query.isEmpty else { return [] }
        var hits: [Hit] = []
        for (entry, terms) in zip(snapshot.file.entries, snapshot.terms) {
            let step: PersonalFoodDatabaseMatchContext.Step
            var alias = entry.title
            var exact = false
            if let name = terms.names.first(where: { query.isSubset(of: $0.terms) }) {
                step = .titleOrAlias
                alias = name.alias
                exact = terms.names.contains { $0.terms == query }
            } else if !terms.variety.isEmpty, query.isSubset(of: terms.variety) {
                step = .variety
            } else if !terms.concept.isEmpty, query.isSubset(of: terms.concept) {
                step = .concept
            } else { continue }
            hits.append(Hit(entry: entry, step: step, alias: alias, exact: exact,
                preference: GenericFoodRankingPolicy.preference(name: entry.title, food: request.retrievalText,
                                                                requestedText: request.text.value)))
        }
        return hits.sorted { a, b in
            if a.step != b.step { return a.step < b.step }
            if a.preference != b.preference { return GenericFoodRankingPolicy.prefers(a.preference, over: b.preference) }
            return a.entry.id < b.entry.id
        }
    }

    private func route(_ request: GenericFoodSearchRequest, snapshot: PersonalFoodDatabaseIndex.Snapshot,
                       evidence: [CaptureEvidence]) throws -> GenericFoodSearchOutcome? {
        guard Set(evidence.map(\.evidenceID)).count == evidence.count else { return nil }
        let evidenceIDs = evidence.map(\.evidenceID)
        var matches: [GenericFoodMatch] = []
        var releases: [SourceRelease] = []
        func add(_ release: SourceRelease) throws {
            if let existing = releases.first(where: { $0.sourceReleaseID == release.sourceReleaseID }) {
                guard existing == release else { throw FoodLedgerValidationError.duplicateValue("source release identity") }
            } else { releases.append(release) }
        }
        var used = 0
        for hit in Self.hits(request, snapshot: snapshot) where used < Self.maximumEntries {
            let record = hit.entry.genericReference.flatMap {
                resolver.resolve(GenericRecordReference($0), evidenceIDs: evidenceIDs, queryAlias: hit.alias)
            }
            // One entry that cannot be represented is left out on its own; the others still answer.
            let built: PersonalFoodDatabaseCandidateBuilder.Built?
            do {
                built = try PersonalFoodDatabaseCandidateBuilder.build(entry: hit.entry, file: snapshot.file,
                    databaseRelease: snapshot.release, record: record, evidenceIDs: evidenceIDs, score: Self.score(hit))
            } catch { continue }
            // A referenced record that was not merged is offered as its own row, after the entry, once:
            // two entries naming the same record never give two rows for it.
            let generic = built?.merged == true ? nil : record.flatMap { resolved in
                matches.contains { $0.searchID.recordID == resolved.candidate.candidate.recordID
                    && $0.searchID.sourceReleaseID == resolved.candidate.candidate.sourceReleaseID } ? nil : resolved
            }
            guard built != nil || generic != nil else { continue }
            var rows: [GenericFoodMatch] = []
            var cited: [SourceRelease] = []
            if let built {
                cited += built.releases
                rows.append(GenericFoodMatch(candidate: built.candidate, isExactName: hit.exact,
                    personalDatabase: PersonalFoodDatabaseMatchContext(step: hit.step, isGenericReference: false)))
            }
            if let generic {
                cited.append(generic.release)
                // Exact when the record's own name, folded, is the query (as the adapters judge it).
                let exact = Set(GenericFoodRankingPolicy.terms(generic.candidate.name.value))
                    == Set(GenericFoodRankingPolicy.terms(request.retrievalText))
                rows.append(GenericFoodMatch(candidate: generic.candidate, isExactName: exact,
                    personalDatabase: PersonalFoodDatabaseMatchContext(step: hit.step, isGenericReference: true)))
            }
            let before = releases
            do { for release in cited { try add(release) } } catch { releases = before; continue }
            used += 1
            matches += rows
        }
        guard let first = matches.first else { return nil }
        return .confirmation(GenericFoodConfirmationRoute(confirmation: try PopulatedFoodConfirmation(
            evidence: evidence, sourceReleases: releases, candidates: matches.map(\.candidate),
            expectedIdentity: first.candidate.candidate.identity,
            expectedEdibleQuantity: first.candidate.candidate.edibleQuantity), matches: matches))
    }

    /// Presentation only; never compared with another source's score.
    static func score(_ hit: Hit) -> Double {
        switch hit.step {
        case .titleOrAlias: hit.exact ? 1 : 0.9
        case .variety: 0.7
        case .concept: 0.5
        }
    }
}

/// Re-resolution against the active Your food database (phase 1 plan section 5.1 item 1). The only
/// target is the active release under `pfc-resolution-v1`; a saved log is matched by its entry ID.
/// With no database installed there is no target, so the service reports `unavailableTarget`.
public struct PersonalFoodDatabaseReresolutionProvider: FoodReresolutionProviding {
    private let index: PersonalFoodDatabaseIndex
    private let resolver: any GenericRecordResolving
    private let ids: any LedgerIDGenerating

    public init(index: PersonalFoodDatabaseIndex, resolver: any GenericRecordResolving, ids: any LedgerIDGenerating) {
        self.index = index
        self.resolver = resolver
        self.ids = ids
    }

    public func targets() throws -> [FoodReresolutionTarget] {
        guard let snapshot = index.snapshot() else { return [] }
        return [FoodReresolutionTarget(sourceRelease: snapshot.release,
                                       methodVersion: try LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion))]
    }

    public func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at date: Date) throws -> GenericFoodSearchOutcome {
        guard let snapshot = index.snapshot(), try targets().contains(target) else { throw FoodReresolutionError.unavailableTarget }
        let evidence = try CaptureEvidence(evidenceID: ids.makeID(EvidenceTag.self), kind: .genericSearch, capturedAt: date,
            locale: LedgerText("en_GB"), captureMethod: LedgerText("personal_food_database_reresolution"),
            captureMethodVersion: LedgerText(PersonalFoodDatabaseCandidateBuilder.methodVersion),
            originalPayload: .text(record.productVersion.name))
        let entryID = record.candidateDecision.candidate.recordID.value
        guard let entry = snapshot.file.entries.first(where: { $0.id == entryID }),
              let built = try PersonalFoodDatabaseCandidateBuilder.build(
                  entry: entry, file: snapshot.file, databaseRelease: snapshot.release,
                  record: entry.genericReference.flatMap {
                      resolver.resolve(GenericRecordReference($0), evidenceIDs: [evidence.evidenceID], queryAlias: entry.title)
                  },
                  evidenceIDs: [evidence.evidenceID], score: 1) else {
            return .noResult(GenericFoodNoResultRoute(evidence: evidence))
        }
        return .confirmation(GenericFoodConfirmationRoute(confirmation: try PopulatedFoodConfirmation(
            evidence: [evidence], sourceReleases: built.releases, candidates: [built.candidate],
            expectedIdentity: built.candidate.candidate.identity, expectedEdibleQuantity: built.candidate.candidate.edibleQuantity),
            matches: [GenericFoodMatch(candidate: built.candidate, isExactName: true,
                personalDatabase: PersonalFoodDatabaseMatchContext(step: .titleOrAlias, isGenericReference: false))]))
    }
}

/// Several re-resolution providers behind the service's single port; each target goes to the
/// provider that lists it.
public struct FoodReresolutionProviderSet: FoodReresolutionProviding {
    private let providers: [any FoodReresolutionProviding]

    public init(_ providers: [any FoodReresolutionProviding]) { self.providers = providers }

    public func targets() throws -> [FoodReresolutionTarget] { try providers.flatMap { try $0.targets() } }

    public func candidates(for record: StoredFoodConfirmation, target: FoodReresolutionTarget, at date: Date) throws -> GenericFoodSearchOutcome {
        for provider in providers where try provider.targets().contains(target) {
            return try provider.candidates(for: record, target: target, at: date)
        }
        throw FoodReresolutionError.unavailableTarget
    }
}
