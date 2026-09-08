import Speech
import XCTest
@testable import WeeklyHealthReport

@MainActor
final class DailyNoteSpeechCaptureTests: XCTestCase {
    func testPermissionsAreNotRequestedUntilMicrophoneTap() async {
        let capture = FakeSpeechCapture(permission: .notDetermined)
        let controller = makeSpeechController(capture: capture)
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(capture.permissionRequestCount, 0)

        capture.requestedPermission = .authorized
        await controller.toggle()

        XCTAssertEqual(capture.permissionRequestCount, 1)
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(controller.state, .listening)
    }

    func testDeniedAndRestrictedPermissionsFailClosedButRemainExplicit() async {
        for expected in [SpeechCapturePermission.denied, .restricted] {
            let capture = FakeSpeechCapture(permission: .notDetermined)
            capture.requestedPermission = expected
            let controller = makeSpeechController(capture: capture)

            await controller.toggle()

            XCTAssertEqual(controller.state, expected == .denied ? .denied : .restricted)
            XCTAssertEqual(capture.startCount, 0)
        }
    }

    func testOnlyDeniedPermissionOffersSettingsRecovery() {
        let denied = makeSpeechController(capture: FakeSpeechCapture(permission: .denied))
        XCTAssertTrue(denied.canOpenPermissionSettings)
        XCTAssertFalse(denied.isMicrophoneEnabled)

        let restricted = makeSpeechController(capture: FakeSpeechCapture(permission: .restricted))
        XCTAssertFalse(restricted.canOpenPermissionSettings)
        XCTAssertFalse(restricted.isMicrophoneEnabled)
    }

    func testUnsupportedLocaleDeviceAndTemporaryUnavailabilityDisableCapture() async {
        let cases: [(OnDeviceSpeechAvailability, DailyNoteSpeechController.State)] = [
            (.unsupportedLocale, .unsupportedLocale),
            (.unsupportedDevice, .unsupportedDevice),
            (.unavailable, .unavailable)
        ]

        for (availability, expectedState) in cases {
            let capture = FakeSpeechCapture(availability: availability)
            let controller = makeSpeechController(capture: capture)
            XCTAssertEqual(controller.state, expectedState)
            XCTAssertFalse(controller.isMicrophoneEnabled)

            await controller.toggle()

            XCTAssertEqual(capture.permissionRequestCount, 0)
            XCTAssertEqual(capture.startCount, 0)
        }
    }

    func testEveryRecognitionRequestRequiresOnDeviceRecognitionAndPartials() {
        let first = SFSpeechAudioBufferRecognitionRequest()
        let second = SFSpeechAudioBufferRecognitionRequest()

        OnDeviceSpeechRequestPolicy.configure(first)
        OnDeviceSpeechRequestPolicy.configure(second)

        XCTAssertTrue(first.requiresOnDeviceRecognition)
        XCTAssertTrue(second.requiresOnDeviceRecognition)
        XCTAssertTrue(first.shouldReportPartialResults)
        XCTAssertTrue(second.shouldReportPartialResults)
        XCTAssertEqual(first.taskHint, .dictation)
    }

    func testStartStopFinaliseAndRepeatCycle() async {
        let capture = FakeSpeechCapture()
        var appended: [String] = []
        let controller = DailyNoteSpeechController(capture: capture) {
            appended.append($0)
            return nil
        }

        await controller.toggle()
        XCTAssertEqual(controller.state, .listening)
        await controller.toggle()
        XCTAssertEqual(controller.state, .stopping)
        XCTAssertEqual(capture.stopCount, 1)
        capture.send(.init(transcript: "First result", isFinal: true))
        XCTAssertEqual(appended, ["First result"])
        XCTAssertEqual(controller.state, .ready)

        await controller.toggle()
        XCTAssertEqual(controller.state, .listening)
        capture.send(.init(transcript: "Second result", isFinal: true))
        XCTAssertEqual(appended, ["First result", "Second result"])
        XCTAssertEqual(capture.startCount, 2)
    }

    func testPartialTranscriptNeverEntersEditableTextBeforeFinalResult() async {
        let capture = FakeSpeechCapture()
        var appended: [String] = []
        let controller = DailyNoteSpeechController(capture: capture) {
            appended.append($0)
            return nil
        }

        await controller.toggle()
        capture.send(.init(transcript: "still changing", isFinal: false))
        XCTAssertEqual(controller.partialTranscript, "still changing")
        XCTAssertTrue(appended.isEmpty)

        capture.send(.init(transcript: "safely final", isFinal: true))
        XCTAssertEqual(controller.partialTranscript, "")
        XCTAssertEqual(appended, ["safely final"])
    }

    func testInterruptionAndRecognitionFailureDiscardOnlyPartialText() async {
        for failure in [SpeechCaptureFailure.interrupted, .recognitionFailed] {
            let capture = FakeSpeechCapture()
            var appended: [String] = []
            let controller = DailyNoteSpeechController(capture: capture) {
                appended.append($0)
                return nil
            }
            await controller.toggle()
            capture.send(.init(transcript: "unsafe partial", isFinal: false))

            capture.fail(failure)

            XCTAssertEqual(controller.partialTranscript, "")
            XCTAssertTrue(appended.isEmpty)
            XCTAssertEqual(capture.cancelCount, 1)
            guard case .failed = controller.state else {
                return XCTFail("Expected an explicit failure state")
            }
        }
    }

    func testLaterInterruptionPreservesTypedAndPreviouslyFinalisedText() async throws {
        let notes = try makeNotesController(draft: "Typed")
        let capture = FakeSpeechCapture()
        let speech = speechController(capture: capture, notes: notes)

        await speech.toggle()
        capture.send(.init(transcript: "finalised", isFinal: true))
        await speech.toggle()
        capture.send(.init(transcript: "unsafe partial", isFinal: false))
        capture.fail(.interrupted)

        XCTAssertEqual(notes.currentDraft?.text, "Typed finalised")
        XCTAssertEqual(speech.partialTranscript, "")
    }

    func testBackgroundingStopsCaptureAndInvalidatesLateResults() async {
        let capture = FakeSpeechCapture()
        var appended: [String] = []
        let controller = DailyNoteSpeechController(capture: capture) {
            appended.append($0)
            return nil
        }
        await controller.toggle()
        capture.send(.init(transcript: "partial", isFinal: false))

        controller.stopForLifecycle()
        capture.send(.init(transcript: "late final", isFinal: true))

        XCTAssertEqual(capture.cancelCount, 1)
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.partialTranscript, "")
        XCTAssertTrue(appended.isEmpty)
    }

    func testEditorDismissalStopsCaptureAndAllowsANewCycle() async {
        let capture = FakeSpeechCapture()
        let controller = makeSpeechController(capture: capture)
        await controller.toggle()

        controller.stopForLifecycle()
        await controller.toggle()

        XCTAssertEqual(capture.cancelCount, 1)
        XCTAssertEqual(capture.startCount, 2)
        XCTAssertEqual(controller.state, .listening)
    }

    func testLifecycleStopWhilePermissionIsPendingPreventsCaptureFromStarting() async {
        let capture = FakeSpeechCapture(permission: .notDetermined)
        capture.shouldSuspendPermissionRequest = true
        let controller = makeSpeechController(capture: capture)

        let toggleTask = Task { await controller.toggle() }
        await capture.waitForPermissionRequest()
        XCTAssertEqual(controller.state, .requestingPermission)

        controller.stopForLifecycle()
        capture.completePermissionRequest(.authorized)
        await toggleTask.value

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(capture.cancelCount, 1)
        XCTAssertEqual(controller.state, .ready)
    }

    func testCallbackFromEarlierCycleCannotAlterLaterCycle() async {
        let capture = FakeSpeechCapture()
        var appended: [String] = []
        let controller = DailyNoteSpeechController(capture: capture) {
            appended.append($0)
            return nil
        }

        await controller.toggle()
        controller.stopForLifecycle()
        await controller.toggle()

        capture.send(.init(transcript: "stale final", isFinal: true), fromCycle: 0)
        XCTAssertEqual(controller.state, .listening)
        XCTAssertEqual(controller.partialTranscript, "")
        XCTAssertTrue(appended.isEmpty)

        capture.send(.init(transcript: "current final", isFinal: true), fromCycle: 1)
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(appended, ["current final"])
    }

    func testStartFailureIsVisibleAndRetryable() async {
        let capture = FakeSpeechCapture()
        capture.startFailure = .audioInputUnavailable
        let controller = makeSpeechController(capture: capture)

        await controller.toggle()

        guard case .failed = controller.state else {
            return XCTFail("Expected an explicit failure state")
        }
        XCTAssertTrue(controller.canRetryAvailability)
        capture.startFailure = nil
        controller.retryAvailability()
        await controller.toggle()
        XCTAssertEqual(controller.state, .listening)
    }

    func testFinalTranscriptAppendsWithoutReplacingExistingDraft() async throws {
        let notes = try makeNotesController(draft: "Typed first")
        let capture = FakeSpeechCapture()
        let speech = speechController(capture: capture, notes: notes)

        await speech.toggle()
        capture.send(.init(transcript: "  then spoken  ", isFinal: true))

        XCTAssertEqual(notes.currentDraft?.text, "Typed first then spoken")
    }

    func testFinalTranscriptAppendsToDraftEditedWhileListening() async throws {
        let notes = try makeNotesController(draft: "Typed first")
        let capture = FakeSpeechCapture()
        let speech = speechController(capture: capture, notes: notes)

        await speech.toggle()
        capture.send(.init(transcript: "unsafe partial", isFinal: false))
        XCTAssertTrue(notes.updateDraftText("Typed first, edited while listening"))

        capture.send(.init(transcript: "spoken final", isFinal: true))

        XCTAssertEqual(
            notes.currentDraft?.text,
            "Typed first, edited while listening spoken final"
        )
        XCTAssertEqual(speech.partialTranscript, "")
    }

    func testPerNoteLimitRejectsFinalTranscriptWithoutTruncatingDraft() async throws {
        let base = String(repeating: "a", count: 1_999)
        let notes = try makeNotesController(draft: base)
        let capture = FakeSpeechCapture()
        let speech = speechController(capture: capture, notes: notes)

        await speech.toggle()
        capture.send(.init(transcript: "bc", isFinal: true))

        XCTAssertEqual(notes.currentDraft?.text, base)
        XCTAssertEqual(notes.errorMessage, "A note can contain at most 2,000 characters.")
        guard case .failed = speech.state else {
            return XCTFail("Expected rejected transcript feedback")
        }
    }

    func testDailyLimitRejectsFinalTranscriptWithoutTruncatingDraft() async throws {
        var document = DailyNotesDocument()
        for index in 0..<9 {
            try add(String(repeating: Character(String(index)), count: 2_000), to: &document)
        }
        try add(String(repeating: "z", count: 1_999), to: &document)
        try document.beginDraft(for: londonDay, now: now)
        let notes = DailyNotesController(
            store: SpeechNotesStore(document: document),
            calendar: londonCalendar,
            now: { self.now }
        )
        let capture = FakeSpeechCapture()
        let speech = speechController(capture: capture, notes: notes)

        await speech.toggle()
        capture.send(.init(transcript: "ab", isFinal: true))

        XCTAssertEqual(notes.currentDraft?.text, "")
        XCTAssertEqual(notes.errorMessage, "Today’s saved notes can contain at most 20,000 characters in total.")
    }

    func testSpeechAddsOnlyTextToLocalDocumentAndNoAudioArtifact() async throws {
        let notes = try makeNotesController(draft: "Base")
        let capture = FakeSpeechCapture()
        let speech = speechController(capture: capture, notes: notes)
        await speech.toggle()
        capture.send(.init(transcript: "spoken", isFinal: true))
        notes.flushDraft()

        let encoded = try JSONEncoder().encode(notes.document)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let draft = try XCTUnwrap(object["draft"] as? [String: Any])

        XCTAssertEqual(draft["text"] as? String, "Base spoken")
        XCTAssertNil(object["audio"])
        XCTAssertNil(draft["audio"])
        XCTAssertNil(draft["audioURL"])
    }

    private func makeSpeechController(capture: FakeSpeechCapture) -> DailyNoteSpeechController {
        DailyNoteSpeechController(capture: capture) { _ in nil }
    }

    private func speechController(
        capture: FakeSpeechCapture,
        notes: DailyNotesController
    ) -> DailyNoteSpeechController {
        DailyNoteSpeechController(capture: capture) { transcript in
            notes.appendSpeechTranscript(transcript) ? nil : notes.errorMessage
        }
    }

    private func makeNotesController(draft: String) throws -> DailyNotesController {
        var document = DailyNotesDocument()
        try document.beginDraft(for: londonDay, now: now)
        try document.updateDraft(text: draft, now: now)
        return DailyNotesController(
            store: SpeechNotesStore(document: document),
            calendar: londonCalendar,
            now: { self.now }
        )
    }

    private func add(_ text: String, to document: inout DailyNotesDocument) throws {
        try document.beginDraft(for: londonDay, now: now)
        try document.updateDraft(text: text, now: now)
        try document.saveDraft(now: now)
    }

    private var londonDay: DailyNoteDayID {
        DailyNoteDayID(reportDate: "2026-09-08", timeZoneIdentifier: "Europe/London")
    }

    private var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private var now: Date {
        londonCalendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 8,
            hour: 10
        ))!
    }
}

@MainActor
private final class FakeSpeechCapture: OnDeviceSpeechCapturing {
    var availability: OnDeviceSpeechAvailability
    var permission: SpeechCapturePermission
    var requestedPermission: SpeechCapturePermission = .authorized
    var startFailure: SpeechCaptureFailure?
    var shouldSuspendPermissionRequest = false
    private(set) var permissionRequestCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private var onUpdate: ((SpeechCaptureUpdate) -> Void)?
    private var onFailure: ((SpeechCaptureFailure) -> Void)?
    private var updateHandlers: [(SpeechCaptureUpdate) -> Void] = []
    private var permissionContinuation: CheckedContinuation<SpeechCapturePermission, Never>?
    private var permissionRequestWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        availability: OnDeviceSpeechAvailability = .available,
        permission: SpeechCapturePermission = .authorized
    ) {
        self.availability = availability
        self.permission = permission
    }

    func requestPermission() async -> SpeechCapturePermission {
        permissionRequestCount += 1
        if shouldSuspendPermissionRequest {
            return await withCheckedContinuation { continuation in
                permissionContinuation = continuation
                let waiters = permissionRequestWaiters
                permissionRequestWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        permission = requestedPermission
        return permission
    }

    func waitForPermissionRequest() async {
        guard permissionRequestCount == 0 else { return }
        await withCheckedContinuation { continuation in
            permissionRequestWaiters.append(continuation)
        }
    }

    func completePermissionRequest(_ permission: SpeechCapturePermission) {
        self.permission = permission
        shouldSuspendPermissionRequest = false
        permissionContinuation?.resume(returning: permission)
        permissionContinuation = nil
    }

    func start(
        onUpdate: @escaping (SpeechCaptureUpdate) -> Void,
        onFailure: @escaping (SpeechCaptureFailure) -> Void
    ) throws {
        startCount += 1
        if let startFailure { throw startFailure }
        self.onUpdate = onUpdate
        self.onFailure = onFailure
        updateHandlers.append(onUpdate)
    }

    func stop() { stopCount += 1 }
    func cancel() { cancelCount += 1 }
    func send(_ update: SpeechCaptureUpdate) { onUpdate?(update) }
    func send(_ update: SpeechCaptureUpdate, fromCycle index: Int) {
        updateHandlers[index](update)
    }
    func fail(_ failure: SpeechCaptureFailure) { onFailure?(failure) }
}

private final class SpeechNotesStore: DailyNotesPersisting {
    var document: DailyNotesDocument?

    init(document: DailyNotesDocument? = nil) {
        self.document = document
    }

    func load() throws -> DailyNotesDocument? { document }
    func save(_ document: DailyNotesDocument) throws { self.document = document }
}
