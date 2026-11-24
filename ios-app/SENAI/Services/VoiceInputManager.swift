import AVFoundation
import Foundation
import Speech

@MainActor
final class VoiceInputManager: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var transcript: String = ""
    @Published var audioLevel: CGFloat = 0.0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastSpeechActivity: Date = Date()
    private var autoSubmitHandler: ((String) -> Void)?

    func toggleRecording(onResult: @escaping (String) -> Void) {
        if isRecording {
            stopRecording(onFinal: onResult)
        } else {
            startRecording(autoSubmitOnSilence: false, onPartial: onResult, onAutoFinal: nil)
        }
    }

    func startAutoListening(onPartial: @escaping (String) -> Void, onAutoFinal: @escaping (String) -> Void) {
        startRecording(autoSubmitOnSilence: true, onPartial: onPartial, onAutoFinal: onAutoFinal)
    }

    private func startRecording(
        autoSubmitOnSilence: Bool,
        onPartial: @escaping (String) -> Void,
        onAutoFinal: ((String) -> Void)?
    ) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self, status == .authorized else { return }
                self.beginEngine(autoSubmitOnSilence: autoSubmitOnSilence, onPartial: onPartial, onAutoFinal: onAutoFinal)
            }
        }
    }

    private func beginEngine(
        autoSubmitOnSilence: Bool,
        onPartial: @escaping (String) -> Void,
        onAutoFinal: ((String) -> Void)?
    ) {
        stopRecording(onFinal: nil)
        transcript = ""
        audioLevel = 0
        lastSpeechActivity = Date()
        autoSubmitHandler = autoSubmitOnSilence ? onAutoFinal : nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            recognitionRequest = req

            let inputNode = audioEngine.inputNode
            let fmt = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
                req.append(buffer)
                guard let chData = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                guard count > 0 else { return }
                var sum: Float = 0
                for i in 0..<count {
                    let s = chData[i]
                    sum += s * s
                }
                let rms = sqrt(sum / Float(count))
                let normalized = CGFloat(min(1.0, max(0.0, (rms - 0.008) * 9.5)))
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.audioLevel = self.audioLevel * 0.45 + normalized * 0.55
                    if normalized > 0.08 {
                        self.lastSpeechActivity = Date()
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            SenHaptics.light()

            if autoSubmitOnSilence {
                silenceTimer?.invalidate()
                silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRecording else { return }
                        let clean = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty else { return }
                        if Date().timeIntervalSince(self.lastSpeechActivity) >= 1.55 {
                            let handler = self.autoSubmitHandler
                            self.autoSubmitHandler = nil
                            self.stopRecording(onFinal: handler)
                        }
                    }
                }
            }

            recognitionTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let nextTxt = result.bestTranscription.formattedString
                        if nextTxt != self.transcript {
                            self.transcript = nextTxt
                            self.lastSpeechActivity = Date()
                            onPartial(nextTxt)
                        }
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        let handler = self.autoSubmitHandler
                        self.autoSubmitHandler = nil
                        self.stopRecording(onFinal: handler)
                    }
                }
            }
        } catch {
            isRecording = false
            audioLevel = 0
        }
    }

    func stopRecording(onFinal: ((String) -> Void)?) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        autoSubmitHandler = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioLevel = 0
        if isRecording {
            isRecording = false
            let finalClean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalClean.isEmpty {
                onFinal?(finalClean)
            }
        }
    }
}
