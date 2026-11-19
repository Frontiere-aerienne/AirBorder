// SUBSTANTIVE: Runs a bounded route conversation using only on-device speech.
import AVFoundation
import Speech
import SwiftUI

@MainActor
final class RouteVoiceSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, preparing, listening, speaking, unavailable }

    @Published private(set) var state: State = .idle
    @Published private(set) var answer: String?
    private let speech = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognition: SFSpeechRecognitionTask?
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var sessionActive = false
    private var hasTap = false
    private var generation = UUID()
    private var endOfPhrase: Task<Void, Never>?
    private var idleTimeout: Task<Void, Never>?
    private var lastPhrase = ""
    private var conversation = RouteVoiceConversation()
    private var guidance: (() -> RouteVoiceConversation.Guidance)?
    private var utterance: AVSpeechUtterance?
    #if DEBUG && targetEnvironment(simulator)
    private let simulatorSpeech = SimulatorRouteSpeech()
    private var listenTask: Task<Void, Never>?
    #endif

    var isActive: Bool { state == .preparing || state == .listening || state == .speaking }

    func start(guidance: @escaping () -> RouteVoiceConversation.Guidance) {
        guard !isActive else { return }
        generation = UUID()
        let token = generation
        self.guidance = guidance
        answer = nil
        conversation = RouteVoiceConversation()
        state = .preparing
        speech.delegate = self

        Task {
            guard token == generation else { return }
            #if DEBUG && targetEnvironment(simulator)
            if simulatorSpeech != nil {
                listen()
                return
            }
            #endif
            guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                fail("Voice is unavailable on this device.", token: token)
                return
            }
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard token == generation else { return }
            guard authorization == .authorized else {
                fail("Allow speech access in Settings to talk.", token: token)
                return
            }
            guard await AVAudioApplication.requestRecordPermission() else {
                fail("Allow microphone access in Settings to talk.", token: token)
                return
            }
            guard token == generation else { return }
            listen()
        }
    }

    func stop() {
        generation = UUID()
        state = .idle
        closeMicrophone()
        utterance = nil
        speech.stopSpeaking(at: .immediate)
        guidance = nil
        answer = nil
        deactivateAudio()
    }

    /// Withdraw spoken guidance and visible answers when the journey changes underneath them.
    func invalidateGuidance() {
        answer = nil
        if state == .speaking {
            utterance = nil
            speech.stopSpeaking(at: .immediate)
            listen()
        }
    }

    private func listen() {
        let token = UUID()
        generation = token
        #if DEBUG && targetEnvironment(simulator)
        if let simulatorSpeech {
            listenOnSimulator(using: simulatorSpeech, token: token)
            return
        }
        #endif
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            fail("Voice is unavailable on this device.", token: token)
            return
        }
        do {
            try activateAudio()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("Microphone unavailable.", token: token)
                return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = ["Which gate?", "What’s next?", "Repeat that", "What about now?"]
            audioRequest = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasTap = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let phrase = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = error != nil
                Task { @MainActor in self?.heard(phrase, final: final, failed: failed, token: token) }
            }
            engine.prepare()
            try engine.start()
            lastPhrase = ""
            state = .listening
            idleTimeout = Task { [weak self] in
                guard (try? await Task.sleep(for: .seconds(12))) != nil, let self, generation == token else { return }
                stop()
            }
        } catch {
            fail("Microphone unavailable.", token: token)
        }
    }

    private func activateAudio() throws {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        sessionActive = true
    }

    #if DEBUG && targetEnvironment(simulator)
    private func listenOnSimulator(using input: SimulatorRouteSpeech, token: UUID) {
        // Once the recording ends, the Mac returns text. The answer still uses the app's
        // current gate and instruction, exactly as it does with the iPhone's recognizer.
        listenTask = Task {
            do {
                if input.needsMicrophone {
                    guard await AVAudioApplication.requestRecordPermission() else {
                        fail("Allow microphone access in Settings to talk.", token: token)
                        return
                    }
                    guard generation == token else { return }
                    try activateAudio()
                }
                state = .listening
                let phrase = try await input.listen().trimmingCharacters(in: .whitespacesAndNewlines)
                if phrase.isEmpty { fail("Couldn’t hear you. Tap Talk to try again.", token: token) }
                else { reply(to: phrase, token: token) }
            } catch SimulatorRouteSpeech.SpeechError.noSpeech {
                fail("Couldn’t hear you. Tap Talk to try again.", token: token)
            } catch {
                fail("Voice is unavailable on this device.", token: token)
            }
        }
    }
    #endif

    private func heard(_ phrase: String?, final: Bool, failed: Bool, token: UUID) {
        guard generation == token, state == .listening else { return }
        if let phrase, !phrase.isEmpty {
            if final {
                reply(to: phrase, token: token)
            } else if phrase != lastPhrase {
                lastPhrase = phrase
                endOfPhrase?.cancel()
                endOfPhrase = Task { [weak self] in
                    guard (try? await Task.sleep(for: .milliseconds(950))) != nil else { return }
                    self?.reply(to: phrase, token: token)
                }
            }
        } else if failed {
            if lastPhrase.isEmpty {
                fail("Couldn’t hear you. Tap Talk to try again.", token: token)
            } else {
                reply(to: lastPhrase, token: token)
            }
        }
    }

    private func reply(to phrase: String, token: UUID) {
        guard generation == token, state == .listening, let guidance else { return }
        let snapshot = guidance()
        let text = conversation.answer(phrase, using: snapshot)
        answer = text
        state = .speaking
        closeMicrophone()
        let spokenGate = snapshot.gate.map(String.init).joined(separator: " ")
        let spoken = text.replacingOccurrences(of: "Gate \(snapshot.gate)", with: "Gate \(spokenGate)",
                                               options: .caseInsensitive)
        let next = AVSpeechUtterance(string: spoken)
        utterance = next
        speech.speak(next)
    }

    private func closeMicrophone() {
        #if DEBUG && targetEnvironment(simulator)
        listenTask?.cancel()
        listenTask = nil
        #endif
        endOfPhrase?.cancel()
        idleTimeout?.cancel()
        if engine.isRunning { engine.stop() }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        audioRequest?.endAudio()
        recognition?.cancel()
        recognition = nil
        audioRequest = nil
    }

    private func deactivateAudio() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    private func fail(_ message: String, token: UUID) {
        guard generation == token else { return }
        stop()
        answer = message
        state = .unavailable
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.utterance === utterance, state == .speaking else { return }
            self.utterance = nil
            listen()
        }
    }
}
