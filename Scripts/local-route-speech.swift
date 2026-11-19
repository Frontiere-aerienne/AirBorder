// PROCEDURAL: Transcribes a simulator audio file with macOS's on-device dictation.
import AVFoundation
import Foundation
import Speech

@main
struct LocalRouteSpeech {
    static func main() async throws {
        let locale = Locale(identifier: "en-US")
        let transcriber = DictationTranscriber(locale: locale, preset: .shortDictation)
        if CommandLine.arguments.dropFirst() == ["--prepare"] {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw SpeechSetupError.modelUnavailable
            }
            return
        }
        guard CommandLine.arguments.count == 2 else { throw SpeechSetupError.missingAudio }
        let audio = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let transcript = read(transcriber)
        try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
        let text = try await transcript
        FileHandle.standardOutput.write(try JSONEncoder().encode(text))
    }

    static func read(_ transcriber: DictationTranscriber) async throws -> String {
        var final = ""
        var latest = ""
        for try await result in transcriber.results {
            latest = String(result.text.characters)
            if result.isFinal { final = latest }
        }
        return final.isEmpty ? latest : final
    }

    enum SpeechSetupError: Error { case missingAudio, modelUnavailable }
}
