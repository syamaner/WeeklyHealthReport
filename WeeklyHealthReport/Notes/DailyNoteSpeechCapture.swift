import AVFAudio
import Combine
import Foundation
import Speech

enum SpeechCapturePermission: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum OnDeviceSpeechAvailability: Equatable {
    case available
    case unsupportedLocale
    case unsupportedDevice
    case unavailable
}

struct SpeechCaptureAudioRange: Equatable {
    let start: TimeInterval
    let end: TimeInterval

    init?(start: TimeInterval, end: TimeInterval) {
        guard start >= 0, end > start else { return nil }
        self.start = start
        self.end = end
    }

    func covers(_ other: SpeechCaptureAudioRange, tolerance: TimeInterval = 0.05) -> Bool {
        start <= other.start + tolerance && end >= other.end - tolerance
    }
}

struct SpeechCaptureUpdate: Equatable {
    let transcript: String
    let isFinal: Bool
    let audioRange: SpeechCaptureAudioRange?

    init(
        transcript: String,
        isFinal: Bool,
        audioRange: SpeechCaptureAudioRange? = nil
    ) {
        self.transcript = transcript
        self.isFinal = isFinal
        self.audioRange = audioRange
    }
}

enum SpeechCaptureFailure: Error, Equatable {
    case audioInputUnavailable
    case audioSessionUnavailable
    case interrupted
    case recognitionFailed
}

@MainActor
protocol OnDeviceSpeechCapturing: AnyObject {
    var availability: OnDeviceSpeechAvailability { get }
    var permission: SpeechCapturePermission { get }

    func requestPermission() async -> SpeechCapturePermission
    func start(
        onUpdate: @escaping (SpeechCaptureUpdate) -> Void,
        onFailure: @escaping (SpeechCaptureFailure) -> Void
    ) throws
    func stop()
    func cancel()
}

enum OnDeviceSpeechRequestPolicy {
    static func configure(_ request: SFSpeechAudioBufferRecognitionRequest) {
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
    }
}

@MainActor
final class SystemOnDeviceSpeechCapture: NSObject, OnDeviceSpeechCapturing {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine: AVAudioEngine
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionID: UUID?
    private var interruptionObserver: NSObjectProtocol?
    private var tapInstalled = false

    init(
        locale: Locale = .autoupdatingCurrent,
        audioEngine: AVAudioEngine = AVAudioEngine()
    ) {
        recognizer = SFSpeechRecognizer(locale: locale)
        self.audioEngine = audioEngine
        super.init()
    }

    var availability: OnDeviceSpeechAvailability {
        guard let recognizer else { return .unsupportedLocale }
        guard recognizer.supportsOnDeviceRecognition else { return .unsupportedDevice }
        guard recognizer.isAvailable else { return .unavailable }
        return .available
    }

    var permission: SpeechCapturePermission {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .authorized:
            break
        @unknown default:
            return .restricted
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    func requestPermission() async -> SpeechCapturePermission {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return permission
    }

    func start(
        onUpdate: @escaping (SpeechCaptureUpdate) -> Void,
        onFailure: @escaping (SpeechCaptureFailure) -> Void
    ) throws {
        cancel()
        guard permission == .authorized,
              availability == .available,
              let recognizer else {
            throw SpeechCaptureFailure.recognitionFailed
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechCaptureFailure.audioSessionUnavailable
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            deactivateAudioSession()
            throw SpeechCaptureFailure.audioInputUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        OnDeviceSpeechRequestPolicy.configure(request)
        let sessionID = UUID()
        self.request = request
        self.sessionID = sessionID

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == sessionID else { return }
                if let result {
                    let transcription = result.bestTranscription
                    let segments = transcription.segments
                    let audioRange = segments.first.flatMap { first in
                        segments.last.flatMap { last in
                            SpeechCaptureAudioRange(
                                start: first.timestamp,
                                end: last.timestamp + last.duration
                            )
                        }
                    }
                    onUpdate(SpeechCaptureUpdate(
                        transcript: transcription.formattedString,
                        isFinal: result.isFinal,
                        audioRange: audioRange
                    ))
                    if result.isFinal {
                        self.finishSession(cancelRecognition: false)
                    } else if error != nil {
                        self.finishSession(cancelRecognition: false)
                        onFailure(.recognitionFailed)
                    }
                } else if error != nil {
                    self.finishSession(cancelRecognition: false)
                    onFailure(.recognitionFailed)
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            finishSession(cancelRecognition: true)
            throw SpeechCaptureFailure.audioInputUnavailable
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .began else { return }
            Task { @MainActor in
                guard let self, self.sessionID == sessionID else { return }
                self.finishSession(cancelRecognition: true)
                onFailure(.interrupted)
            }
        }
    }

    func stop() {
        guard sessionID != nil else { return }
        stopAudioInput()
        request?.endAudio()
    }

    func cancel() {
        finishSession(cancelRecognition: true)
    }

    private func finishSession(cancelRecognition: Bool) {
        sessionID = nil
        stopAudioInput()
        request?.endAudio()
        if cancelRecognition {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        request = nil
        removeInterruptionObserver()
        deactivateAudioSession()
    }

    private func stopAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

@MainActor
final class DailyNoteSpeechController: ObservableObject {
    enum State: Equatable {
        case ready
        case requestingPermission
        case listening
        case stopping
        case reviewRequired
        case denied
        case restricted
        case unsupportedLocale
        case unsupportedDevice
        case unavailable
        case failed(String)
    }

    private struct Fragment: Equatable {
        let transcript: String
        let audioRange: SpeechCaptureAudioRange?
    }

    @Published private(set) var state: State = .ready
    @Published private(set) var partialTranscript = ""
    @Published private(set) var earlierUnfinalisedTranscript = ""
    @Published private(set) var reviewTranscript = ""
    @Published private(set) var reviewErrorMessage: String?
    @Published private(set) var noticeMessage: String?

    private let capture: any OnDeviceSpeechCapturing
    private let appendFinalTranscript: (String) -> String?
    private var cycleID: UUID?
    private var activePartial: Fragment?
    private var settledPartial: Fragment?
    private var supersededFragments: [Fragment] = []

    init(
        capture: any OnDeviceSpeechCapturing,
        appendFinalTranscript: @escaping (String) -> String?
    ) {
        self.capture = capture
        self.appendFinalTranscript = appendFinalTranscript
        refreshState()
    }

    var isMicrophoneEnabled: Bool {
        switch state {
        case .ready, .listening:
            return true
        default:
            return false
        }
    }

    var canOpenPermissionSettings: Bool {
        state == .denied
    }

    var canRetryAvailability: Bool {
        switch state {
        case .unavailable, .failed:
            return true
        default:
            return false
        }
    }

    var hasReviewTranscript: Bool {
        state == .reviewRequired
    }

    var statusMessage: String {
        switch state {
        case .ready:
            return capture.permission == .notDetermined
                ? "Tap the microphone to request access and dictate on device."
                : "Ready for on-device dictation."
        case .requestingPermission:
            return "Waiting for microphone and speech-recognition permission."
        case .listening where !earlierUnfinalisedTranscript.isEmpty:
            return "A pause changed the live transcript. Earlier speech is retained; tap Stop when you finish."
        case .listening:
            return "Listening on device… Tap Stop when you finish."
        case .stopping:
            return "Finishing the on-device transcript…"
        case .reviewRequired:
            return "Review the recognised text below before adding or discarding it."
        case .denied:
            return "Microphone or speech-recognition access is denied. You can keep typing or enable access in Settings."
        case .restricted:
            return "Speech recognition is restricted on this device. Typed notes remain available."
        case .unsupportedLocale:
            return "On-device speech recognition is not available for this locale. Typed notes remain available."
        case .unsupportedDevice:
            return "This device cannot provide the required on-device recognition. Server recognition is never used."
        case .unavailable:
            return "On-device speech recognition is temporarily unavailable. Typed notes remain available."
        case .failed(let message):
            return message
        }
    }

    func toggle() async {
        switch state {
        case .listening:
            state = .stopping
            capture.stop()
        case .ready:
            await start()
        default:
            break
        }
    }

    func updateReviewTranscript(_ transcript: String) {
        guard state == .reviewRequired else { return }
        reviewTranscript = transcript
        reviewErrorMessage = nil
    }

    @discardableResult
    func acceptReviewTranscript() -> Bool {
        guard state == .reviewRequired else { return false }
        let transcript = reviewTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            reviewErrorMessage = "Recognised text cannot be empty. Edit it or discard it."
            return false
        }
        if let rejection = appendFinalTranscript(transcript) {
            reviewErrorMessage = rejection
            return false
        }
        reviewTranscript = ""
        reviewErrorMessage = nil
        refreshState()
        return true
    }

    func discardReviewTranscript() {
        guard state == .reviewRequired else { return }
        reviewTranscript = ""
        reviewErrorMessage = nil
        refreshState()
    }

    func dismissNotice() {
        noticeMessage = nil
    }

    func stopForLifecycle() {
        cycleID = nil
        capture.cancel()
        if state == .reviewRequired, hasReviewTranscript {
            clearUnsafeTranscripts(includingReview: false)
            return
        }
        clearUnsafeTranscripts(includingReview: true)
        refreshState()
    }

    func retryAvailability() {
        guard state != .listening, state != .stopping, state != .reviewRequired else { return }
        refreshState()
    }

    private func start() async {
        refreshState()
        guard state == .ready else { return }

        noticeMessage = nil
        clearUnsafeTranscripts(includingReview: true)
        let cycleID = UUID()
        self.cycleID = cycleID
        if capture.permission != .authorized {
            state = .requestingPermission
            let permission = await capture.requestPermission()
            guard self.cycleID == cycleID else { return }
            apply(permission: permission)
            guard state == .ready else { return }
        }

        do {
            try capture.start(
                onUpdate: { [weak self] update in
                    self?.receive(update, cycleID: cycleID)
                },
                onFailure: { [weak self] failure in
                    self?.fail(failure, cycleID: cycleID)
                }
            )
            guard self.cycleID == cycleID else {
                capture.cancel()
                return
            }
            state = .listening
        } catch let failure as SpeechCaptureFailure {
            fail(failure, cycleID: cycleID)
        } catch {
            fail(.recognitionFailed, cycleID: cycleID)
        }
    }

    private func receive(_ update: SpeechCaptureUpdate, cycleID: UUID) {
        guard self.cycleID == cycleID,
              state == .listening || state == .stopping else { return }
        if update.isFinal {
            finish(with: update)
        } else {
            receivePartial(update)
        }
    }

    private func receivePartial(_ update: SpeechCaptureUpdate) {
        let transcript = update.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        let incoming = Fragment(transcript: transcript, audioRange: update.audioRange)

        if let settledPartial,
           isNewUtterance(after: settledPartial, incoming: incoming) {
            supersededFragments.append(settledPartial)
            earlierUnfinalisedTranscript = assemble(supersededFragments)
            self.settledPartial = nil
        }

        activePartial = incoming
        if incoming.audioRange != nil {
            settledPartial = incoming
        }
        partialTranscript = transcript
    }

    private func finish(with update: SpeechCaptureUpdate) {
        let finalTranscript = update.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalFragment = finalTranscript.isEmpty
            ? nil
            : Fragment(transcript: finalTranscript, audioRange: update.audioRange)
        cycleID = nil
        partialTranscript = ""

        var uncoveredFragments = supersededFragments
        if let finalFragment {
            uncoveredFragments.removeAll { fragment in
                finalCovers(fragment, final: finalFragment)
            }
        }

        let finalAppearsIncomplete = finalFragment.map { final in
            activePartial.map { active in
                finalDoesNotCoverActivePartial(final, active: active)
            } ?? false
        } ?? false

        if let finalFragment, uncoveredFragments.isEmpty, !finalAppearsIncomplete {
            clearUnsafeTranscripts(includingReview: false)
            appendOrHoldForLimit(finalFragment.transcript, showRecoveredNotice: false)
            return
        }

        var reviewFragments = uncoveredFragments
        if let finalFragment {
            reviewFragments.append(
                finalAppearsIncomplete ? (activePartial ?? finalFragment) : finalFragment
            )
        } else if let activePartial {
            reviewFragments.append(activePartial)
        } else if let settledPartial {
            reviewFragments.append(settledPartial)
        }

        let recoveredTranscript = assemble(reviewFragments)
        clearUnsafeTranscripts(includingReview: false)
        if recoveredTranscript.isEmpty {
            state = .failed("On-device recognition finished without usable text. Your typed draft was preserved.")
        } else {
            appendOrHoldForLimit(recoveredTranscript, showRecoveredNotice: true)
        }
    }

    private func appendOrHoldForLimit(_ transcript: String, showRecoveredNotice: Bool) {
        if let rejection = appendFinalTranscript(transcript) {
            reviewTranscript = transcript
            reviewErrorMessage = rejection
            state = .reviewRequired
            return
        }
        if showRecoveredNotice {
            noticeMessage = "Speech was added to the note above."
        }
        refreshState()
    }

    private func finalCovers(_ fragment: Fragment, final: Fragment) -> Bool {
        if let finalRange = final.audioRange,
           let fragmentRange = fragment.audioRange,
           finalRange.covers(fragmentRange) {
            return true
        }
        return beginsWithWords(final.transcript, prefix: fragment.transcript)
    }

    private func finalDoesNotCoverActivePartial(_ final: Fragment, active: Fragment) -> Bool {
        if let finalRange = final.audioRange,
           let activeRange = active.audioRange {
            return !finalRange.covers(activeRange)
        }
        return words(in: final.transcript).count < words(in: active.transcript).count
    }

    private func isNewUtterance(after settled: Fragment, incoming: Fragment) -> Bool {
        if let settledRange = settled.audioRange,
           let incomingRange = incoming.audioRange {
            return incomingRange.start > settledRange.end + 0.05
        }
        return !beginsWithWords(incoming.transcript, prefix: settled.transcript)
    }

    private func beginsWithWords(_ transcript: String, prefix: String) -> Bool {
        let transcriptWords = words(in: transcript)
        let prefixWords = words(in: prefix)
        guard !prefixWords.isEmpty, transcriptWords.count >= prefixWords.count else { return false }
        return transcriptWords.prefix(prefixWords.count).elementsEqual(prefixWords)
    }

    private func words(in transcript: String) -> [String] {
        transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func assemble(_ fragments: [Fragment]) -> String {
        fragments.reduce(into: "") { result, fragment in
            let transcript = fragment.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }
            if !result.isEmpty, result.last?.isWhitespace != true {
                result.append(" ")
            }
            result.append(transcript)
        }
    }

    private func clearUnsafeTranscripts(includingReview: Bool) {
        partialTranscript = ""
        earlierUnfinalisedTranscript = ""
        activePartial = nil
        settledPartial = nil
        supersededFragments = []
        if includingReview {
            reviewTranscript = ""
            reviewErrorMessage = nil
        }
    }

    private func fail(_ failure: SpeechCaptureFailure, cycleID: UUID) {
        guard self.cycleID == cycleID else { return }
        self.cycleID = nil
        capture.cancel()
        clearUnsafeTranscripts(includingReview: true)
        switch failure {
        case .audioInputUnavailable:
            state = .failed("The microphone input could not start. Your draft was preserved.")
        case .audioSessionUnavailable:
            state = .failed("Audio capture is unavailable. Your draft was preserved.")
        case .interrupted:
            state = .failed("Dictation was interrupted. Your draft and finalised text were preserved.")
        case .recognitionFailed:
            state = .failed("On-device recognition failed. Your draft was preserved; you can keep typing.")
        }
    }

    private func refreshState() {
        switch capture.availability {
        case .available:
            apply(permission: capture.permission)
        case .unsupportedLocale:
            state = .unsupportedLocale
        case .unsupportedDevice:
            state = .unsupportedDevice
        case .unavailable:
            state = .unavailable
        }
    }

    private func apply(permission: SpeechCapturePermission) {
        switch permission {
        case .notDetermined, .authorized:
            state = .ready
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        }
    }
}
