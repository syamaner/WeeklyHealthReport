import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerGRDB
import FoodLedgerTestSupport

struct TestHarness {
    let name: String
    let committer: any LedgerCommandCommitting
    let reader: any LedgerReading & FoodConfirmationReading
    let cleanup: () -> Void
}

enum LedgerFixtures {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static let clock = FixedClock(value: date)
    static let encoder = FoundationCanonicalJSONEncoder()
    static let digester = SHA256Digester()

    static func harnesses() throws -> [TestHarness] {
        let memory = InMemoryFoodLedgerStore(encoder: encoder, digester: digester)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("food-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let grdb = try FoodLedgerGRDBStore.temporary(
            directory: directory,
            encoder: encoder,
            digester: digester
        )
        return [
            TestHarness(name: "memory", committer: memory, reader: memory, cleanup: {}),
            TestHarness(
                name: "grdb",
                committer: grdb,
                reader: grdb,
                cleanup: { try? FileManager.default.removeItem(at: directory) }
            )
        ]
    }

    static func service(_ committer: any LedgerCommandCommitting) throws -> FoodLedgerService {
        FoodLedgerService(
            actorID: try id(900, ActorTag.self),
            committer: committer,
            clock: clock,
            encoder: encoder,
            digester: digester
        )
    }

    static func baseMutation() throws -> LedgerMutation {
        let evidenceID: EvidenceID = try id(1, EvidenceTag.self)
        let productID: ProductID = try id(2, ProductTag.self)
        let productVersionID: ProductVersionID = try id(3, ProductVersionTag.self)
        let resolutionID: ResolutionID = try id(4, ResolutionTag.self)
        let resolutionVersionID: ResolutionVersionID = try id(5, ResolutionVersionTag.self)
        let evidence = try CaptureEvidence(
            evidenceID: evidenceID,
            kind: .synthetic,
            capturedAt: date,
            locale: LedgerText("en_GB"),
            captureMethod: LedgerText("synthetic_fixture"),
            captureMethodVersion: LedgerText("v1"),
            originalPayload: .text(LedgerText("fixture"))
        )
        let product = Product(productID: productID, createdAt: date)
        let productVersion = try ProductVersion(
            productVersionID: productVersionID,
            productID: productID,
            ordinal: VersionOrdinal(1),
            name: LedgerText("Fixture food"),
            itemClass: .food,
            packFacts: PackFacts(),
            identity: identity(),
            evidenceIDs: [evidenceID],
            assertionIDs: [],
            createdAt: date
        )
        let resolution = NutritionResolution(
            resolutionID: resolutionID,
            productVersionID: productVersionID,
            basis: .per100Grams,
            createdAt: date
        )
        let version = try NutritionResolutionVersion(
            resolutionVersionID: resolutionVersionID,
            resolutionID: resolutionID,
            ordinal: try VersionOrdinal(1),
            methodVersion: try LedgerText("fixture_resolution_v1"),
            sourceReleaseIDs: [try ExternalIdentifier("package:fixture-v1")],
            nutrients: try nutrientSet(),
            createdAt: date
        )
        return LedgerMutation(
            evidence: [evidence],
            products: [product],
            productVersions: [productVersion],
            resolutions: [resolution],
            resolutionVersions: [version],
            sourceReleases: [try packageSourceRelease()]
        )
    }

    static func identity(
        drained: DrainedState = .notApplicable,
        fortification: FortificationState = .unfortified
    ) throws -> DecisiveIdentity {
        try DecisiveIdentity(
            preparation: PreparationState(kind: .asSold),
            bone: .notApplicable,
            skin: .notApplicable,
            drained: drained,
            packingMedium: .named(LedgerText("none")),
            fortification: fortification,
            servingBasis: .per100Grams
        )
    }

    static func nutrientSet() throws -> NutrientSet {
        let provenance = NutrientProvenance(
            sourceKind: .userVerifiedPanel,
            sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"),
            evidenceID: try id(1, EvidenceTag.self),
            capturedAt: date
        )
        let entries = try NutrientKey.allCases.map { key -> NutrientEntry in
            switch key {
            case .protein:
                return try NutrientEntry(
                    key: key,
                    value: .measured(ExactNutrientValue(
                        amount: 10,
                        unit: key.canonicalUnit,
                        sourceValue: .exact(SourceExactNutrientValue(
                            amount: 10,
                            unit: LedgerText(key.canonicalUnit.rawValue),
                            basis: .per100Grams
                        )),
                        provenance: [provenance]
                    ))
                )
            case .sugar:
                return try NutrientEntry(
                    key: key,
                    value: .bounded(NutrientBounds(
                        lower: 0,
                        upper: 0.5,
                        lowerClosed: true,
                        upperClosed: false,
                        origin: .measured,
                        unit: key.canonicalUnit,
                        sourceValue: .bounded(SourceBoundedNutrientValue(
                            lower: 0,
                            upper: 0.5,
                            lowerClosed: true,
                            upperClosed: false,
                            unit: LedgerText(key.canonicalUnit.rawValue),
                            basis: .per100Grams
                        )),
                        provenance: [provenance]
                    ))
                )
            case .iodine:
                return try NutrientEntry(key: key, value: .unknown(.noCompatibleSource))
            default:
                return try NutrientEntry(key: key, value: .unknown(.notDeclared))
            }
        }
        return try NutrientSet(entries: entries)
    }

    static func id<Tag>(_ number: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", number))
    }

    static func operationID(_ number: Int) throws -> OperationID {
        try id(number, OperationTag.self)
    }

    static func packageSourceRelease() throws -> SourceRelease {
        SourceRelease(
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"),
            sourceID: try ExternalIdentifier("physical_package"),
            releasedAt: date,
            artifactHash: try SHA256Digest(String(repeating: "c", count: 64)),
            schemaVersion: try LedgerText("food-contract-v1"),
            pipelineVersion: try LedgerText("manual-capture-v1"),
            licence: try LedgerText("user supplied evidence"),
            attribution: try LedgerText("synthetic fixture"),
            manifestHash: try SHA256Digest(String(repeating: "d", count: 64))
        )
    }

    static func validTransaction(
        mutation: LedgerMutation,
        operationID: OperationID,
        actorID: ActorID,
        sequence: Int,
        previousHash: FoodLedgerDomain.SHA256Digest?
    ) throws -> LedgerTransaction {
        let payload = try encoder.encode(mutation)
        let payloadHash = try digester.sha256(payload)
        let unsigned = UnsignedLedgerOperation(
            schemaVersion: LedgerOperation.schemaVersion,
            operationID: operationID,
            actorID: actorID,
            actorSequence: sequence,
            operationType: .composite,
            createdAt: date,
            affectedIDs: mutation.affectedIDs,
            payloadHash: payloadHash,
            previousOperationHash: previousHash,
            idempotencyKey: nil
        )
        let operation = LedgerOperation(
            operationID: operationID,
            actorID: actorID,
            actorSequence: sequence,
            operationType: .composite,
            createdAt: date,
            affectedIDs: mutation.affectedIDs,
            payload: payload,
            payloadHash: payloadHash,
            previousOperationHash: previousHash,
            operationHash: try digester.sha256(encoder.encode(unsigned)),
            idempotencyKey: nil
        )
        return LedgerTransaction(mutation: mutation, operation: operation)
    }
}

struct FixedClock: LedgerClock {
    let value: Date
    func now() -> Date { value }
}
