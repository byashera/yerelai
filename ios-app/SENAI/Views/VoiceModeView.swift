import SwiftUI

// MARK: - Full-Screen Hands-Free Turkish Voice Conversation Mode

struct VoiceModeView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceInputManager()

    @State private var ripple: Bool = false
    @State private var lastTranscript: String = ""

    private var statusTitle: String {
        if voice.isRecording { return "Dinliyorum..." }
        if server.isGenerating { return "SEN.AI düşünüyor..." }
        if server.speakingMessageId != nil { return "SEN.AI konuşuyor..." }
        return "Konuşmak için mikrofona dokun"
    }

    private var statusTint: Color {
        if voice.isRecording { return .red }
        if server.isGenerating { return .indigo }
        if server.speakingMessageId != nil { return .blue }
        return .secondary
    }

    var body: some View {
        ZStack {
            SenAmbientBackground()

            VStack(spacing: 24) {
                // Top Header (centered status pill — bottom red button handles close)
                HStack {
                    Spacer()
                    HStack(spacing: 7) {
                        Circle()
                            .fill(server.connectionRoute == .disconnected ? Color.orange : Color.green)
                            .frame(width: 7, height: 7)
                        Text("SEN.AI · Sesli Sohbet")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .senGlassCapsule(interactive: false)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()

                // Center Audio-Reactive Prism Orb + Expanding Ripples
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                (voice.isRecording ? Color.red : Color.blue).opacity(ripple ? 0.0 : 0.28),
                                lineWidth: 1.5
                            )
                            .frame(width: 140 + CGFloat(i) * 44, height: 140 + CGFloat(i) * 44)
                            .scaleEffect(ripple ? 1.28 : 0.92)
                            .animation(
                                .easeOut(duration: 2.2)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.55),
                                value: ripple
                            )
                    }
                    SenPrismOrb(size: 118)
                        .scaleEffect(voice.isRecording ? 1.07 : (server.speakingMessageId != nil ? 1.04 : 1.0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: voice.isRecording)
                }
                .frame(height: 230)

                // Live Audio Waveform Visualizer
                VoiceWaveformBars(
                    isActive: voice.isRecording || server.isGenerating || server.speakingMessageId != nil,
                    tint: voice.isRecording ? .red : (server.isGenerating ? .indigo : .blue)
                )
                .frame(height: 28)

                // Live Status & Transcript Preview
                VStack(spacing: 10) {
                    Text(statusTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(statusTint == .secondary ? .primary : statusTint)

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

                // Bottom Liquid Glass Voice Controls
                SenGlassContainer(spacing: 18) {
                    HStack(spacing: 22) {
                        Button {
                            SenHaptics.light()
                            server.stopSpeaking()
                            server.stopGeneration()
                        } label: {
                            Image(systemName: "speaker.slash")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(SenSpringButtonStyle())
                        .senGlassCircle(interactive: true)
                        .accessibilityLabel("Sesi Sustur")

                        Button {
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
                        } label: {
                            Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                        }
                        .buttonStyle(SenSpringButtonStyle())
                        .senGlassCircle(interactive: true, tint: voice.isRecording ? .red : .blue)
                        .accessibilityLabel(voice.isRecording ? "Gönder" : "Konuş")

                        Button {
                            voice.stopRecording(onFinal: nil)
                            server.stopSpeaking()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(SenSpringButtonStyle())
                        .senGlassCircle(interactive: true)
                        .accessibilityLabel("Kapat")
                    }
                }
                .padding(.bottom, 26)
            }
        }
        .onAppear { ripple = true }
        .onDisappear {
            voice.stopRecording(onFinal: nil)
            server.stopSpeaking()
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
                ForEach(0..<9, id: \.self) { i in
                    let phase = Double(i) * 0.65
                    let wave = isActive
                        ? (0.32 + 0.68 * abs(sin(t * 4.4 + phase)))
                        : (0.22 + 0.16 * abs(sin(t * 1.4 + phase)))
                    Capsule()
                        .fill(tint.opacity(isActive ? 0.85 : 0.32))
                        .frame(width: 4, height: max(6, CGFloat(wave) * 26))
                }
            }
        }
    }
}
