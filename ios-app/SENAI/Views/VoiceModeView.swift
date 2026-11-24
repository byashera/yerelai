import SwiftUI

// MARK: - ChatGPT / Gemini Live Style Hands-Free Auto-VAD Voice Mode

struct VoiceModeView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice = VoiceInputManager()

    @State private var lastTranscript: String = ""
    @State private var isMuted: Bool = false

    private enum LivePhase {
        case idle, listening, thinking, speaking
    }

    private var phase: LivePhase {
        if voice.isRecording { return .listening }
        if server.isGenerating { return .thinking }
        if server.speakingMessageId != nil { return .speaking }
        return .idle
    }

    private var statusTitle: String {
        switch phase {
        case .listening: return "Dinliyorum..."
        case .thinking: return "SEN.AI düşünüyor..."
        case .speaking: return "SEN.AI konuşuyor..."
        case .idle: return isMuted ? "Mikrofon kapalı" : "Konuşmaya hazır"
        }
    }

    private var primaryTint: Color {
        switch phase {
        case .listening: return Color(red: 0.96, green: 0.25, blue: 0.37)
        case .thinking: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .speaking: return Color(red: 0.06, green: 0.65, blue: 0.91)
        case .idle: return Color(red: 0.23, green: 0.51, blue: 0.96)
        }
    }

    private var secondaryTint: Color {
        switch phase {
        case .listening: return Color(red: 0.98, green: 0.57, blue: 0.24)
        case .thinking: return Color(red: 0.85, green: 0.27, blue: 0.94)
        case .speaking: return Color(red: 0.20, green: 0.83, blue: 0.60)
        case .idle: return Color(red: 0.49, green: 0.23, blue: 0.93)
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                if colorScheme == .dark {
                    Color(red: 0.035, green: 0.045, blue: 0.085)
                } else {
                    Color(red: 0.965, green: 0.972, blue: 0.992)
                }
                RadialGradient(
                    colors: [
                        primaryTint.opacity(colorScheme == .dark ? 0.28 : 0.16),
                        secondaryTint.opacity(colorScheme == .dark ? 0.14 : 0.08),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 340
                )
                .animation(.easeInOut(duration: 0.55), value: phase)
            }
            .ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Circle()
                            .fill(phase == .listening ? Color.red : (server.connectionRoute == .disconnected ? Color.orange : Color.green))
                            .frame(width: 7, height: 7)
                        Text("SEN.AI Live · \(server.activeModelName)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .senGlassCapsule(interactive: false)
                    Spacer()
                }
                .padding(.top, 14)

                Spacer()

                // Audio-Synchronized Morphing Liquid Plasma Orb
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let liveBoost: CGFloat = phase == .listening ? voice.audioLevel : (phase == .speaking ? CGFloat(0.35 + 0.35 * abs(sin(t * 5.2))) : 0.12)
                    let energy: Double = {
                        switch phase {
                        case .listening: return 0.9 + Double(liveBoost) * 1.4
                        case .speaking: return 1.15
                        case .thinking: return 0.95
                        case .idle: return 0.38
                        }
                    }()
                    let dynamicOrbSize: CGFloat = 162 + liveBoost * 34

                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            let wave = (t * (0.34 + energy * 0.22) + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
                            Circle()
                                .stroke(
                                    primaryTint.opacity((1.0 - wave) * (phase == .idle ? 0.15 : (0.28 + Double(liveBoost) * 0.32))),
                                    lineWidth: 1.5 + liveBoost * 1.2
                                )
                                .frame(width: 146 + CGFloat(wave) * (115 + liveBoost * 50), height: 146 + CGFloat(wave) * (115 + liveBoost * 50))
                        }

                        Canvas { ctx, size in
                            let cx = size.width / 2
                            let cy = size.height / 2
                            let baseR: CGFloat = 76 + liveBoost * 16

                            let blobs: [(CGFloat, CGFloat, CGFloat, Color)] = [
                                (CGFloat(sin(t * 1.5 * energy)) * (11 + liveBoost * 10), CGFloat(cos(t * 1.2 * energy)) * (10 + liveBoost * 8), baseR * 0.95, primaryTint.opacity(0.90)),
                                (CGFloat(cos(t * 1.8 * energy + 1.4)) * (13 + liveBoost * 10), CGFloat(sin(t * 1.4 * energy + 0.8)) * (11 + liveBoost * 9), baseR * 0.86, secondaryTint.opacity(0.82)),
                                (CGFloat(sin(t * 2.2 * energy + 2.6)) * 10, CGFloat(cos(t * 1.9 * energy + 2.0)) * 10, baseR * 0.70, Color.white.opacity(colorScheme == .dark ? 0.38 : 0.50)),
                            ]
                            for (dx, dy, r, col) in blobs {
                                let rr = r * (1.0 + liveBoost * 0.12)
                                let rect = CGRect(x: cx + dx - rr, y: cy + dy - rr, width: rr * 2, height: rr * 2)
                                ctx.fill(Path(ellipseIn: rect), with: .color(col))
                            }
                        }
                        .frame(width: 260, height: 260)
                        .blur(radius: 16)
                        .mask {
                            Circle()
                                .frame(width: dynamicOrbSize, height: dynamicOrbSize)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.75), Color.white.opacity(0.12), primaryTint.opacity(0.48)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.4
                                )
                                .frame(width: dynamicOrbSize, height: dynamicOrbSize)
                        }
                        .shadow(color: primaryTint.opacity(0.38 + Double(liveBoost) * 0.25), radius: 24 + liveBoost * 14, y: 10)
                    }
                    .frame(height: 270)
                    .contentShape(Circle())
                    .onTapGesture {
                        toggleMicAction()
                    }
                }

                // Real Audio-Reactive Spectrum Bars
                VoiceWaveformBars(
                    isActive: phase != .idle,
                    level: phase == .listening ? voice.audioLevel : (phase == .speaking ? 0.65 : 0.25),
                    tint: primaryTint
                )
                .frame(height: 36)

                VStack(spacing: 10) {
                    Text(statusTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(phase == .idle ? .primary : primaryTint)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.22), value: phase)

                    let previewText: String = {
                        if !voice.transcript.isEmpty { return "“\(voice.transcript)”" }
                        if let last = server.messages.last(where: { $0.role == "assistant" && !$0.content.isEmpty }) {
                            return String(last.content.prefix(140))
                        }
                        if !lastTranscript.isEmpty { return "“\(lastTranscript)”" }
                        return "Konuşmaya başlayın, durduğunuzda otomatik yanıtlanır."
                    }()

                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)
                }

                Spacer()

                SenGlassContainer(spacing: 20) {
                    HStack(spacing: 24) {
                        Button {
                            SenHaptics.light()
                            isMuted.toggle()
                            if isMuted {
                                voice.stopRecording(onFinal: nil)
                                server.stopSpeaking()
                            } else if !server.isGenerating {
                                beginHandsFreeListen()
                            }
                        } label: {
                            Image(systemName: isMuted ? "mic.slash.fill" : "speaker.slash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isMuted ? .orange : .primary)
                                .frame(width: 54, height: 54)
                        }
                        .buttonStyle(SenSpringButtonStyle())
                        .senGlassCircle(interactive: true)
                        .accessibilityLabel(isMuted ? "Mikrofonu Aç" : "Sustur")

                        Button {
                            toggleMicAction()
                        } label: {
                            Image(systemName: voice.isRecording ? "arrow.up" : "mic.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 74, height: 74)
                                .background {
                                    Circle()
                                        .fill(LinearGradient(colors: [primaryTint, secondaryTint], startPoint: .topLeading, endPoint: .bottomTrailing))
                                }
                                .shadow(color: primaryTint.opacity(0.42), radius: 14, y: 5)
                        }
                        .buttonStyle(SenSpringButtonStyle())
                        .accessibilityLabel(voice.isRecording ? "Gönder" : "Konuş")

                        Button {
                            SenHaptics.light()
                            voice.stopRecording(onFinal: nil)
                            server.stopSpeaking()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 54, height: 54)
                        }
                        .buttonStyle(SenSpringButtonStyle())
                        .senGlassCircle(interactive: true)
                        .accessibilityLabel("Kapat")
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            if !isMuted && !server.isGenerating {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    beginHandsFreeListen()
                }
            }
        }
        .onChange(of: server.speakingMessageId) { oldVal, newVal in
            // Auto-resume listening once AI finishes speaking
            if oldVal != nil && newVal == nil && !isMuted && !server.isGenerating {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if !voice.isRecording && !isMuted && !server.isGenerating {
                        beginHandsFreeListen()
                    }
                }
            }
        }
        .onDisappear {
            voice.stopRecording(onFinal: nil)
            server.stopSpeaking()
        }
    }

    private func beginHandsFreeListen() {
        server.stopSpeaking()
        voice.startAutoListening(
            onPartial: { partial in
                lastTranscript = partial
            },
            onAutoFinal: { finalTxt in
                lastTranscript = finalTxt
                server.sendMessage(finalTxt, autoSpeak: true)
            }
        )
    }

    private func toggleMicAction() {
        SenHaptics.medium()
        isMuted = false
        if voice.isRecording {
            voice.stopRecording { finalTxt in
                lastTranscript = finalTxt
                server.sendMessage(finalTxt, autoSpeak: true)
            }
        } else {
            beginHandsFreeListen()
        }
    }
}

private struct VoiceWaveformBars: View {
    let isActive: Bool
    let level: CGFloat
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<13, id: \.self) { i in
                    let distFromCenter = abs(Double(i) - 6.0)
                    let centerEnvelope = max(0.28, 1.0 - distFromCenter * 0.11)
                    let phase = Double(i) * 0.58
                    let rawWave = 0.35 + 0.65 * abs(sin(t * 5.2 + phase))
                    let amplitude = isActive
                        ? max(0.18, Double(level) * rawWave * centerEnvelope)
                        : (0.14 + 0.08 * abs(sin(t * 1.4 + phase))) * centerEnvelope
                    Capsule()
                        .fill(tint.opacity(isActive ? (0.55 + Double(level) * 0.45) : 0.30))
                        .frame(width: 4, height: max(6, CGFloat(amplitude) * 34))
                        .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.72), value: level)
                }
            }
        }
    }
}
