import SwiftUI

// MARK: - ChatGPT / Gemini Live Style Full-Screen Liquid Voice Mode

struct VoiceModeView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice = VoiceInputManager()

    @State private var lastTranscript: String = ""

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
        case .idle: return "Konuşmak için dokun"
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
            // Deep Immersive Live Backdrop with Reactive Glow
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
                .animation(.easeInOut(duration: 0.6), value: phase)
            }
            .ignoresSafeArea()

            VStack(spacing: 22) {
                // Top Live Pill
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

                // ChatGPT / Gemini Live Morphing Liquid Plasma Orb
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let energy: Double = {
                        switch phase {
                        case .listening: return 1.35
                        case .speaking: return 1.15
                        case .thinking: return 0.92
                        case .idle: return 0.42
                        }
                    }()

                    ZStack {
                        // Outer Expanding Audio Aura Rings
                        ForEach(0..<3, id: \.self) { i in
                            let wave = (t * (0.35 + energy * 0.25) + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
                            Circle()
                                .stroke(
                                    primaryTint.opacity((1.0 - wave) * (phase == .idle ? 0.18 : 0.38)),
                                    lineWidth: 1.6
                                )
                                .frame(width: 150 + CGFloat(wave) * 125, height: 150 + CGFloat(wave) * 125)
                        }

                        // Morphing Organic Fluid Plasma Sphere (Canvas)
                        Canvas { ctx, size in
                            let cx = size.width / 2
                            let cy = size.height / 2
                            let baseR: CGFloat = 78

                            // 3 overlapping drifting liquid blobs forming an organic ChatGPT/Gemini Live orb
                            let blobs: [(CGFloat, CGFloat, CGFloat, Color)] = [
                                (CGFloat(sin(t * 1.4 * energy)) * 12, CGFloat(cos(t * 1.1 * energy)) * 10, baseR * 0.94, primaryTint.opacity(0.88)),
                                (CGFloat(cos(t * 1.7 * energy + 1.4)) * 14, CGFloat(sin(t * 1.3 * energy + 0.8)) * 12, baseR * 0.86, secondaryTint.opacity(0.80)),
                                (CGFloat(sin(t * 2.1 * energy + 2.6)) * 10, CGFloat(cos(t * 1.8 * energy + 2.0)) * 11, baseR * 0.72, Color.white.opacity(colorScheme == .dark ? 0.35 : 0.48)),
                            ]
                            for (dx, dy, r, col) in blobs {
                                let breath = 1.0 + CGFloat(sin(t * 2.4 * energy)) * 0.055
                                let rr = r * breath
                                let rect = CGRect(x: cx + dx - rr, y: cy + dy - rr, width: rr * 2, height: rr * 2)
                                ctx.fill(Path(ellipseIn: rect), with: .color(col))
                            }
                        }
                        .frame(width: 240, height: 240)
                        .blur(radius: 16)
                        .mask {
                            Circle()
                                .frame(width: 168 + CGFloat(sin(t * 2.6 * energy)) * (phase == .idle ? 3 : 9),
                                       height: 168 + CGFloat(cos(t * 2.2 * energy)) * (phase == .idle ? 3 : 9))
                        }
                        .overlay {
                            // Crisp Liquid Glass Specular Rim on the Orb
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.75), Color.white.opacity(0.12), primaryTint.opacity(0.45)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.4
                                )
                                .frame(width: 168, height: 168)
                        }
                        .shadow(color: primaryTint.opacity(0.42), radius: 28, y: 10)
                    }
                    .frame(height: 270)
                    .contentShape(Circle())
                    .onTapGesture {
                        toggleMicAction()
                    }
                }

                // Smooth Live Equalizer Bars
                VoiceWaveformBars(
                    isActive: phase != .idle,
                    tint: primaryTint
                )
                .frame(height: 30)

                // Status & Live Subtitle
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
                        return "Türkçe olarak doğalca konuşabilirsin."
                    }()

                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)
                }

                Spacer()

                // Floating Liquid Glass Control Dock
                SenGlassContainer(spacing: 20) {
                    HStack(spacing: 24) {
                        Button {
                            SenHaptics.light()
                            server.stopSpeaking()
                            server.stopGeneration()
                        } label: {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 54, height: 54)
                        }
                        .buttonStyle(SenSpringButtonStyle())
                        .senGlassCircle(interactive: true)
                        .accessibilityLabel("Sesi Sustur")

                        Button {
                            toggleMicAction()
                        } label: {
                            Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
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
        .onDisappear {
            voice.stopRecording(onFinal: nil)
            server.stopSpeaking()
        }
    }

    private func toggleMicAction() {
        SenHaptics.medium()
        if voice.isRecording {
            voice.stopRecording { finalTxt in
                lastTranscript = finalTxt
                server.sendMessage(finalTxt, autoSpeak: true)
            }
        } else {
            server.stopSpeaking()
            voice.toggleRecording { partial in
                lastTranscript = partial
            }
        }
    }
}

private struct VoiceWaveformBars: View {
    let isActive: Bool
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<11, id: \.self) { i in
                    let centerBoost = 1.0 - abs(Double(i) - 5.0) * 0.12
                    let phase = Double(i) * 0.62
                    let wave = isActive
                        ? (0.28 + 0.72 * abs(sin(t * 4.6 + phase))) * centerBoost
                        : (0.18 + 0.14 * abs(sin(t * 1.4 + phase))) * centerBoost
                    Capsule()
                        .fill(tint.opacity(isActive ? 0.88 : 0.34))
                        .frame(width: 4, height: max(6, CGFloat(wave) * 28))
                }
            }
        }
    }
}
