// PROCEDURAL: Bridges simulator microphone input to offline dictation on the same Mac.
#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import Foundation

@MainActor
final class SimulatorRouteSpeech {
    private let endpoint: URL
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private var fixture: URL?
    var needsMicrophone: Bool { fixture == nil }

    init?() {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--uitesting"),
              let index = process.arguments.firstIndex(of: "--qa-route-speech-port"),
              process.arguments.indices.contains(index + 1),
              let port = UInt16(process.arguments[index + 1]), port > 0,
              let url = URL(string: "http://127.0.0.1:\(port)/transcribe") else { return nil }
        endpoint = url
        fixture = process.environment["AIRBORDER_ROUTE_SPEECH_FIXTURE"].map { URL(fileURLWithPath: $0) }
    }

    func listen() async throws -> String {
        let audio: Data
        if let fixture {
            self.fixture = nil
            audio = try Data(contentsOf: fixture)
        } else {
            audio = try await recordQuestion()
        }
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audio
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SpeechError.unavailable }
        return try JSONDecoder().decode(String.self, from: data)
    }

    private func recordQuestion() async throws -> Data {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let recorder = try AVAudioRecorder(url: path, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
        ])
        defer {
            recorder.stop()
            try? FileManager.default.removeItem(at: path)
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw SpeechError.unavailable }
        var heardVoice = false
        var silencePolls = 0
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(100))
            guard recorder.isRecording else { continue }
            recorder.updateMeters()
            // The detector ends the turn after 0.9 seconds below the speech threshold.
            if recorder.averagePower(forChannel: 0) >= -40 {
                heardVoice = true
                silencePolls = 0
            } else if heardVoice {
                silencePolls += 1
                if silencePolls >= 9 { break }
            }
        }
        recorder.stop()
        guard heardVoice else { throw SpeechError.noSpeech }
        return try Data(contentsOf: path)
    }

    enum SpeechError: Error { case unavailable, noSpeech }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
#endif
