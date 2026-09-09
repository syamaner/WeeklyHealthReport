import Foundation
import XCTest
@testable import WeeklyHealthReport

// All values and identities in this file are invented. No test contacts HealthKit or Google.
final class DailyDriveExportCoordinatorTests: XCTestCase {
    private let reportDate = "2026-09-06"
    private let accountID = "account-a"
    private let folderID = "folder-a"
    private let token: DailyDriveExportCoordinator.TokenProvider = { refresh in
        refresh ? "refreshed-token" : "initial-token"
    }

    func testCreatePersistsGeneratedIDThenUpdatesOneFileByStoredID() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        await server.setReservationProbe {
            guard let identity = try? store.load()?.identities.first else { return false }
            return identity.fileID == "generated-1" && identity.pending?.phase == .submitted
        }
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)

        let morning = try await export(8, coordinator: coordinator)
        XCTAssertEqual(morning, .verified(
            dataAsOf: "2026-09-06T08:00:00+01:00", created: true
        ))
        let fileID = try XCTUnwrap(store.snapshot()?.identities.first?.fileID)
        let evening = try await export(18, coordinator: coordinator)
        XCTAssertEqual(evening, .verified(
            dataAsOf: "2026-09-06T18:00:00+01:00", created: false
        ))
        let bedtime = try await export(23, coordinator: coordinator)
        XCTAssertEqual(bedtime, .verified(
            dataAsOf: "2026-09-06T23:00:00+01:00", created: false
        ))
        let repeated = try await export(23, coordinator: coordinator)
        XCTAssertEqual(repeated, .unchangedVerified(
            dataAsOf: "2026-09-06T23:00:00+01:00"
        ))

        let generatedIDs = await server.generatedIDs
        let createIDs = await server.createIDs
        let updateIDs = await server.updateIDs
        let fileCount = await server.fileCount()
        let storedContent = await server.storedContent(id: fileID)
        XCTAssertEqual(generatedIDs, [fileID])
        XCTAssertEqual(createIDs, [fileID])
        XCTAssertEqual(updateIDs, [fileID, fileID])
        XCTAssertEqual(fileCount, 1)
        XCTAssertEqual(storedContent, try payload(hour: 23))
    }

    func testSchemaV1CanonicalFileIsReplacedByV3UnderSameIDWithoutWeakeningGuards() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)
        let version1 = try legacyVersion1Payload(hour: 8)

        _ = try await coordinator.export(
            payload: version1,
            reportDate: reportDate,
            accountID: accountID,
            folderID: folderID,
            tokenProvider: token
        )
        let fileID = try XCTUnwrap(store.snapshot()?.identities.first?.fileID)
        let version3 = try payload(hour: 18)
        _ = try await coordinator.export(
            payload: version3,
            reportDate: reportDate,
            accountID: accountID,
            folderID: folderID,
            tokenProvider: token
        )

        let fileCountAfterReplacement = await server.fileCount()
        let contentAfterReplacement = await server.storedContent(id: fileID)
        let generatedIDs = await server.generatedIDs
        let updateIDs = await server.updateIDs
        XCTAssertEqual(store.snapshot()?.identities.first?.fileID, fileID)
        XCTAssertEqual(fileCountAfterReplacement, 1)
        XCTAssertEqual(contentAfterReplacement, version3)
        XCTAssertEqual(generatedIDs, [fileID])
        XCTAssertEqual(updateIDs, [fileID])

        do {
            _ = try await coordinator.export(
                payload: try payload(hour: 8),
                reportDate: reportDate,
                accountID: accountID,
                folderID: folderID,
                tokenProvider: token
            )
            XCTFail("A schema-v3 payload older than the verified replacement must be rejected")
        } catch DailyDriveExportFailure.staleSnapshot {}
        let fileCountAfterStaleAttempt = await server.fileCount()
        let contentAfterStaleAttempt = await server.storedContent(id: fileID)
        XCTAssertEqual(fileCountAfterStaleAttempt, 1)
        XCTAssertEqual(contentAfterStaleAttempt, version3)
    }

    func testSchemaV2CanonicalFileIsReplacedByV3UnderSameID() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)
        let version2 = try legacyVersion2Payload(hour: 8)
        _ = try await coordinator.export(
            payload: version2,
            reportDate: reportDate,
            accountID: accountID,
            folderID: folderID,
            tokenProvider: token
        )
        let fileID = try XCTUnwrap(store.snapshot()?.identities.first?.fileID)

        let version3 = try payload(hour: 18)
        _ = try await coordinator.export(
            payload: version3,
            reportDate: reportDate,
            accountID: accountID,
            folderID: folderID,
            tokenProvider: token
        )

        let fileCount = await server.fileCount()
        let storedContent = await server.storedContent(id: fileID)
        XCTAssertEqual(fileCount, 1)
        XCTAssertEqual(storedContent, version3)
        XCTAssertEqual(store.snapshot()?.identities.first?.fileID, fileID)
    }

    func testUncertainCreateRetriesSameReservedIDAndLostResponseReconciles() async throws {
        let retryStore = MemoryDailyIdentityStore()
        let retryServer = MockDailyDriveServer()
        await retryServer.enqueueCreate(.transientBeforeCommit)
        let retryCoordinator = DailyDriveExportCoordinator(
            transport: retryServer,
            store: retryStore
        )
        let retryResult = try await export(8, coordinator: retryCoordinator)
        XCTAssertEqual(retryResult, .verified(
            dataAsOf: "2026-09-06T08:00:00+01:00", created: true
        ))
        let retryIDs = await retryServer.createIDs
        XCTAssertEqual(retryIDs.count, 2)
        XCTAssertEqual(retryIDs.first, retryIDs.last)
        let generatedCount = await retryServer.generatedIDs.count
        XCTAssertEqual(generatedCount, 1)
        XCTAssertGreaterThanOrEqual(retryStore.savedCount(), 4)

        let lostStore = MemoryDailyIdentityStore()
        let lostServer = MockDailyDriveServer()
        await lostServer.enqueueCreate(.transientAfterCommit)
        let lostCoordinator = DailyDriveExportCoordinator(
            transport: lostServer,
            store: lostStore
        )
        _ = try await export(8, coordinator: lostCoordinator)
        let lostCreateCount = await lostServer.createIDs.count
        let lostFileCount = await lostServer.fileCount()
        XCTAssertEqual(lostCreateCount, 1)
        XCTAssertEqual(lostFileCount, 1)
    }

    func testSerialisationCancellationAndTokenRefreshPreserveVerifiedState() async throws {
        let beforeStore = MemoryDailyIdentityStore()
        let beforeServer = MockDailyDriveServer()
        await beforeServer.pauseGenerate()
        let beforeCoordinator = DailyDriveExportCoordinator(
            transport: beforeServer,
            store: beforeStore
        )
        let beforeTask = Task { try await self.export(8, coordinator: beforeCoordinator) }
        await waitUntil { await beforeServer.isGeneratePaused() }
        await beforeCoordinator.requestCancellation()
        await beforeServer.resumeGenerate()
        let beforeResult = try await beforeTask.value
        let beforeCreateIDs = await beforeServer.createIDs
        XCTAssertEqual(beforeResult, .cancelledBeforeSubmission)
        XCTAssertTrue(beforeCreateIDs.isEmpty)
        XCTAssertEqual(beforeStore.snapshot()?.identities.first?.pending?.phase, .reserved)

        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)
        _ = try await export(8, coordinator: coordinator)
        await server.enqueueUpdate(.unauthorized)
        _ = try await export(18, coordinator: coordinator)
        let refreshedUpdateCount = await server.updateIDs.count
        XCTAssertEqual(refreshedUpdateCount, 2)

        await server.pauseUpdateAfterCommit()
        let task = Task { try await self.export(23, coordinator: coordinator) }
        await waitUntil { await server.isUpdatePaused() }
        do {
            _ = try await export(23, coordinator: coordinator)
            XCTFail("A second write must not overlap")
        } catch DailyDriveExportFailure.busy {}
        await coordinator.requestCancellation()
        await server.resumeUpdate()
        let cancelledResult = try await task.value
        XCTAssertEqual(cancelledResult, .cancelledAfterSubmissionVerified(
            dataAsOf: "2026-09-06T23:00:00+01:00", created: false
        ))
    }

    func testOnlyUncancelledVerifiedResultsAuthorizeNoteCleanup() {
        XCTAssertTrue(DailyDriveExportResult.verified(
            dataAsOf: "2026-09-06T23:00:00+01:00",
            created: true
        ).authorizesNoteCleanup)
        XCTAssertTrue(DailyDriveExportResult.unchangedVerified(
            dataAsOf: "2026-09-06T23:00:00+01:00"
        ).authorizesNoteCleanup)
        XCTAssertFalse(DailyDriveExportResult.cancelledBeforeSubmission.authorizesNoteCleanup)
        XCTAssertFalse(DailyDriveExportResult.cancelledAfterSubmissionVerified(
            dataAsOf: "2026-09-06T23:00:00+01:00",
            created: false
        ).authorizesNoteCleanup)
    }

    func testUnresolvedSubmissionHasNoQueueAndBlocksNewerSnapshot() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)
        _ = try await export(8, coordinator: coordinator)
        await server.enqueueUpdate(.transientBeforeCommit)
        await server.enqueueUpdate(.transientBeforeCommit)
        do {
            _ = try await export(18, coordinator: coordinator)
            XCTFail("Two lost submissions must remain unresolved")
        } catch DailyDriveExportFailure.unresolvedRequest {}
        let count = await server.updateIDs.count
        try await Task.sleep(for: .milliseconds(20))
        let countAfterWait = await server.updateIDs.count
        XCTAssertEqual(countAfterWait, count)
        do {
            _ = try await export(23, coordinator: coordinator)
            XCTFail("A newer snapshot must not overtake unresolved state")
        } catch DailyDriveExportFailure.unresolvedRequest {}
        XCTAssertEqual(
            store.snapshot()?.identities.first?.lastVerified?.dataAsOf,
            "2026-09-06T08:00:00+01:00"
        )
    }

    func testRelaunchRecoveryCredentialsAndDestinationIsolationFailClosed() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let first = DailyDriveExportCoordinator(transport: server, store: store)
        _ = try await export(8, coordinator: first)
        let identity = try XCTUnwrap(store.snapshot()?.identities.first)
        let relaunched = DailyDriveExportCoordinator(transport: server, store: store)
        _ = try await export(18, coordinator: relaunched)
        let generatedCount = await server.generatedIDs.count
        let updateIDs = await server.updateIDs
        XCTAssertEqual(generatedCount, 1)
        XCTAssertEqual(updateIDs, [identity.fileID])

        let recoveredStore = MemoryDailyIdentityStore()
        let recovered = DailyDriveExportCoordinator(transport: server, store: recoveredStore)
        let recovery = try await recovered.recover(
                selectedFileID: identity.fileID,
                reportDate: reportDate,
                accountID: accountID,
                folderID: folderID,
                tokenProvider: token
            )
        XCTAssertEqual(recovery, .recovered(dataAsOf: "2026-09-06T18:00:00+01:00"))
        XCTAssertEqual(recoveredStore.snapshot()?.identities.first?.fileID, identity.fileID)

        store.removeRegistryPreservingMarker()
        do {
            _ = try await export(23, coordinator: relaunched)
            XCTFail("A marker without its registry must fail closed")
        } catch DailyDriveExportFailure.identityRecoveryAmbiguous {}

        for failure in [
            DailyDriveCredentialFailure.expired,
            .denied,
            .revoked
        ] {
            let credentialServer = MockDailyDriveServer()
            let coordinator = DailyDriveExportCoordinator(
                transport: credentialServer,
                store: MemoryDailyIdentityStore()
            )
            do {
                _ = try await export(
                    8,
                    coordinator: coordinator,
                    tokenProvider: { _ in throw failure }
                )
                XCTFail("Credential failure must stop before Drive ID generation")
            } catch DailyDriveExportFailure.credentials(let observed) {
                XCTAssertEqual(observed, failure)
            }
            let generatedIDs = await credentialServer.generatedIDs
            XCTAssertTrue(generatedIDs.isEmpty)
        }

        let isolationStore = MemoryDailyIdentityStore()
        let isolationServer = MockDailyDriveServer()
        let isolation = DailyDriveExportCoordinator(
            transport: isolationServer,
            store: isolationStore
        )
        _ = try await export(8, coordinator: isolation)
        do {
            _ = try await export(18, coordinator: isolation, folder: "folder-b")
            XCTFail("Destination state must not be reused")
        } catch DailyDriveExportFailure.destinationChangeRequiresMigration {}
        await isolationServer.setAccountID("account-b")
        do {
            _ = try await export(18, coordinator: isolation)
            XCTFail("Account state must not be reused")
        } catch DailyDriveExportFailure.accountMismatch {}
    }

    func testAbandonmentRemovesOnlyExactIdentitiesAndPreservesInstallation() async throws {
        let store = MemoryDailyIdentityStore()
        let installationID = "installation-a"
        try store.save(DailyDriveExportRegistry(
            installationID: installationID,
            identities: [
                identity(
                    accountID: "account-a", folderID: "folder-a",
                    reportDate: "2026-09-06", installationID: installationID
                ),
                identity(
                    accountID: "account-a", folderID: "folder-b",
                    reportDate: "2026-09-07", installationID: installationID
                ),
                identity(
                    accountID: "account-b", folderID: "folder-a",
                    reportDate: "2026-09-08", installationID: installationID
                )
            ]
        ))
        let coordinator = DailyDriveExportCoordinator(
            transport: MockDailyDriveServer(),
            store: store
        )

        try await coordinator.abandonFileIdentity(
            accountID: "account-a",
            folderID: "folder-b",
            reportDate: "2026-09-07"
        )

        XCTAssertEqual(
            store.snapshot()?.identities.map { [$0.accountID, $0.folderID, $0.reportDate] },
            [
                ["account-a", "folder-a", "2026-09-06"],
                ["account-b", "folder-a", "2026-09-08"]
            ]
        )

        try await coordinator.abandonDestination(accountID: "account-a", folderID: "folder-a")

        XCTAssertEqual(store.snapshot()?.installationID, installationID)
        XCTAssertEqual(try store.installationMarker(), installationID)
        XCTAssertEqual(
            store.snapshot()?.identities.map { [$0.accountID, $0.folderID, $0.reportDate] },
            [
                ["account-b", "folder-a", "2026-09-08"]
            ]
        )

        store.removeRegistryPreservingMarker()
        do {
            try await coordinator.abandonDestination(
                accountID: "account-b",
                folderID: "folder-a"
            )
            XCTFail("A marker without its registry must block identity abandonment")
        } catch DailyDriveExportFailure.identityRecoveryAmbiguous {}
    }

    func testExplicitMissingFileOverrideAllowsFreshCanonicalID() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)
        _ = try await export(8, coordinator: coordinator)
        let originalID = try XCTUnwrap(store.snapshot()?.identities.first?.fileID)
        await server.removeFile(id: originalID)

        do {
            _ = try await export(18, coordinator: coordinator)
            XCTFail("A missing tracked file must fail closed before explicit override")
        } catch DailyDriveExportFailure.remoteMissing {}
        XCTAssertEqual(store.snapshot()?.identities.first?.fileID, originalID)

        try await coordinator.abandonFileIdentity(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate
        )
        let replacement = try await export(18, coordinator: coordinator)
        let replacementID = try XCTUnwrap(store.snapshot()?.identities.first?.fileID)
        let fileCount = await server.fileCount()
        let generatedIDs = await server.generatedIDs

        XCTAssertEqual(replacement, .verified(
            dataAsOf: "2026-09-06T18:00:00+01:00",
            created: true
        ))
        XCTAssertNotEqual(replacementID, originalID)
        XCTAssertEqual(fileCount, 1)
        XCTAssertEqual(generatedIDs, [originalID, replacementID])
    }

    func testByteMetadataRemoteStateAndStaleCompletionAreRejected() async throws {
        let mismatchStore = MemoryDailyIdentityStore()
        let mismatchServer = MockDailyDriveServer()
        let mismatch = DailyDriveExportCoordinator(
            transport: mismatchServer,
            store: mismatchStore
        )
        _ = try await export(8, coordinator: mismatch)
        _ = try await export(18, coordinator: mismatch)
        await mismatchServer.overrideContent(try payload(hour: 23))
        do {
            _ = try await export(18, coordinator: mismatch)
            XCTFail("Remote bytes must match")
        } catch DailyDriveExportFailure.remoteContentMismatch {}
        XCTAssertEqual(
            mismatchStore.snapshot()?.identities.first?.lastVerified?.dataAsOf,
            "2026-09-06T18:00:00+01:00"
        )

        await mismatchServer.overrideContent(nil)
        await mismatchServer.overrideParent("moved-folder")
        do {
            _ = try await export(18, coordinator: mismatch)
            XCTFail("Moved file must fail verification")
        } catch DailyDriveExportFailure.remoteMoved {}
        await mismatchServer.overrideParent(nil)
        await mismatchServer.setTrashed(true)
        do {
            _ = try await export(18, coordinator: mismatch)
            XCTFail("Trashed file must fail verification")
        } catch DailyDriveExportFailure.remoteTrashed {}

        let staleStore = MemoryDailyIdentityStore()
        let staleServer = MockDailyDriveServer()
        let stale = DailyDriveExportCoordinator(transport: staleServer, store: staleStore)
        _ = try await export(8, coordinator: stale)
        await staleServer.pauseUpdateAfterCommit()
        let task = Task { try await self.export(18, coordinator: stale) }
        await waitUntil { await staleServer.isUpdatePaused() }
        staleStore.mutate { registry in
            guard let pending = registry.identities[0].pending else { return }
            registry.identities[0].pending = PendingDailyDriveOperation(
                operationID: "newer-operation",
                dataAsOf: pending.dataAsOf,
                payloadSHA256: pending.payloadSHA256,
                kind: pending.kind,
                phase: pending.phase
            )
        }
        await staleServer.resumeUpdate()
        do {
            _ = try await task.value
            XCTFail("Stale completion must not become verified")
        } catch DailyDriveExportFailure.staleCompletion {}
        XCTAssertEqual(
            staleStore.snapshot()?.identities.first?.lastVerified?.dataAsOf,
            "2026-09-06T08:00:00+01:00"
        )

        do {
            _ = try await stale.export(
                payload: Data(#"{"invented":true}"#.utf8),
                reportDate: reportDate,
                accountID: accountID,
                folderID: folderID,
                tokenProvider: token
            )
            XCTFail("Non-canonical bytes must be rejected")
        } catch DailyDriveExportFailure.invalidPayload {}
    }

    private func export(
        _ hour: Int,
        coordinator: DailyDriveExportCoordinator,
        account: String? = nil,
        folder: String? = nil,
        tokenProvider: DailyDriveExportCoordinator.TokenProvider? = nil
    ) async throws -> DailyDriveExportResult {
        try await coordinator.export(
            payload: payload(hour: hour),
            reportDate: reportDate,
            accountID: account ?? accountID,
            folderID: folder ?? folderID,
            tokenProvider: tokenProvider ?? token
        )
    }

    private func payload(hour: Int) throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let cutoff = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 6, hour: hour
        ))!
        let window = try DailyExportWindow.capture(at: cutoff, calendar: calendar)
        let emptyGlucose = DailyGlucoseValue(
            day: window.day,
            averageMillimolesPerLiter: nil,
            minimumMillimolesPerLiter: nil,
            maximumMillimolesPerLiter: nil,
            sourceNames: []
        )
        let inputs = DailyHealthExportInputs(
            weight: [], bodyFat: [], waist: [], vo2Max: [], bloodOxygen: [],
            bloodPressure: [],
            todaySteps: DailyStepTotal(
                day: window.day,
                steps: Double(hour * 100),
                sourceNames: ["Invented Fixture"]
            ),
            todayGlucose: emptyGlucose,
            hourlyGlucose: window.glucoseHours.map {
                DailyGlucoseValue(
                    day: $0,
                    averageMillimolesPerLiter: nil,
                    minimumMillimolesPerLiter: nil,
                    maximumMillimolesPerLiter: nil,
                    sourceNames: []
                )
            },
            todayRestingHeartRate: DailyHeartMetricValue(
                day: window.day, value: nil, sourceNames: []
            ),
            todayHRV: DailyHeartMetricValue(day: window.day, value: nil, sourceNames: []),
            todayWatchSampleDates: [],
            todayActiveEnergyKilocalories: nil,
            todayExerciseMinutes: nil,
            todayWorkouts: [],
            todayAsleepIntervals: [],
            todayMedicationDoses: [],
            supportsMedicationData: false,
            contextSteps: [], contextGlucose: [], contextRestingHeartRate: [],
            previousRestingHeartRate: [], contextHRV: [], previousHRV: [],
            contextWatchSampleDates: [], contextActiveEnergyKilocalories: nil,
            contextExerciseMinutes: nil, contextWorkouts: [], contextAsleepIntervals: [],
            contextMedicationDoses: [],
            nutrition: emptyNutrition(window: window)
        )
        let envelope = try DailyHealthExportBuilder.make(
            window: window,
            exportedAt: cutoff.addingTimeInterval(1),
            inputs: inputs
        )
        let bytes = try DailyHealthExportSerializer.encode(envelope)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(DailyHealthExportEnvelope.self, from: bytes)
        XCTAssertEqual(try DailyHealthExportSerializer.encode(decoded), bytes)
        return bytes
    }

    private func legacyVersion1Payload(hour: Int) throws -> Data {
        let current = try decodedPayload(hour: hour)
        let today = current.today
        let context = current.appContext
        let legacy = DailyHealthExportEnvelope(
            schemaVersion: 1,
            reportDate: current.reportDate,
            timeZone: current.timeZone,
            dataAsOf: current.dataAsOf,
            exportedAt: current.exportedAt,
            dayWindow: current.dayWindow,
            today: DailyHealthMetrics(
                notes: nil,
                weight: today.weight,
                bodyFat: today.bodyFat,
                waist: today.waist,
                bloodPressure: today.bloodPressure,
                glucose: today.glucose,
                restingHeartRate: today.restingHeartRate,
                hrv: today.hrv,
                bloodOxygen: today.bloodOxygen,
                vo2Max: today.vo2Max,
                sleep: today.sleep,
                activity: today.activity,
                workouts: today.workouts,
                watchCoverage: today.watchCoverage,
                medications: today.medications,
                nutrition: nil
            ),
            appContext: DailyAppContext(
                policyID: context.policyID,
                window: context.window,
                weight: context.weight,
                bodyFat: context.bodyFat,
                waist: context.waist,
                glucose: context.glucose,
                vo2Max: context.vo2Max,
                bloodOxygen: context.bloodOxygen,
                bloodPressure: context.bloodPressure,
                steps: context.steps,
                restingHeartRate: context.restingHeartRate,
                hrv: context.hrv,
                watchCoverage: context.watchCoverage,
                sleep: context.sleep,
                activeEnergy: context.activeEnergy,
                exercise: context.exercise,
                workouts: context.workouts,
                medications: context.medications,
                nutrition: nil
            )
        )
        let bytes = try DailyHealthExportSerializer.encode(legacy)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(DailyHealthExportEnvelope.self, from: bytes)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.today.nutrition)
        XCTAssertEqual(try DailyHealthExportSerializer.encode(decoded), bytes)
        return bytes
    }

    private func legacyVersion2Payload(hour: Int) throws -> Data {
        let current = try decodedPayload(hour: hour)
        let today = current.today
        let legacy = DailyHealthExportEnvelope(
            schemaVersion: 2,
            reportDate: current.reportDate,
            timeZone: current.timeZone,
            dataAsOf: current.dataAsOf,
            exportedAt: current.exportedAt,
            dayWindow: current.dayWindow,
            today: DailyHealthMetrics(
                notes: nil,
                weight: today.weight,
                bodyFat: today.bodyFat,
                waist: today.waist,
                bloodPressure: today.bloodPressure,
                glucose: today.glucose,
                restingHeartRate: today.restingHeartRate,
                hrv: today.hrv,
                bloodOxygen: today.bloodOxygen,
                vo2Max: today.vo2Max,
                sleep: today.sleep,
                activity: today.activity,
                workouts: today.workouts,
                watchCoverage: today.watchCoverage,
                medications: today.medications,
                nutrition: today.nutrition
            ),
            appContext: current.appContext
        )
        let bytes = try DailyHealthExportSerializer.encode(legacy)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(DailyHealthExportEnvelope.self, from: bytes)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertNil(decoded.today.notes)
        XCTAssertNotNil(decoded.today.nutrition)
        XCTAssertEqual(try DailyHealthExportSerializer.encode(decoded), bytes)
        return bytes
    }

    private func decodedPayload(hour: Int) throws -> DailyHealthExportEnvelope {
        let bytes = try payload(hour: hour)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DailyHealthExportEnvelope.self, from: bytes)
    }

    private func emptyNutrition(window: DailyExportWindow) -> NutritionExportInput {
        let previous = window.context.precedingEquivalent(calendar: window.calendar)!
        return NutritionExportInput(
            source: NutritionSource(
                bundleIdentifier: "example.fixture.nutrition",
                name: "Invented Nutrition Source"
            ),
            nutrients: NutritionCatalogue.all.map { definition in
                NutritionNutrientTotals(
                    key: definition.key,
                    today: nil,
                    currentDays: window.context.completedDays.map {
                        NutritionDailyTotal(day: $0.start, value: nil)
                    },
                    previousDays: previous.completedDays.map {
                        NutritionDailyTotal(day: $0.start, value: nil)
                    }
                )
            }
        )
    }

    private func identity(
        accountID: String,
        folderID: String,
        reportDate: String,
        installationID: String
    ) -> DailyDriveExportIdentity {
        DailyDriveExportIdentity(
            accountID: accountID,
            folderID: folderID,
            reportDate: reportDate,
            fileID: "file-\(accountID)-\(folderID)-\(reportDate)",
            installationID: installationID,
            lastVerified: nil,
            pending: nil
        )
    }

    func testExplicitRecoveryMigratesTheSameCanonicalFileAfterFolderMove() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)
        _ = try await export(8, coordinator: coordinator)
        let identity = try XCTUnwrap(store.snapshot()?.identities.first)

        await server.overrideParent("folder-b")
        let recovery = try await coordinator.recover(
            selectedFileID: identity.fileID,
            reportDate: reportDate,
            accountID: accountID,
            folderID: "folder-b",
            tokenProvider: token
        )

        XCTAssertEqual(recovery, .migrated(dataAsOf: "2026-09-06T08:00:00+01:00"))
        let migrated = try XCTUnwrap(store.snapshot()?.identities.first)
        XCTAssertEqual(migrated.accountID, accountID)
        XCTAssertEqual(migrated.folderID, "folder-b")
        XCTAssertEqual(migrated.fileID, identity.fileID)
        XCTAssertNil(migrated.pending)
        let generatedAfterMigration = await server.generatedIDs.count
        XCTAssertEqual(generatedAfterMigration, 1)

        _ = try await export(18, coordinator: coordinator, folder: "folder-b")
        let generatedAfterUpdate = await server.generatedIDs.count
        let updateIDs = await server.updateIDs
        XCTAssertEqual(generatedAfterUpdate, 1)
        XCTAssertEqual(updateIDs, [identity.fileID])
    }

    func testExplicitRecoveryWillNotMigrateADifferentCanonicalFile() async throws {
        let store = MemoryDailyIdentityStore()
        let server = MockDailyDriveServer()
        let coordinator = DailyDriveExportCoordinator(transport: server, store: store)
        _ = try await export(8, coordinator: coordinator)
        let selectedFileID = try XCTUnwrap(store.snapshot()?.identities.first?.fileID)
        store.mutate { registry in
            let existing = registry.identities[0]
            registry.identities[0] = DailyDriveExportIdentity(
                accountID: existing.accountID,
                folderID: existing.folderID,
                reportDate: existing.reportDate,
                fileID: "different-file",
                installationID: existing.installationID,
                lastVerified: existing.lastVerified,
                pending: existing.pending
            )
        }
        await server.overrideParent("folder-b")

        do {
            _ = try await coordinator.recover(
                selectedFileID: selectedFileID,
                reportDate: reportDate,
                accountID: accountID,
                folderID: "folder-b",
                tokenProvider: token
            )
            XCTFail("Migration must require the exact previously tracked file ID")
        } catch DailyDriveExportFailure.identityRecoveryAmbiguous {}

        XCTAssertEqual(store.snapshot()?.identities.first?.folderID, folderID)
        let generatedIDs = await server.generatedIDs
        let updateIDs = await server.updateIDs
        XCTAssertEqual(generatedIDs.count, 1)
        XCTAssertTrue(updateIDs.isEmpty)
    }

    private func waitUntil(_ predicate: @escaping () async -> Bool) async {
        for _ in 0..<5_000 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for deterministic test gate")
    }
}

private final class MemoryDailyIdentityStore: DailyDriveExportIdentityPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DailyDriveExportRegistry?
    private var marker: String?
    private var saves = 0

    func load() throws -> DailyDriveExportRegistry? {
        lock.withLock { value }
    }

    func installationMarker() throws -> String? {
        lock.withLock { marker }
    }

    func save(_ registry: DailyDriveExportRegistry) throws {
        lock.withLock {
            if let marker { precondition(marker == registry.installationID) }
            marker = registry.installationID
            value = registry
            saves += 1
        }
    }

    func snapshot() -> DailyDriveExportRegistry? { lock.withLock { value } }
    func savedCount() -> Int { lock.withLock { saves } }

    func removeRegistryPreservingMarker() {
        lock.withLock { value = nil }
    }

    func mutate(_ change: (inout DailyDriveExportRegistry) -> Void) {
        lock.withLock {
            guard var current = value else { return }
            change(&current)
            value = current
        }
    }
}

private actor MockDailyDriveServer: DailyDriveTransporting {
    enum Behavior: Sendable {
        case succeed, transientBeforeCommit, transientAfterCommit, unauthorized, denied
    }

    struct Stored: Sendable {
        var descriptor: DailyDriveUploadDescriptor
        var content: Data
    }

    private(set) var accountID = "account-a"
    private(set) var generatedIDs: [String] = []
    private(set) var createIDs: [String] = []
    private(set) var updateIDs: [String] = []
    private var files: [String: Stored] = [:]
    private var creates: [Behavior] = []
    private var updates: [Behavior] = []
    private var generatedCounter = 0
    private var contentOverride: Data?
    private var parentOverride: String?
    private var trashed = false
    private var pauseNextGenerate = false
    private var generateContinuation: CheckedContinuation<Void, Never>?
    private var pauseNextUpdate = false
    private var updateContinuation: CheckedContinuation<Void, Never>?
    private var reservationProbe: (@Sendable () -> Bool)?

    func setAccountID(_ value: String) { accountID = value }
    func enqueueCreate(_ behavior: Behavior) { creates.append(behavior) }
    func enqueueUpdate(_ behavior: Behavior) { updates.append(behavior) }
    func overrideContent(_ value: Data?) { contentOverride = value }
    func overrideParent(_ value: String?) { parentOverride = value }
    func setTrashed(_ value: Bool) { trashed = value }
    func setReservationProbe(_ value: @escaping @Sendable () -> Bool) { reservationProbe = value }
    func pauseGenerate() { pauseNextGenerate = true }
    func pauseUpdateAfterCommit() { pauseNextUpdate = true }
    func isGeneratePaused() -> Bool { generateContinuation != nil }
    func isUpdatePaused() -> Bool { updateContinuation != nil }
    func resumeGenerate() { generateContinuation?.resume(); generateContinuation = nil }
    func resumeUpdate() { updateContinuation?.resume(); updateContinuation = nil }
    func fileCount() -> Int { files.count }
    func storedContent(id: String) -> Data? { files[id]?.content }
    func removeFile(id: String) { files.removeValue(forKey: id) }

    func account(accessToken: String) async throws -> DailyDriveAccount {
        DailyDriveAccount(
            id: accountID,
            displayName: "Invented User",
            emailAddress: "invented@example.invalid"
        )
    }

    func generateFileID(accessToken: String) async throws -> String {
        if pauseNextGenerate {
            pauseNextGenerate = false
            await withCheckedContinuation { generateContinuation = $0 }
        }
        generatedCounter += 1
        let id = "generated-\(generatedCounter)"
        generatedIDs.append(id)
        return id
    }

    func createFile(
        _ descriptor: DailyDriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        createIDs.append(descriptor.id)
        precondition(reservationProbe?() ?? true)
        try apply(next(&creates), descriptor: descriptor, content: content, requiresExisting: false)
    }

    func updateFile(
        _ descriptor: DailyDriveUploadDescriptor,
        content: Data,
        accessToken: String
    ) async throws {
        updateIDs.append(descriptor.id)
        try apply(next(&updates), descriptor: descriptor, content: content, requiresExisting: true)
        if pauseNextUpdate {
            pauseNextUpdate = false
            await withCheckedContinuation { updateContinuation = $0 }
        }
    }

    func fileMetadata(id: String, accessToken: String) async throws -> DailyDriveFileMetadata {
        guard let file = files[id] else { throw DailyDriveAPI.Failure.httpStatus(404, nil) }
        return DailyDriveFileMetadata(
            id: id,
            name: file.descriptor.name,
            mimeType: "application/json",
            parents: [parentOverride ?? file.descriptor.parentID],
            trashed: trashed,
            driveID: nil,
            isAppAuthorized: true,
            canEdit: true,
            appProperties: file.descriptor.appProperties
        )
    }

    func fileContent(id: String, accessToken: String) async throws -> Data {
        guard let file = files[id] else { throw DailyDriveAPI.Failure.httpStatus(404, nil) }
        return contentOverride ?? file.content
    }

    private func next(_ values: inout [Behavior]) -> Behavior {
        values.isEmpty ? .succeed : values.removeFirst()
    }

    private func apply(
        _ behavior: Behavior,
        descriptor: DailyDriveUploadDescriptor,
        content: Data,
        requiresExisting: Bool
    ) throws {
        if requiresExisting && files[descriptor.id] == nil {
            throw DailyDriveAPI.Failure.httpStatus(404, nil)
        }
        switch behavior {
        case .succeed:
            files[descriptor.id] = Stored(descriptor: descriptor, content: content)
        case .transientBeforeCommit:
            throw URLError(.timedOut)
        case .transientAfterCommit:
            files[descriptor.id] = Stored(descriptor: descriptor, content: content)
            throw URLError(.networkConnectionLost)
        case .unauthorized:
            throw DailyDriveAPI.Failure.httpStatus(401, nil)
        case .denied:
            throw DailyDriveAPI.Failure.httpStatus(403, "insufficientFilePermissions")
        }
    }
}

final class DailyDrivePolicyTests: XCTestCase {
    func testScopePickerDestinationAndRevocationPoliciesStayNarrow() throws {
        XCTAssertNoThrow(try DailyDriveConsentPolicy.validateGrantedScopes(
            DailyDriveConsentPolicy.scope
        ))
        XCTAssertThrowsError(try DailyDriveConsentPolicy.validateGrantedScopes(
            "\(DailyDriveConsentPolicy.scope) openid"
        ))
        XCTAssertEqual(
            try DailyDriveConsentPolicy.selectedItemID(from: "one-id"),
            "one-id"
        )
        XCTAssertThrowsError(try DailyDriveConsentPolicy.selectedItemID(from: "one,two"))

        let folder = DailyDriveFolder(
            id: "folder-a", accountID: "account-a", name: "Invented",
            mimeType: DailyDriveConsentPolicy.folderMIMEType, trashed: false,
            driveID: nil, isAppAuthorized: true, canAddChildren: true
        )
        XCTAssertNoThrow(try DailyDriveConsentPolicy.validate(
            folder: folder, expectedAccountID: "account-a"
        ))
        XCTAssertEqual(
            DailyDisconnectTransition.afterRevocation(statusCode: 200),
            .clearCredentialsPreserveDestinations
        )
        XCTAssertEqual(
            DailyDisconnectTransition.afterRevocation(statusCode: 500),
            .keepCredentialsAndReportFailure
        )

        var partitions = DailyDestinationPartitions()
        partitions.bind(DailyDestinationBinding(
            accountID: "account-a",
            folderID: "folder-a",
            folderName: "Invented",
            origin: .created
        ))
        XCTAssertFalse(partitions.unbind(accountID: "account-a", folderID: "folder-b"))
        XCTAssertNotNil(partitions.destination(for: "account-a"))
        XCTAssertTrue(partitions.unbind(accountID: "account-a", folderID: "folder-a"))
        XCTAssertNil(partitions.destination(for: "account-a"))
    }
}
