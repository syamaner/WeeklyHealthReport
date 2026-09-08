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

struct SpeechCaptureUpdate: Equatable {
    let transcript: String
    let isFinal: Bool
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
                    onUpdate(SpeechCaptureUpdate(
                        transcript: result.bestTranscription.formattedString,
                        isFinal: result.isFinal
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
        case denied
        case restricted
        case unsupportedLocale
        case unsupportedDevice
        case unavailable
        case failed(String)
    }

    @Published private(set) var state: State = .ready
    @Published private(set) var partialTranscript = ""

    private let capture: any OnDeviceSpeechCapturing
    private let appendFinalTranscript: (String) -> String?
    private var cycleID: UUID?

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

    var statusMessage: String {
        switch state {
        case .ready:
            return capture.permission == .notDetermined
                ? "Tap the microphone to request access and dictate on device."
                : "Ready for on-device dictation."
        case .requestingPermission:
            return "Waiting for microphone and speech-recognition permission."
        case .listening:
            return "Listening on device… Tap Stop when you finish."
        case .stopping:
            return "Finishing the on-device transcript…"
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

    func stopForLifecycle() {
        cycleID = nil
        capture.cancel()
        partialTranscript = ""
        refreshState()
    }

    func retryAvailability() {
        guard state != .listening, state != .stopping else { return }
        refreshState()
    }

    private func start() async {
        refreshState()
        guard state == .ready else { return }

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
            partialTranscript = ""
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
            partialTranscript = ""
            self.cycleID = nil
            if let rejection = appendFinalTranscript(update.transcript) {
                state = .failed(rejection)
            } else {
                refreshState()
            }
        } else {
            partialTranscript = update.transcript
        }
    }

    private func fail(_ failure: SpeechCaptureFailure, cycleID: UUID) {
        guard self.cycleID == cycleID else { return }
        self.cycleID = nil
        capture.cancel()
        partialTranscript = ""
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
