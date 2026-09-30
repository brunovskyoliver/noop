import Foundation
import SwiftUI
import os
#if canImport(UIKit)
import UIKit
import Speech
#endif

/// K4: On-device speech-to-text wrapper for the Coach composer (iOS only).
///
/// Design contract (see PRD-K4):
/// - **No raw audio egress.** Recognition is requested with `requiresOnDeviceRecognition = true`
///   wherever the locale supports it. If a locale ONLY supports server recognition, voice is
///   **disabled** for that locale rather than falling back to server transcription — server
///   transcription would ship audio off-device, breaking the offline posture.
/// - The microphone button lives in the shared `CoachView` composer; on macOS this type is a
///   no-op (`isSupported` is `false`, all methods are inert) so the shared file keeps compiling.
/// - Only the resulting TEXT ever reaches the provider, via the same channel a typed question
///   already uses. No new network path is introduced.
///
/// Usage from `CoachView`:
/// 1. `voice.isSupported` gates whether the mic button is shown at all.
/// 2. `voice.authorizationStatus` drives the button's enabled / "open Settings" state.
/// 3. `voice.startTranscribing(partial:)` begins a session; `partial` is called on the main
///    actor with the live transcript.
/// 4. `voice.stopTranscribing(completion:)` finalizes and returns the final text.
@MainActor
final class CoachVoiceInput: ObservableObject {

    /// Session start, end and errors (never the words): what is missing when dictation misbehaves on a
    /// phone and nobody had a debugger attached. Console.app, subsystem = bundle id, category "dictation".
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "noop", category: "dictation")
    private var resultCount = 0

    /// Whether voice input is available on this device + locale at all.
    static var isSupported: Bool {
        #if canImport(UIKit)
        return SFSpeechRecognizer.authorizationStatus() != .restricted
            && SFSpeechRecognizer.self != nil
            && speechLocale != nil
        #else
        return false
        #endif
    }

    #if canImport(UIKit)
    /// Speech recognition and microphone authorization together, mapped to a simple enum the UI can switch
    /// on. Both grants are needed: with speech allowed and the microphone refused, every session is silent.
    var authorization: AuthorizationState {
        let speech = mapSpeech(SFSpeechRecognizer.authorizationStatus())
        guard speech == .authorized else { return speech }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .authorized
        case .denied: return .denied
        case .undetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }
    #else
    var authorization: AuthorizationState { .unavailable }
    #endif

    /// Whether a recognition session is currently recording.
    @Published private(set) var isRecording: Bool = false

    /// The whole session's transcript so far, across pauses. Not published: the screens take the text when
    /// dictation stops, so a result arriving mid-sentence re-renders nothing.
    private(set) var partialTranscript: String = ""

    /// The microphone's loudness for a voice-only screen's animation. A separate object, observed only by
    /// the view that draws it: published on this object it re-rendered the whole Coach screen about 40 times
    /// a second while dictating, and the recognizer's results queued behind those renders and never showed.
    let meter = CoachVoiceMeter()

    /// A short human-readable status for the disabled-state tooltip (e.g. "On-device speech not
    /// available for en-GB"). `nil` when voice is fully available.
    @Published var statusMessage: String?

    #if canImport(UIKit)
    /// The recognizer locale for the person's language and region (see `DictationLocale`).
    static var speechLocale: Locale? {
        let current = Locale.current
        let supported = SFSpeechRecognizer.supportedLocales().map(\.identifier)
        return DictationLocale.pick(language: current.language.languageCode?.identifier,
                                    region: current.region?.identifier, supported: supported).map(Locale.init(identifier:))
    }
    #endif

    /// On-device support for the current locale. If `false`, voice is disabled rather than
    /// falling back to server recognition (which would be raw-audio egress).
    private static var localeSupportsOnDevice: Bool {
        #if canImport(UIKit)
        guard let locale = speechLocale, let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.supportsOnDeviceRecognition
        #else
        return false
        #endif
    }

    /// True when voice can be used right now: supported, authorized, and locale supports on-device.
    var canUseVoice: Bool {
        guard Self.isSupported, authorization == .authorized, Self.localeSupportsOnDevice else {
            return false
        }
        return true
    }

    /// Request Speech + Microphone authorization. Safe to call repeatedly; the system no-ops if
    /// already decided. `completion` fires on the main actor.
    func requestAuthorization(completion: @escaping (AuthorizationState) -> Void) {
        #if canImport(UIKit)
        // Speech auth first; mic auth piggybacks on the same prompt flow but is a separate grant.
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            Task { @MainActor in
                if speechStatus != .authorized {
                    completion(self.mapSpeech(speechStatus))
                    return
                }
                // Mic permission is requested lazily by AVAudioEngine on iOS — but we ask up front
                // so the user sees one consolidated prompt and the button state is correct before
                // the first tap.
                self.requestMicPermission { micGranted in
                    completion(micGranted ? .authorized : .denied)
                }
            }
        }
        #else
        completion(.unavailable)
        #endif
    }

    /// Begin a recognition session. `partial` is invoked on the main actor with the live transcript
    /// as it streams in. `ended` receives the transcript when the session ends without `stopTranscribing`
    /// (an incoming call, Siri, a recognizer error), so what was said is not lost.
    /// No-op (calls `partial` with "") on macOS / unsupported locales.
    func startTranscribing(partial: @escaping (String) -> Void, ended: ((String) -> Void)? = nil) {
        #if canImport(UIKit)
        guard canUseVoice else {
            statusMessage = Self.localeSupportsOnDevice
                ? String(localized: "Voice input unavailable. Check microphone permission in Settings.")
                : String(localized: "On-device speech not available for \(Locale.current.identifier).")
            return
        }
        cancel()
        partialTranscript = ""
        statusMessage = nil
        endedHandler = ended
        beginSession(partial: partial)
        #else
        partial("")
        #endif
    }

    /// Stop the active session and return the finalized transcript via `completion` (main actor). The
    /// microphone stops at once; the completion waits briefly for the recognizer to finish the audio it
    /// already has, so the last words are not cut off.
    func stopTranscribing(completion: @escaping (String) -> Void) {
        #if canImport(UIKit)
        guard isRecording else {
            completion(partialTranscript)
            return
        }
        endedHandler = nil
        stopAudio()
        finishing = completion
        let token = sessionID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.finalResultTimeoutNanos)
            guard let self, self.sessionID == token else { return }
            self.finishSession(completion: nil)
        }
        #else
        completion("")
        #endif
    }

    /// End any session now and release the microphone, delivering nothing. For a screen going away.
    func cancel() {
        #if canImport(UIKit)
        guard isRecording || finishing != nil || audioEngine != nil else { return }
        finishing = nil
        endedHandler = nil
        finishSession(completion: nil)
        #endif
    }

    // MARK: - Private (iOS only)

    #if canImport(UIKit)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Bumped when a session ends. A recognition result is delivered through a main-actor hop, so one can
    /// arrive after the session stopped (the message already sent); results from an ended session are dropped.
    private var sessionID = 0
    private var transcript = DictationTranscript()
    /// A stop is waiting for the recognizer's final result; it receives the transcript once that arrives.
    private var finishing: ((String) -> Void)?
    /// Receives the transcript when the session ends by itself (see `startTranscribing`).
    private var endedHandler: ((String) -> Void)?
    /// How long a stop waits for the final result before giving up and using the last partial one.
    private static let finalResultTimeoutNanos: UInt64 = 1_500_000_000

    private func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .unavailable
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    private func requestMicPermission(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    private func beginSession(partial: @escaping (String) -> Void) {
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let request = SFSpeechAudioBufferRecognitionRequest()
        // K4 hard constraint: on-device ONLY. If the locale doesn't support it, voice is disabled
        // upstream — but we set the flag defensively here too so a regression can't slip audio out.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        guard let locale = Self.speechLocale, let recognizer = SFSpeechRecognizer(locale: locale) else {
            statusMessage = String(localized: "On-device speech not available for \(Locale.current.identifier).")
            return
        }

        let token = sessionID
        transcript = DictationTranscript()
        resultCount = 0
        Self.log.info("start locale=\(locale.identifier, privacy: .public) onDevice=\(recognizer.supportsOnDeviceRecognition, privacy: .public)")
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == token else { return }
                if let error {
                    Self.log.error("recognition error after \(self.resultCount, privacy: .public) results: \(String(describing: error), privacy: .public)")
                }
                if let result {
                    self.resultCount += 1
                    // After a pause the recognizer starts a new utterance and reports only its words; the
                    // accumulator keeps what came before (see `DictationTranscript`).
                    let text = self.transcript.update(result.bestTranscription.formattedString,
                                                      utteranceEnded: result.speechRecognitionMetadata != nil)
                    self.partialTranscript = text
                    partial(text)
                }
                if error != nil || (result?.isFinal ?? false) {
                    // Ended by the recognizer: a stop waiting on it, or the session ending by itself.
                    self.finishSession(completion: self.finishing == nil ? self.endedHandler : nil)
                }
            }
        }
        self.recognitionTask = task

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            // Metering only when a screen draws it, and at most every fourth buffer (about 12 a second).
            let drawn = meter.isEnabled ? meter : nil
            meter.session = token
            let counter = BufferCounter()
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
                guard let drawn, counter.next() % 4 == 0 else { return }
                let level = Self.level(of: buffer)
                Task { @MainActor in drawn.set(level, session: token) }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            Self.log.error("microphone failed to start: \(String(describing: error), privacy: .public)")
            statusMessage = String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            endedHandler = nil
            finishSession(completion: nil)
        }
    }

    /// RMS loudness of one buffer mapped to 0 to 1 (about -50 dB to -10 dB).
    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-7))
        return Double(min(max((db + 50) / 40, 0), 1))
    }

    /// Stop capturing and tell the recognizer no more audio is coming. The recognition task keeps running
    /// so it can deliver the final result for what it already has.
    private func stopAudio() {
        meter.set(0, session: meter.session)
        meter.session = -1
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
    }

    /// Tear the session down and deliver the transcript to a waiting stop, else to `completion`.
    private func finishSession(completion: ((String) -> Void)?) {
        let wasRecording = isRecording
        sessionID += 1
        stopAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        let final = partialTranscript
        let deliver = finishing ?? completion
        if wasRecording || finishing != nil {
            Self.log.info("end after \(self.resultCount, privacy: .public) results, \(final.count, privacy: .public) characters")
        }
        finishing = nil
        endedHandler = nil
        deliver?(final)
    }
    #endif

    /// Simplified authorization state the UI switches on (decoupled from SFSpeech symbols on macOS).
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
        case unavailable
    }
}

/// Microphone loudness, 0 to 1, for the voice-only journal's circle (see `CoachVoiceInput.meter`). Off until
/// a screen that draws it turns it on.
@MainActor
final class CoachVoiceMeter: ObservableObject {
    @Published private(set) var level: Double = 0
    var isEnabled = false
    /// The recording session the level belongs to; a late reading from an ended session is dropped.
    var session = -1

    func set(_ value: Double, session: Int) {
        guard session == self.session, value != level else { return }
        level = value
    }
}

/// Counts tap buffers on the audio thread (the tap runs on one thread at a time).
private final class BufferCounter: @unchecked Sendable {
    private var n = 0
    func next() -> Int { n += 1; return n }
}
