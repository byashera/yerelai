import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var server: ServerManager
    @StateObject private var voice = VoiceInputManager()

    var initialPreviewScreen: String? = nil

    @State private var draft: String = ""
    @State private var showSidebar: Bool = false
    @State private var showSettings: Bool = false
    @State private var showModelSheet: Bool = false
    @State private var activeSources: [WebSource]? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                SenAmbientBackground()

                VStack(spacing: 0) {
                    if server.connectionRoute == .disconnected && !server.isConnecting {
                        floatingOfflinePill
                    }

                    if server.messages.isEmpty {
                        welcomeHero
                    } else {
                        messageStream
                    }

                    floatingComposer
                }
            }
            .onAppear {
                if initialPreviewScreen == "sidebar" {
                    showSidebar = true
                } else if initialPreviewScreen == "settings" {
                    showSettings = true
                } else if initialPreviewScreen == "models" {
                    showModelSheet = true
                } else if initialPreviewScreen == "sources" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        activeSources = server.messages.last?.webSources
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        SenHaptics.light()
                        showSidebar = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("Sohbet Geçmişi")
                }

                ToolbarItem(placement: .principal) {
                    modelPickerMenu
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        server.startNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Yeni Sohbet")
                }
            }
            .sheet(isPresented: $showSidebar) {
                SidebarView(showSettings: $showSettings)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showModelSheet) {
                ModelPickerSheetView(showSettings: $showSettings)
                    .presentationDetents([.height(360), .medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: Binding(
                get: { activeSources.map { SourcesSheetWrapper(sources: $0) } },
                set: { activeSources = $0?.sources }
            )) { wrapper in
                SourcesSheetView(sources: wrapper.sources)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Native iOS 26 Toolbar Model & Thinking Sheet Trigger

    private var modelPickerMenu: some View {
        Button {
            SenHaptics.light()
            showModelSheet = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                Text("SEN.AI")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var statusDotColor: Color {
        switch server.connectionRoute {
        case .lan: return .green
        case .cloudflare, .custom: return .blue
        case .disconnected: return .orange
        }
    }

    private var turkishGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 5 && h < 12 { return "Günaydın," }
        if h >= 12 && h < 18 { return "İyi günler," }
        if h >= 18 && h < 23 { return "İyi akşamlar," }
        return "İyi geceler,"
    }

    // MARK: - Flagship 2x2 Bento Welcome Hero

    private var welcomeHero: some View {
        VStack(spacing: 22) {
            Spacer()

            SenPrismOrb(size: 64)

            VStack(spacing: 6) {
                Text(turkishGreeting)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("birlikte ne çözelim?")
                    .font(.title.weight(.bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.primary, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .multilineTextAlignment(.center)
                Text(server.connectionRoute == .disconnected ? "Sunucu bekleniyor · Ayarlar'dan bağlanın" : "\(server.connectionRoute.rawValue) · \(server.activeModelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                bentoCard(
                    title: "Hava Durumu",
                    subtitle: "5 günlük canlı tahmin",
                    icon: "cloud.sun.fill",
                    tint: .blue,
                    prompt: "Manisa hava durumu nasıl?"
                )
                bentoCard(
                    title: "Film Önerisi",
                    subtitle: "Puanlı görsel liste",
                    icon: "film.fill",
                    tint: .orange,
                    prompt: "Bana sürükleyici bir bilim kurgu filmi öner"
                )
                bentoCard(
                    title: "Burç Uyumu",
                    subtitle: "Yüzdelik analiz kartı",
                    icon: "heart.fill",
                    tint: .pink,
                    prompt: "Oğlak ve Akrep uyumu nasıl olur?"
                )
                bentoCard(
                    title: "Hızlı Plan",
                    subtitle: "Tıklanabilir adımlar",
                    icon: "checklist",
                    tint: .green,
                    prompt: "Hafta sonu için 1 günlük verimli rutin planı yap"
                )
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .onTapGesture { inputFocused = false }
    }

    private func bentoCard(title: String, subtitle: String, icon: String, tint: Color, prompt: String) -> some View {
        Button {
            server.sendMessage(prompt)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(tint.opacity(0.14))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
        }
        .buttonStyle(.plain)
        .senGlassRounded(radius: 18, interactive: true)
    }

    // MARK: - Messages Stream

    private var messageStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(server.messages) { msg in
                        MessageRowView(
                            msg: msg,
                            onShowSources: { srcs in activeSources = srcs }
                        )
                        .id(msg.id)
                    }
                    if !server.statusLine.isEmpty {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini)
                            Text(server.statusLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    Color.clear.frame(height: 12).id("BOTTOM_ANCHOR")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .senSoftScrollEdge()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: server.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Floating iOS 26 Liquid Glass Composer

    private var floatingComposer: some View {
        VStack(spacing: 6) {
            if server.webSearchEnabled {
                HStack {
                    Button {
                        SenHaptics.light()
                        server.webSearchEnabled = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .foregroundStyle(.blue)
                            Text("Araştır")
                                .foregroundStyle(.primary)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .senGlassCapsule(interactive: true)
                    Spacer()
                }
                    .padding(.horizontal, 58)
            }

            SenGlassContainer(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    Menu {
                        Button {
                            server.webSearchEnabled.toggle()
                        } label: {
                            Label(
                                server.webSearchEnabled ? "Web Araştırmasını Kapat" : "Web Araştırmasını Aç",
                                systemImage: "globe"
                            )
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("Ayarlar", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .senGlassCircle(interactive: true)

                    HStack(alignment: .bottom, spacing: 6) {
                        TextField("SEN.AI'ya bir şey sor...", text: $draft, axis: .vertical)
                            .lineLimit(1...5)
                            .font(.body)
                            .focused($inputFocused)
                            .padding(.vertical, 8)
                            .padding(.leading, 12)

                        Button {
                            voice.toggleRecording { text in
                                draft = text
                            }
                        } label: {
                            Image(systemName: voice.isRecording ? "waveform.circle.fill" : "mic")
                                .font(.system(size: 18))
                                .foregroundStyle(voice.isRecording ? .red : .secondary)
                                .frame(width: 34, height: 34)
                        }
                        .padding(.bottom, 2)
                        .padding(.trailing, 4)
                    }
                    .senGlassCapsule(interactive: false)

                    if server.isGenerating {
                        Button {
                            server.stopGeneration()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background { Circle().fill(Color.red) }
                        }
                        .accessibilityLabel("Durdur")
                    } else {
                        let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button {
                            let text = draft
                            draft = ""
                            inputFocused = false
                            server.sendMessage(text)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(isEmpty ? Color.secondary : Color.white)
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        .senGlassCircle(interactive: true, tint: isEmpty ? nil : .blue)
                        .disabled(isEmpty)
                        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isEmpty)
                        .accessibilityLabel("Gönder")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .padding(.top, 4)
            }
        }
    }

    private var floatingOfflinePill: some View {
        HStack {
            Button {
                SenHaptics.light()
                Task { await server.bootstrap() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Çevrimdışı")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("· Bağlan")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .senGlassCapsule(interactive: true)
        }
        .padding(.top, 6)
    }
}

// MARK: - Single Message Row

struct MessageRowView: View {
    @EnvironmentObject private var server: ServerManager
    let msg: ChatMessage
    let onShowSources: ([WebSource]) -> Void
    @State private var showThinking: Bool = false

    var body: some View {
        if msg.role == "user" {
            HStack {
                Spacer(minLength: 52)
                Text(msg.content)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.16), Color.indigo.opacity(0.11)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.6)
                            }
                    }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let persona = msg.autoPersona, !persona.isEmpty {
                    Text("Uzman: \(persona)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(.secondary.opacity(0.12)) }
                }

                // Server Rich Cards (Weather / Finance)
                ForEach(msg.richCards) { rc in
                    if rc.kind == "weather" {
                        WeatherCardView(card: rc)
                    } else if rc.kind == "finance" {
                        FinanceCardView(card: rc)
                    }
                }

                // Compact 1-line "Düşünüyor" disclosure
                if !msg.thinking.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { showThinking.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text(msg.isStreaming ? "Düşünüyor · \(String(format: "%.1fs", msg.thinkingSeconds))" : "Düşünme süreci")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(msg.isStreaming ? .blue : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule().fill(.secondary.opacity(0.10))
                            }
                        }
                        .buttonStyle(.plain)

                        if showThinking {
                            Text(msg.thinking)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 2)
                                }
                        }
                    }
                }

                // Markdown + Inline Rich Cards (Zero-Flash)
                let segments = MarkdownCardParser.parse(msg.content, isStreaming: msg.isStreaming)
                ForEach(segments) { seg in
                    switch seg {
                    case .markdown(let txt):
                        Text(markdownAttributed(txt))
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    case .cardLoading:
                        CardLoadingPlaceholder()
                    case .visualCard(let card):
                        SenVisualCardView(card: card)
                    }
                }

                if msg.isStreaming && !msg.content.isEmpty {
                    SenStreamingDot()
                        .padding(.top, 2)
                }

                // Bottom Action Bar + Right-Aligned Liquid Glass "🌐 N kaynak" Capsule
                if !msg.isStreaming && !msg.content.isEmpty {
                    HStack(spacing: 14) {
                        Button {
                            Task { await server.toggleSpeak(messageId: msg.id, text: msg.content) }
                        } label: {
                            Image(systemName: server.speakingMessageId == msg.id ? "stop.circle.fill" : "speaker.wave.2")
                                .foregroundStyle(server.speakingMessageId == msg.id ? .blue : .secondary)
                        }

                        Button {
                            UIPasteboard.general.string = msg.content
                            SenHaptics.light()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await server.rateMessage(msg.id, rating: "like") }
                        } label: {
                            Image(systemName: msg.rating == "like" ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .foregroundStyle(msg.rating == "like" ? .green : .secondary)
                        }

                        Button {
                            Task { await server.rateMessage(msg.id, rating: "dislike") }
                        } label: {
                            Image(systemName: msg.rating == "dislike" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .foregroundStyle(msg.rating == "dislike" ? .red : .secondary)
                        }

                        Spacer()

                        if !msg.webSources.isEmpty {
                            Button {
                                SenHaptics.light()
                                onShowSources(msg.webSources)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "globe")
                                    Text("\(msg.webSources.count) kaynak")
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .senGlassCapsule(interactive: true, tint: .blue)
                        }
                    }
                    .font(.system(size: 15))
                    .padding(.top, 2)
                }
            }
        }
    }

    private func markdownAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct SourcesSheetWrapper: Identifiable {
    let id = UUID()
    let sources: [WebSource]
}

struct SourcesSheetView: View {
    let sources: [WebSource]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(sources) { src in
                if let url = URL(string: src.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(src.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(src.domain)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Web Kaynakları (\(sources.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Dedicated iOS 26 Liquid Glass Model & Thinking Picker Sheet

struct ModelPickerSheetView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Düşünme Seviyesi")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 6) {
                        ForEach(ThinkingEffort.allCases) { eff in
                            let active = server.thinkingEffort == eff
                            Button {
                                SenHaptics.light()
                                server.thinkingEffort = eff
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: eff.icon)
                                        .font(.caption.weight(.semibold))
                                    Text(eff.label)
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(active ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(active ? Color.blue : Color.primary.opacity(0.06))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktif Yerel Model")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(server.availableModels) { m in
                            let selected = server.selectedModelId == m.id
                            Button {
                                SenHaptics.light()
                                server.selectedModelId = m.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: m.id.contains("e4b") ? "sparkles" : "bolt.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(m.id.contains("e4b") ? .indigo : .blue)
                                        .frame(width: 36, height: 36)
                                        .background {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill((m.id.contains("e4b") ? Color.indigo : Color.blue).opacity(0.14))
                                        }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.name)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.primary)
                                        Text(m.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(12)
                                .background {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .fill(selected ? Color.blue.opacity(0.10) : Color.primary.opacity(0.05))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                                .strokeBorder(selected ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1)
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .navigationTitle("Model & Düşünme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showSettings = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
