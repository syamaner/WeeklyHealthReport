import Foundation
import FoodLedgerDomain
import FoodLedgerApplication
import FoodLedgerTestSupport

@main struct SafeguardRunner {
    static func main() throws {
        let runner = SafeguardRunner()
        let cases = try [runner.execute(count: true), runner.execute(count: false)]
        let data = try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    func execute(count: Bool) throws -> [String: Any] {
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try id(999, ActorTag.self), committer: store,
            clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: FixedClock(), ids: SequenceIDs())
        var state = FoodConfirmationState(input: try fixtureInput())
        FoodConfirmationReducer.reduce(state: &state, action: .accept)
        state.quantity = FoodQuantityDraft(value: count ? 2 : 100, unit: count ? .count : .grams)
        var outcome = "saved"
        var error = ""
        do { _ = try service.save(state, operationID: id(920, OperationTag.self)) }
        catch let observed { outcome = "blocked"; error = String(describing: observed) }
        let records = try store.archiveState().records
        return ["case_id": count ? "unsupported-count-conversion" : "supported-grams-control",
                "validation": outcome, "error": error, "saved_count": records.logItemVersions.count,
                "entered_value": count ? 2 : 100, "entered_unit": count ? "count" : "g",
                "conversion_supplied": false]
    }
    private func fixtureInput(candidateCount: Int = 1, kind: CaptureKind = .synthetic, identityOverride: DecisiveIdentity? = nil) throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try id(1, EvidenceTag.self)
        let release = SourceRelease(
            sourceReleaseID: try ExternalIdentifier("synthetic:food-v1"),
            sourceID: try ExternalIdentifier("synthetic"),
            releasedAt: FixedClock.date,
            artifactHash: try SHA256Digest(String(repeating: "a", count: 64)),
            schemaVersion: try LedgerText("food-v1"),
            pipelineVersion: try LedgerText("fixture-v1"),
            licence: try LedgerText("fixture"),
            attribution: try LedgerText("fixture"),
            manifestHash: try SHA256Digest(String(repeating: "b", count: 64))
        )
        let evidence = try CaptureEvidence(
            evidenceID: evidenceID,
            kind: kind,
            capturedAt: FixedClock.date,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic_route"),
            captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("populated evidence"))
        )
        let identity = try identityOverride ?? DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: .notApplicable,
            packingMedium: .named(LedgerText("none")),
            fortification: .unfortified,
            servingBasis: .per100Grams
        )
        let quantity = try PositiveQuantity(value: 100, unit: .grams)
        let provenance = NutrientProvenance(
            sourceKind: .exactProductDataset,
            sourceID: release.sourceID,
            sourceReleaseID: release.sourceReleaseID,
            recordID: try ExternalIdentifier("record:1"),
            evidenceID: evidenceID,
            capturedAt: FixedClock.date
        )
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            if key == .protein {
                return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(
                    amount: 10,
                    unit: key.canonicalUnit,
                    sourceValue: .exact(SourceExactNutrientValue(
                        amount: 10,
                        unit: LedgerText(key.canonicalUnit.rawValue),
                        basis: .per100Grams
                    )),
                    provenance: [provenance]
                )))
            }
            return try NutrientEntry(key: key, value: .unknown(.notDeclared))
        })
        let candidates = try (0..<candidateCount).map { index in
            try PopulatedFoodCandidate(
                candidate: ProviderNeutralCandidate(
                    sourceReleaseID: release.sourceReleaseID,
                    recordID: ExternalIdentifier("record:\(index + 1)"),
                    identity: identity,
                    edibleQuantity: .known(quantity, conversionVersionID: nil),
                    nutrients: nutrients,
                    evidenceIDs: [evidenceID]
                ),
                name: LedgerText(index == 0 ? "Fixture food" : "Alternate fixture food"),
                itemClass: .food
            )
        }
        return try PopulatedFoodConfirmation(
            evidence: [evidence],
            sourceReleases: [release],
            candidates: candidates,
            expectedIdentity: identity,
            expectedEdibleQuantity: .known(quantity, conversionVersionID: nil)
        )
    }

    private func id<Tag>(_ value: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
private struct FixedClock: LedgerClock {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { Self.date }
}
private final class SequenceIDs: LedgerIDGenerating, @unchecked Sendable {
    private var value = 100
    func makeID<Tag>(_ tag: Tag.Type) throws -> LedgerID<Tag> {
        value += 1
        return try LedgerID(String(format: "00000000-0000-0000-0000-%012x", value))
    }
}
