import AVFoundation
import Foundation
import Speech

@MainActor
final class VoiceInputManager: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var transcript: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func toggleRecording(onResult: @escaping (String) -> Void) {
        if isRecording {
            stopRecording(onFinal: onResult)
        } else {
            startRecording(onPartial: onResult)
        }
    }

    private func startRecording(onPartial: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self, status == .authorized else { return }
                self.beginEngine(onPartial: onPartial)
            }
        }
    }

    private func beginEngine(onPartial: @escaping (String) -> Void) {
        stopRecording(onFinal: nil)
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            recognitionRequest = req

            let inputNode = audioEngine.inputNode
            let fmt = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, _ in
                req.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            SenHaptics.medium()

            recognitionTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        onPartial(self.transcript)
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stopRecording(onFinal: nil)
                    }
                }
            }
        } catch {
            isRecording = false
        }
    }

    func stopRecording(onFinal: ((String) -> Void)?) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if isRecording {
            isRecording = false
            if !transcript.isEmpty {
                onFinal?(transcript)
            }
        }
    }
}
