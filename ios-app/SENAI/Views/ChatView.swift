import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var server: ServerManager
    @StateObject private var voice = VoiceInputManager()

    @State private var draft: String = ""
    @State private var showSidebar: Bool = false
    @State private var showSettings: Bool = false
    @State private var activeSources: [WebSource]? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                SenAmbientBackground()

                VStack(spacing: 0) {
                    if let err = server.connectionError, server.connectionRoute == .disconnected {
                        connectionBanner(err)
                    }

                    if server.messages.isEmpty {
                        welcomeHero
                    } else {
                        messageStream
                    }

                    floatingComposer
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

    // MARK: - Native iOS 26 Toolbar Model & Thinking Menu

    private var modelPickerMenu: some View {
        Menu {
            Section("Aktif Model") {
                ForEach(server.availableModels) { m in
                    Button {
                        SenHaptics.light()
                        server.selectedModelId = m.id
                    } label: {
                        if server.selectedModelId == m.id {
                            Label("\(m.name) · \(m.subtitle)", systemImage: "checkmark")
                        } else {
                            Text("\(m.name) · \(m.subtitle)")
                        }
                    }
                }
            }
            Section("Düşünme Seviyesi") {
                ForEach(ThinkingEffort.allCases) { eff in
                    Button {
                        SenHaptics.light()
                        server.thinkingEffort = eff
                    } label: {
                        if server.thinkingEffort == eff {
                            Label(eff.label, systemImage: "checkmark")
                        } else {
                            Label(eff.label, systemImage: eff.icon)
                        }
                    }
                }
            }
            Section {
                Button {
                    showSettings = true
                } label: {
                    Label("Ayarlar & Sunucu", systemImage: "gearshape")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("SEN.AI")
                    .font(.headline.weight(.bold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Welcome Hero

    private var welcomeHero: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.22), .indigo.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 6) {
                Text("Merhaba, birlikte ne çözelim?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(server.connectionRoute == .disconnected ? "Sunucu bekleniyor..." : "\(server.connectionRoute.rawValue) · \(server.activeModelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    starterPill("Hava Durumu", icon: "cloud.sun.fill", prompt: "Manisa hava durumu nasıl?")
                    starterPill("Film Önerisi", icon: "film.fill", prompt: "Bana sürükleyici bir bilim kurgu filmi öner")
                    starterPill("Burç Uyumu", icon: "heart.fill", prompt: "Oğlak ve Akrep uyumu nasıl olur?")
                    starterPill("Hızlı Plan", icon: "checklist", prompt: "Hafta sonu için 1 günlük verimli rutin planı yap")
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .onTapGesture { inputFocused = false }
    }

    private func starterPill(_ title: String, icon: String, prompt: String) -> some View {
        Button {
            server.sendMessage(prompt)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .senGlassCapsule(interactive: true)
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
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                            Text("Araştır")
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .senGlassCapsule(interactive: true, tint: .blue)
                    Spacer()
                }
                .padding(.horizontal, 14)
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
                        Button {
                            let text = draft
                            draft = ""
                            inputFocused = false
                            server.sendMessage(text)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background {
                                    Circle().fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.blue.opacity(0.45) : Color.blue)
                                }
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Gönder")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .padding(.top, 4)
            }
        }
    }

    private func connectionBanner(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
            Text(err).font(.caption2).lineLimit(2)
            Spacer()
            Button("Tekrar Dene") {
                Task { await server.bootstrap() }
            }
            .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background { Color.orange.opacity(0.12) }
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
                            .fill(Color.blue.opacity(0.13))
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
