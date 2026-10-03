import Foundation
import FoodLedgerDomain
import FoodLedgerApplication
import FoodLedgerTestSupport

// Evaluation fixture only. Actual save/reopen/projection run through production types.
@main struct JourneyRunner {
    static let roster = ["grams-100", "grams-50", "two-entries", "quantity-edit", "idempotent-retry", "unsupported-count", "unaccepted", "cleared-quantity", "empty-other-day", "partial-nutrients", "completed-week", "remove-entry", "restore-entry"]
    static func main() throws {
        let runner = JourneyRunner()
        let cases = try roster.map { try runner.execute($0) }
        let data = try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    func execute(_ caseID: String) throws -> [String: Any] {
        let store = InMemoryFoodLedgerStore()
        let ledger = FoodLedgerService(actorID: try id(999, ActorTag.self), committer: store,
            clock: FixedClock(), encoder: FoundationCanonicalJSONEncoder(), digester: SHA256Digester())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let identifiers = SequenceIDs()
        let service = FoodConfirmationService(ledger: ledger, reader: store, clock: FixedClock(), ids: identifiers, calendar: calendar)
        var state = FoodConfirmationState(input: try fixtureInput())
        if caseID != "unaccepted" { FoodConfirmationReducer.reduce(state: &state, action: .accept) }
        state.quantity = FoodQuantityDraft(value: caseID == "grams-50" ? 50 : 100, unit: .grams)
        if caseID == "unsupported-count" { state.quantity = FoodQuantityDraft(value: 2, unit: .count) }
        if caseID == "cleared-quantity" { FoodConfirmationReducer.reduce(state: &state, action: .setQuantity(nil, .grams)) }
        var validation = "saved", error = ""
        var saved: StoredFoodConfirmation?
        do {
            saved = try service.save(state, operationID: id(920, OperationTag.self), idempotencyKey: LedgerText("journey-first"))
        } catch let observed { validation = "blocked"; error = String(describing: observed) }
        var retrySame = false
        if let saved {
            if caseID == "two-entries" || caseID == "partial-nutrients" {
                var second = FoodConfirmationState(input: try fixtureInput(evidenceNumber: 2, unknownProtein: caseID == "partial-nutrients"))
                FoodConfirmationReducer.reduce(state: &second, action: .accept)
                second.quantity = FoodQuantityDraft(value: 50, unit: .grams)
                _ = try service.save(second, operationID: id(921, OperationTag.self))
            }
            if caseID == "quantity-edit" {
                guard var reopened = try service.reopen(logItemID: saved.logItem.logItemID) else { throw FoodLedgerStoreError.integrityFailure("reopen failed") }
                FoodConfirmationReducer.reduce(state: &reopened, action: .setQuantity(200, .grams))
                _ = try service.save(reopened, operationID: id(921, OperationTag.self))
            }
            if caseID == "remove-entry" || caseID == "restore-entry" {
                let management = FoodLogManagementService(ledger: ledger, reader: ArchiveFoodLogHistoryReader(archive: store), clock: FixedClock(), ids: identifiers)
                let removed = try management.remove(logItemID: saved.logItem.logItemID, expectedVersion: saved.logItemVersion.logItemVersionID, reason: LedgerText("synthetic removal"), operationID: id(921, OperationTag.self))
                if caseID == "restore-entry" {
                    _ = try management.restore(logItemID: saved.logItem.logItemID, expectedVersion: removed.logItemVersionID, reason: LedgerText("synthetic restore"), operationID: id(922, OperationTag.self))
                }
            }
            if caseID == "idempotent-retry" {
                let retried = try service.save(state, operationID: id(920, OperationTag.self), idempotencyKey: LedgerText("journey-first"))
                retrySame = retried.logItemVersion.logItemVersionID == saved.logItemVersion.logItemVersionID
            }
        }
        let archive = try store.archiveState()
        let date = caseID == "empty-other-day" ? FixedClock.date.addingTimeInterval(-86400) : FixedClock.date
        let projection = try FoodIntakeProjection(records: archive.records, reportingDate: FoodReportingDay.key(for: date, calendar: calendar))
        let protein = projection.summary.totals.first { $0.key == .protein }!
        let fat = projection.summary.totals.first { $0.key == .fatTotal }!
        let preview = FoodIntakeDayPreview.pastWeek(records: archive.records, now: FixedClock.date.addingTimeInterval(86400), calendar: calendar)
        let previewCount = preview.reduce(0) { $0 + ($1.summary?.itemCount ?? 0) }
        let noToday = preview.allSatisfy { calendar.startOfDay(for: $0.date) < calendar.startOfDay(for: FixedClock.date.addingTimeInterval(86400)) }
        let evidencePreserved = archive.records.evidence.allSatisfy { $0.originalPayload == state.input.evidence[0].originalPayload }
        let provenancePreserved = archive.records.resolutionVersions.allSatisfy { v in
            v.nutrients.entries.flatMap { $0.value.provenance }.allSatisfy { provenance in provenance.sourceID.value == "synthetic" && ["record:1", "record:2"].contains(provenance.recordID?.value ?? "") && archive.records.evidence.contains(where: { e in e.evidenceID == provenance.evidenceID }) }
        }
        return ["case_id": caseID, "validation": validation, "error": error,
            "saved_versions": archive.records.logItemVersions.count, "operations": archive.operations.count,
            "evidence_count": archive.records.evidence.count, "nutrient_keys": projection.summary.totals.count,
            "row_grams": projection.rows.map { $0.quantity.value }.sorted(), "removed_rows": projection.removedRows.count,
            "rows": projection.rows.count, "item_count": projection.summary.itemCount,
            "protein_known": protein.knownAmount.map { $0 as Any } ?? NSNull(),
            "protein_incomplete": protein.incompleteContributions,
            "fat_known": fat.knownAmount.map { $0 as Any } ?? NSNull(), "fat_incomplete": fat.incompleteContributions,
            "evidence_preserved": evidencePreserved, "provenance_preserved": provenancePreserved,
            "retry_same_version": retrySame, "preview_days": preview.count, "preview_item_count": previewCount,
            "preview_excludes_today": noToday]
    }
    private func fixtureInput(evidenceNumber: Int = 1, unknownProtein: Bool = false, candidateCount: Int = 1, kind: CaptureKind = .synthetic, identityOverride: DecisiveIdentity? = nil) throws -> PopulatedFoodConfirmation {
        let evidenceID: EvidenceID = try id(evidenceNumber, EvidenceTag.self)
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
            recordID: try ExternalIdentifier("record:\(evidenceNumber)"),
            evidenceID: evidenceID,
            capturedAt: FixedClock.date
        )
        let nutrients = try NutrientSet(entries: NutrientKey.allCases.map { key in
            if key == .protein && !unknownProtein {
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
                    recordID: ExternalIdentifier("record:\(evidenceNumber + index)"),
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
