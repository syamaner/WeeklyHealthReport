import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// `composite-generic-ranking-v11` and `cocoa-percent-policy-v2` contract tests
/// (docs/ciqual-2025-admission-v1.md sections 4.2 and 5, Architecture gate). Synthetic query
/// text plus the pinned corpora.
final class CiqualCompositeContractTests: XCTestCase {
    private static let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let repositoryRoot = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
    private static let ciqualPrefix = "ciqual:2025-11-19:sha256:"
    private static let syntheticPrefix = "synthetic-reference:"

    // MARK: Subsequence property

    /// For every FoodSearchQuality v3 to v8 query and "dark chocolate p%" (p from 1 to 100 in
    /// 0.5 steps), with Taiwan promoted and not, removing the Ciqual rows from the v11 output gives
    /// the v10 output exactly. The sweep is repeated with a synthetic reference row banded at 90%
    /// (with and without Ciqual) to prove the per-group tier keys; the scenario queries have no
    /// cocoa request, so the synthetic variants are run on the sweep only (CI time, #384 review M1).
    func testRemovingReferenceRowsFromV11GivesV10ForEveryRequest() throws {
        let ids = RandomLedgerIDGenerator()
        // The searchers hold no mutable state and every request carries its capture evidence, so
        // queries are compared concurrently; each query has its own cache (CI time, review M1).
        let cofid = try CoFIDGenericFoodSearch(ids: ids), usda = try USDAGenericFoodSearch(ids: ids)
        let tfda = try TFDAGenericFoodSearch(ids: ids), ciqual = try CiqualGenericFoodSearch(ids: ids)
        struct Query { let text: String; let preparation: String?; var sweep = false }
        var queries: [Query] = []
        for version in 3...8 {
            let url = Self.repositoryRoot.appendingPathComponent("Tools/FoodSearchQuality/retrieval-scenarios-v\(version).json")
            let fixture = try JSONDecoder().decode(RankedRetrievalDevelopmentTests.Fixture.self, from: Data(contentsOf: url))
            for scenario in fixture.cases where !queries.contains(where: { $0.text == scenario.query && $0.preparation == scenario.preparation }) {
                queries.append(Query(text: scenario.query, preparation: scenario.preparation))
            }
        }
        for step in 2...200 {
            let p = Double(step) / 2
            queries.append(Query(text: "dark chocolate \(p.rounded() == p ? String(Int(p)) : String(p))%", preparation: nil, sweep: true))
        }
        struct Tally { var failures: [String] = []; var compared = 0; var ciqualOnly = 0; var syntheticShown = 0 }
        func compare(_ query: Query, index: Int) throws -> Tally {
            var tally = Tally()
            func check(_ condition: Bool, _ message: String) { if !condition { tally.failures.append(message) } }
            let shared = (cofid: Memo(cofid), usda: Memo(usda), tfda: Memo(tfda), ciqual: Memo(ciqual))
            let synthetic = SyntheticNinetyPercentReference(inner: shared.ciqual)
            let evidence = try CaptureEvidence(evidenceID: LedgerID(String(format: "00000000-0000-0000-0000-%012x", index + 1)), kind: .genericSearch,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"),
                captureMethod: LedgerText("typed_generic_food_search"), captureMethodVersion: LedgerText(CompositeGenericFoodSearch.version),
                originalPayload: .text(LedgerText(query.text)))
            let preparation = try query.preparation.map { try PreparationState(kind: XCTUnwrap(PreparationKind(rawValue: $0))) }
            let request = GenericFoodSearchRequest(text: try LedgerText(query.text), identity: GenericFoodIdentityQuery(preparation: preparation),
                capturedAt: evidence.capturedAt, locale: evidence.locale, captureEvidence: evidence)
            for promoted in [false, true] {
                let v10 = V10ReferenceComposite(sources: [shared.cofid, shared.usda], regionalSources: [shared.tfda], promotesRegional: { _ in promoted })
                let expected = try v10.search(request)
                let lists: [[any GenericFoodSearching]] = query.sweep ? [[shared.ciqual], [shared.ciqual, synthetic], [synthetic]] : [[shared.ciqual]]
                for references in lists {
                    let v11 = CompositeGenericFoodSearch(sources: [shared.cofid, shared.usda], regionalSources: [shared.tfda],
                                                         referenceSources: references, promotesRegional: { _ in promoted }, ids: ids)
                    let actual = try v11.search(request)
                    let label = "\(query.text) promoted=\(promoted) references=\(references.count)"
                    switch (expected, actual) {
                    case let (.confirmation(old), .confirmation(new)):
                        let isReference = new.matches.map { Self.isReference($0.candidate.candidate.recordID.value) }
                        check(new.matches.filter { !Self.isReference($0.candidate.candidate.recordID.value) } == old.matches, "matches: \(label)")
                        check(new.confirmation.sourceReleases.filter { !$0.sourceReleaseID.value.hasPrefix(Self.ciqualPrefix) }
                              == old.confirmation.sourceReleases, "releases: \(label)")
                        check(new.confirmation.evidence == old.confirmation.evidence, "evidence: \(label)")
                        // No preparation or fat partition separates these rows, so references follow every other row.
                        if query.preparation == nil, FoodQueryParser.parse(query.text).attributes["fat_descriptor"] == nil {
                            check(isReference == isReference.sorted { !$0 && $1 }, "reference rows last: \(label)")
                        }
                        tally.syntheticShown += new.matches.contains { $0.candidate.candidate.recordID.value.hasPrefix(Self.syntheticPrefix) } ? 1 : 0
                        tally.compared += 1
                    case let (.noResult(old), .noResult(new)):
                        check(new.suggestedQueries == old.suggestedQueries && new.guidance == old.guidance && new.evidence == old.evidence,
                              "no-result route: \(label)")
                    case let (.noResult, .confirmation(new)):
                        // The one visible difference: a request whose only matches are reference rows.
                        check(new.matches.allSatisfy { Self.isReference($0.candidate.candidate.recordID.value) }, "reference-only result: \(label)")
                        tally.ciqualOnly += 1
                    case (.confirmation, .noResult):
                        tally.failures.append("v11 lost results: \(label)")
                    }
                }
            }
            return tally
        }
        let lock = NSLock()
        var total = Tally()
        DispatchQueue.concurrentPerform(iterations: queries.count) { index in
            let tally: Tally
            do { tally = try compare(queries[index], index: index) } catch { tally = Tally(failures: ["\(queries[index].text): \(error)"]) }
            lock.lock(); defer { lock.unlock() }
            total.failures += tally.failures; total.compared += tally.compared
            total.ciqualOnly += tally.ciqualOnly; total.syntheticShown += tally.syntheticShown
        }
        XCTAssertEqual(total.failures.sorted(), [])
        XCTAssertGreaterThan(total.compared, 0)
        XCTAssertGreaterThan(total.syntheticShown, 0, "the synthetic 90% row reached the dark chocolate requests")
        print("Subsequence property: \(queries.count) queries, \(total.compared) confirmation comparisons, \(total.ciqualOnly) reference-only results")
    }

    /// The synthetic 90% reference row never moves USDA 170273 out of tier 2 for 86 to 99%,
    /// although it would be "the greatest band below" 95 if keys were computed over all rows.
    func testAReferenceBandNeverChangesAnotherRowsTier() throws {
        let ids = RandomLedgerIDGenerator()
        let ciqual = try CiqualGenericFoodSearch(ids: ids)
        let search = CompositeGenericFoodSearch(sources: [try CoFIDGenericFoodSearch(ids: ids), try USDAGenericFoodSearch(ids: ids)],
                                                referenceSources: [SyntheticNinetyPercentReference(inner: ciqual)], ids: ids)
        let request = GenericFoodSearchRequest(text: try LedgerText("dark chocolate 95%"), capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: try LedgerText("en_GB"))
        guard case let .confirmation(route) = try search.search(request) else { return XCTFail() }
        XCTAssertEqual(route.matches.first?.candidate.name.value, "Chocolate, dark, 70-85% cacao solids")
        XCTAssertEqual(route.matches.last?.candidate.candidate.recordID.value.hasPrefix(Self.syntheticPrefix), true)
    }

    private static func isReference(_ recordID: String) -> Bool {
        recordID.hasPrefix(ciqualPrefix) || recordID.hasPrefix(syntheticPrefix)
    }

    // MARK: Band equality and the pinned Ciqual bands

    /// Section 4.2: v2 reads every bundled CoFID, USDA and TFDA record exactly as v1 did, over
    /// the name, description (or candidate variant) and record ID each reader sees.
    func testV2BandEqualsV1BandForEveryCoFIDUSDAAndTFDARecord() throws {
        func json(_ name: String) throws -> [String: Any] {
            let url = Self.packageRoot.appendingPathComponent("Sources/FoodGenericSearch/Resources/\(name)")
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        var inputs: [(name: String, description: String?, recordID: String?)] = []
        for record in try XCTUnwrap(try json("cofid-2021-generic-search-v1.json")["records"] as? [[String: Any]]) {
            let name = try XCTUnwrap(record["name"] as? String), description = record["description"] as? String
            let id = try XCTUnwrap(record["record_id"] as? String)
            inputs += [(name, description, nil), (name, description, id), (name, nil, id)]
        }
        for record in try XCTUnwrap(try json("usda-generic-v1.json")["records"] as? [[String: Any]]) {
            let name = try XCTUnwrap(record["name"] as? String), id = try XCTUnwrap(record["id"] as? String)
            inputs += [(name, nil, id), (name, "USDA · US composition estimate · per 100 g", id)]
        }
        for record in try XCTUnwrap(try json("tfda-generic-v1.json")["records"] as? [[String: Any]]) {
            let name = try XCTUnwrap(record["name"] as? String), id = "tfda:" + (try XCTUnwrap(record["id"] as? String))
            let sourceName = try XCTUnwrap(record["sourceName"] as? String), description = record["description"] as? String
            let variant = "TFDA · Taiwan composition estimate · per 100 g edible portion"
            for shown in [name, name + " · " + sourceName, name + ", raw · " + sourceName] {
                inputs += [(shown, variant, id), (shown, nil, nil)]
            }
            inputs += [(sourceName, description, id)] + (record["aliases"] as? [String] ?? []).map { ($0, nil, id) }
        }
        XCTAssertGreaterThan(inputs.count, 10_000)
        var mismatches: [String] = []
        for input in inputs where CocoaPercentPolicy.band(name: input.name, description: input.description, recordID: input.recordID)
                != V1BandReader.band(name: input.name, description: input.description, recordID: input.recordID) {
            mismatches.append("\(input.name) | \(input.description ?? "-")")
        }
        XCTAssertEqual(mismatches, [])
    }

    /// docs/cocoa-exact-match-v1.md rule 1.5: the v3 display reading equals the band for every
    /// bundled CoFID, USDA and TFDA input above, so bundled row notes and Search sections are unchanged.
    func testV3DisplayBandEqualsBandForEveryCoFIDUSDAAndTFDARecord() throws {
        func json(_ name: String) throws -> [String: Any] {
            let url = Self.packageRoot.appendingPathComponent("Sources/FoodGenericSearch/Resources/\(name)")
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
        var inputs: [(name: String, description: String?, recordID: String?)] = []
        for record in try XCTUnwrap(try json("cofid-2021-generic-search-v1.json")["records"] as? [[String: Any]]) {
            let name = try XCTUnwrap(record["name"] as? String), description = record["description"] as? String
            inputs += [(name, description, nil), (name, nil, nil)]
        }
        for record in try XCTUnwrap(try json("usda-generic-v1.json")["records"] as? [[String: Any]]) {
            inputs += [(try XCTUnwrap(record["name"] as? String), nil, try XCTUnwrap(record["id"] as? String))]
        }
        for record in try XCTUnwrap(try json("tfda-generic-v1.json")["records"] as? [[String: Any]]) {
            let name = try XCTUnwrap(record["name"] as? String), sourceName = try XCTUnwrap(record["sourceName"] as? String)
            inputs += [(name, nil, nil), (name + " · " + sourceName, nil, nil), (sourceName, record["description"] as? String, nil)]
            inputs += (record["aliases"] as? [String] ?? []).map { ($0, nil, nil) }
        }
        XCTAssertGreaterThan(inputs.count, 10_000)
        let mismatches = inputs.filter {
            CocoaPercentPolicy.displayBand(name: $0.name, description: $0.description, recordID: $0.recordID)
                != CocoaPercentPolicy.band(name: $0.name, description: $0.description, recordID: $0.recordID)
        }.map(\.name)
        XCTAssertEqual(mismatches, [])
    }

    /// The v2 bands of all 29 Ciqual rows, pinned to the spec's table (section 4).
    func testTheTwentyNineCiqualBandsArePinned() throws {
        let url = Self.packageRoot.appendingPathComponent("Sources/FoodGenericSearch/Resources/ciqual-2025-generic-v1.json")
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let records = try XCTUnwrap(corpus["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 29)
        let pinned: [String: CocoaPercentPolicy.Band] = ["31074": .declared(lower: 70, upper: 70), "31005": .declared(lower: 50, upper: 50), "31085": .atLeast(40)]
        let variant = "Ciqual · French composition estimate · per 100 g"
        for record in records {
            let code = try XCTUnwrap(record["alimCode"] as? String), name = try XCTUnwrap(record["name"] as? String)
            let id = try XCTUnwrap(record["recordID"] as? String)
            XCTAssertEqual(CocoaPercentPolicy.band(name: name, description: variant, recordID: id), pinned[code], code)
            XCTAssertEqual(CocoaPercentPolicy.band(name: name, description: nil, recordID: id), pinned[code], code)
            XCTAssertEqual(CocoaPercentPolicy.displayBand(name: name, description: variant, recordID: id), pinned[code], code)
            // Only the qualified row reads differently from v1, which read it as a wrong point band.
            XCTAssertEqual(V1BandReader.band(name: name, description: variant, recordID: id),
                           code == "31085" ? .declared(lower: 40, upper: 40) : pinned[code], code)
        }
    }

    // MARK: Helpers

    /// Shares one source search between the v10 and v11 composites for the same request.
    private final class Memo: GenericFoodSearching, @unchecked Sendable {
        let inner: any GenericFoodSearching
        private var cache: [String: GenericFoodSearchOutcome] = [:]
        init(_ inner: any GenericFoodSearching) { self.inner = inner }
        func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
            let key = [request.text.value, request.identity.preparation.map { "\($0.kind)" } ?? "-",
                       request.captureEvidence?.evidenceID.rawValue ?? UUID().uuidString].joined(separator: "|")
            if let hit = cache[key] { return hit }
            let outcome = try inner.search(request)
            cache[key] = outcome
            return outcome
        }
    }
}

/// One synthetic reference-only row banded at 90%, built from a real Ciqual row so it carries
/// bundled generic provenance; used only to prove the per-group tier keys.
private struct SyntheticNinetyPercentReference: GenericFoodSearching {
    let inner: any GenericFoodSearching
    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        guard case let .confirmation(route) = try inner.search(request), let first = route.matches.first?.candidate else { return try inner.search(request) }
        let row = try ProviderNeutralCandidate(sourceReleaseID: first.candidate.sourceReleaseID,
            recordID: ExternalIdentifier("synthetic-reference:90"), identity: first.candidate.identity,
            edibleQuantity: first.candidate.edibleQuantity, nutrients: first.candidate.nutrients, evidenceIDs: first.candidate.evidenceIDs)
        let candidate = try PopulatedFoodCandidate(candidate: row, name: LedgerText("Dark chocolate, 90% cocoa, bar"),
                                                   variant: first.variant, itemClass: .food)
        return .confirmation(GenericFoodConfirmationRoute(confirmation: try PopulatedFoodConfirmation(
            evidence: route.confirmation.evidence, sourceReleases: route.confirmation.sourceReleases, candidates: [candidate],
            expectedIdentity: row.identity, expectedEdibleQuantity: row.edibleQuantity), matches: [GenericFoodMatch(candidate: candidate, isExactName: false)]))
    }
}

/// `composite-generic-ranking-v10` as merged before #384 C2 (origin/main fe18ddb), frozen here
/// as the reference for the v11 removal invariant. Bands are read with the frozen v1 reader on
/// name, variant and record ID, and tier keys with the frozen v1 function below, so no live
/// cocoa policy code is used. Remaining differences from fe18ddb: the evidence is the request's
/// capture evidence (every caller here sets it, so v10's `ids.makeID` branch is unreachable);
/// `CocoaPercentPolicy.requested`, `GenericFoodRankingPolicy`, `FoodPreparationDiscoveryPolicy`
/// and `FoodQueryCandidateAssessment.matchesFat` are the live code, none of which C2 changes.
private final class V10ReferenceComposite: GenericFoodSearching, @unchecked Sendable {
    private let sources: [any GenericFoodSearching]
    private let regionalSources: [any GenericFoodSearching]
    private let promotesRegional: (GenericFoodSearchRequest) -> Bool
    init(sources: [any GenericFoodSearching], regionalSources: [any GenericFoodSearching], promotesRegional: @escaping (GenericFoodSearchRequest) -> Bool) {
        self.sources = sources; self.regionalSources = regionalSources; self.promotesRegional = promotesRegional
    }

    func search(_ request: GenericFoodSearchRequest) throws -> GenericFoodSearchOutcome {
        let evidence = try XCTUnwrap(request.captureEvidence)
        let shared = GenericFoodSearchRequest(text: request.text, identity: request.identity, capturedAt: request.capturedAt,
                                             locale: request.locale, captureEvidence: evidence, additionalEvidence: request.additionalEvidence)
        var routes: [GenericFoodConfirmationRoute] = []
        var regionalRoutes = Set<Int>()
        var fallback: GenericFoodNoResultRoute?
        var suggestions: [String] = []
        let deferRegional = !promotesRegional(request)
        for (index, source) in (sources + regionalSources).enumerated() {
            switch try source.search(shared) {
            case let .confirmation(route):
                if route.reuse != nil { return .confirmation(route) }
                if index >= sources.count && deferRegional { regionalRoutes.insert(routes.count) }
                routes.append(route)
            case let .noResult(route):
                if fallback == nil { fallback = route }
                for query in route.suggestedQueries where !suggestions.contains(query) { suggestions.append(query) }
            }
        }
        guard let first = routes.first else {
            return .noResult(GenericFoodNoResultRoute(evidence: evidence, additionalEvidence: request.additionalEvidence, guidance: fallback?.guidance, suggestedQueries: Array(suggestions.prefix(3))))
        }
        var interleaved: [GenericFoodMatch] = []
        var regional: [Bool] = []
        for rank in 0..<(routes.map { $0.matches.count }.max() ?? 0) {
            for (index, route) in routes.enumerated() where rank < route.matches.count {
                interleaved.append(route.matches[rank]); regional.append(regionalRoutes.contains(index))
            }
        }
        let food = request.retrievalText
        let cocoa = CocoaPercentPolicy.requested(request.parsedQuery).map { value in
            V1TierKeys.keys(interleaved.map { V1BandReader.band(name: $0.candidate.name.value, description: $0.candidate.variant?.value,
                                                                 recordID: $0.candidate.candidate.recordID.value) }, requested: value)
        }
        let lexical = interleaved.enumerated().sorted { lhs, rhs in
            let leftUnverified = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: lhs.element.candidate.candidate.identity.preparation.kind)
            let rightUnverified = FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation,
                actual: rhs.element.candidate.candidate.identity.preparation.kind)
            if leftUnverified != rightUnverified { return !leftUnverified }
            if regional[lhs.offset] != regional[rhs.offset] { return !regional[lhs.offset] }
            if let cocoa, cocoa[lhs.offset] != cocoa[rhs.offset] { return cocoa[lhs.offset] < cocoa[rhs.offset] }
            if lhs.element.isExactName != rhs.element.isExactName { return lhs.element.isExactName }
            let a = GenericFoodRankingPolicy.preference(name: lhs.element.candidate.name.value, food: food, requestedText: request.text.value)
            let b = GenericFoodRankingPolicy.preference(name: rhs.element.candidate.name.value, food: food, requestedText: request.text.value)
            return a == b ? lhs.offset < rhs.offset : GenericFoodRankingPolicy.prefers(a, over: b)
        }.map(\.element)
        let fatRanked = lexical.filter { FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: $0.candidate) } + lexical.filter { !FoodQueryCandidateAssessment.matchesFat(query: request.parsedQuery, candidate: $0.candidate) }
        let matches = fatRanked.filter { !FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation, actual: $0.candidate.candidate.identity.preparation.kind) }
            + fatRanked.filter { FoodPreparationDiscoveryPolicy.isUnverified(requested: request.identity.preparation, actual: $0.candidate.candidate.identity.preparation.kind) }
        var releases: [SourceRelease] = []
        for release in routes.flatMap({ $0.confirmation.sourceReleases }) {
            if let existing = releases.first(where: { $0.sourceReleaseID == release.sourceReleaseID }) {
                guard existing == release else { throw FoodLedgerValidationError.duplicateValue("source release identity") }
            } else { releases.append(release) }
        }
        return .confirmation(GenericFoodConfirmationRoute(
            confirmation: try PopulatedFoodConfirmation(
                evidence: first.confirmation.evidence, sourceReleases: releases, candidates: matches.map(\.candidate),
                expectedIdentity: matches[0].candidate.candidate.identity, expectedEdibleQuantity: matches[0].candidate.candidate.edibleQuantity
            ), matches: matches
        ))
    }
}

/// `cocoa-percent-policy-v1`'s tier keys as merged before #384 C2 (origin/main fe18ddb): band
/// contains the request (1); else the greatest band below it (2); other bands by distance (3);
/// rows with no single band (4).
enum V1TierKeys {
    struct Key: Comparable {
        let tier: Int
        let distance: Double
        static func < (lhs: Key, rhs: Key) -> Bool { lhs.tier == rhs.tier ? lhs.distance < rhs.distance : lhs.tier < rhs.tier }
    }

    static func keys(_ bands: [CocoaPercentPolicy.Band?], requested value: Double) -> [Key] {
        let ranges: [ClosedRange<Double>?] = bands.map { band in
            switch band {
            case let .declared(lower, upper)?: lower <= upper ? lower...upper : nil
            case .estimate100?: 100...100
            default: nil
            }
        }
        let below = ranges.compactMap { $0 }.filter { !$0.contains(value) && $0.upperBound < value }.map(\.upperBound).max()
        return ranges.map { range in
            guard let range else { return Key(tier: 4, distance: 0) }
            if range.contains(value) { return Key(tier: 1, distance: 0) }
            if let below, range.upperBound == below { return Key(tier: 2, distance: 0) }
            return Key(tier: 3, distance: min(abs(value - range.lowerBound), abs(value - range.upperBound)))
        }
    }
}

/// `cocoa-percent-policy-v1`'s band reader as merged before #384 C2 (origin/main fe18ddb),
/// frozen here so the band-equality test compares against v1 itself.
enum V1BandReader {
    static func band(name: String, description: String?, recordID: String?) -> CocoaPercentPolicy.Band? {
        if recordID == CocoaPercentPolicy.estimate100RecordID { return .estimate100 }
        var found: [CocoaPercentPolicy.Band] = []
        for text in [name, description ?? ""] where !text.isEmpty {
            let lowered = text.lowercased()
            if lowered.contains("("), lowered.range(of: #"\([^)]*\d\s*%[^)]*(?:cocoa|cacao)"#, options: .regularExpression) != nil {
                found.append(.blend)
            }
            let outside = lowered.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            for match in captures(#"(\d+(?:\.\d+)?)\s*[-\x{2013}]\s*(\d+(?:\.\d+)?)\s*%\s*(?:cacao|cocoa)\s+solids"#, outside) {
                guard let lower = Double(match[0]), let upper = Double(match[1]), lower <= upper else { return nil }
                found.append(.declared(lower: lower, upper: upper))
            }
            let withoutRanges = outside.replacingOccurrences(
                of: #"\d+(?:\.\d+)?\s*[-\x{2013}]\s*\d+(?:\.\d+)?\s*%"#, with: " ", options: .regularExpression)
            for match in captures(#"(\d+(?:\.\d+)?)\s*%\s*(?:cacao|cocoa)\b(?!\s*(?:butter|powder|mass|liquor|paste|nibs?|beans?))"#, withoutRanges) {
                guard let value = Double(match[0]) else { return nil }
                found.append(.declared(lower: value, upper: value))
            }
        }
        let declared = found.filter { $0 != .blend }
        if declared.isEmpty { return found.isEmpty ? nil : .blend }
        // v1's `range` check: only `.declared` reaches here, so a valid range is lower <= upper.
        guard Set(declared).count == 1, case let .declared(lower, upper) = declared[0], lower <= upper,
              lower >= 0, upper <= 100 else { return nil }
        return declared[0]
    }

    private static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
