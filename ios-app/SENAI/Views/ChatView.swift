import PhotosUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var server: ServerManager
    @StateObject private var voice = VoiceInputManager()

    var initialPreviewScreen: String? = nil

    @State private var draft: String = ""
    @State private var showSidebar: Bool = false
    @State private var showSettings: Bool = false
    @State private var showModelSheet: Bool = false
    @State private var showCamera: Bool = false
    @State private var showVoiceMode: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingPhotos: [PendingPhoto] = []
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
                } else if initialPreviewScreen == "voice" {
                    showVoiceMode = true
                } else if initialPreviewScreen == "camera" {
                    showCamera = true
                } else if initialPreviewScreen == "photo_composer" {
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 180))
                    let sampleImg = renderer.image { ctx in
                        UIColor(red: 0.14, green: 0.36, blue: 0.88, alpha: 1).setFill()
                        ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
                        UIColor(red: 0.45, green: 0.72, blue: 1.0, alpha: 0.85).setFill()
                        ctx.cgContext.fillEllipse(in: CGRect(x: 70, y: 40, width: 100, height: 100))
                    }
                    if let d = sampleImg.jpegData(compressionQuality: 0.85) {
                        pendingPhotos = [PendingPhoto(data: d)]
                        draft = "Bu görselde ne görüyorsun?"
                    }
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
                    .presentationDetents([.height(400), .medium])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCamera) {
                InstantCameraView { jpegData in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        pendingPhotos.append(PendingPhoto(data: jpegData))
                    }
                }
            }
            .fullScreenCover(isPresented: $showVoiceMode) {
                VoiceModeView()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, maxSelectionCount: 4, matching: .images)
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let raw = try? await item.loadTransferable(type: Data.self) {
                            let finalData = UIImage(data: raw)?.jpegData(compressionQuality: 0.78) ?? raw
                            await MainActor.run {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    pendingPhotos.append(PendingPhoto(data: finalData))
                                }
                            }
                        }
                    }
                    await MainActor.run { selectedPhotoItems = [] }
                }
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
        .buttonStyle(SenSpringButtonStyle())
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
            if !pendingPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingPhotos) { ph in
                            if let uiImg = UIImage(data: ph.data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(.rect(cornerRadius: 14))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
                                        }
                                    Button {
                                        SenHaptics.light()
                                        withAnimation(.snappy(duration: 0.22)) {
                                            pendingPhotos.removeAll { $0.id == ph.id }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.white, Color.black.opacity(0.7))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                                .padding(.top, 5)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

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
                .padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            SenGlassContainer(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    Menu {
                        Button {
                            SenHaptics.light()
                            showCamera = true
                        } label: {
                            Label("Fotoğraf Çek (Anlık)", systemImage: "camera.fill")
                        }
                        Button {
                            SenHaptics.light()
                            showPhotoPicker = true
                        } label: {
                            Label("Galeriden Fotoğraf Seç", systemImage: "photo.on.rectangle")
                        }
                        Divider()
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
                                .font(.system(size: 17))
                                .foregroundStyle(voice.isRecording ? .red : .secondary)
                                .frame(width: 32, height: 34)
                        }
                        .padding(.bottom, 2)

                        Button {
                            SenHaptics.light()
                            showVoiceMode = true
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 32, height: 34)
                        }
                        .padding(.bottom, 2)
                        .padding(.trailing, 4)
                        .accessibilityLabel("Canlı Sesli Sohbet")
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
                        let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingPhotos.isEmpty
                        Button {
                            let text = draft
                            let imgs = pendingPhotos.map(\.data)
                            draft = ""
                            pendingPhotos = []
                            inputFocused = false
                            server.sendMessage(text, images: imgs)
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
    @State private var copied: Bool = false

    var body: some View {
        if msg.role == "user" {
            VStack(alignment: .trailing, spacing: 6) {
                if !msg.attachedImages.isEmpty {
                    HStack(spacing: 6) {
                        Spacer(minLength: 52)
                        ForEach(Array(msg.attachedImages.enumerated()), id: \.offset) { _, imgData in
                            if let uiImg = UIImage(data: imgData) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(.rect(cornerRadius: 16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                                    }
                            }
                        }
                    }
                }
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
                    case .codeBlock(let lang, let code):
                        CodeBlockCardView(lang: lang, code: code)
                    case .table(let headers, let rows):
                        MarkdownTableCardView(headers: headers, rows: rows)
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
                            withAnimation(.snappy(duration: 0.2)) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.snappy(duration: 0.2)) { copied = false }
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copied ? .green : .secondary)
                                .contentTransition(.symbolEffect(.replace))
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
                                        .foregroundStyle(.blue)
                                    Text("\(msg.webSources.count) kaynak")
                                        .foregroundStyle(.primary)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(SenSpringButtonStyle())
                            .senGlassCapsule(interactive: true)
                        }
                    }
                    .font(.system(size: 15))
                    .padding(.top, 4)
                    .padding(.bottom, 6)
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

// MARK: - Dedicated iOS 26 Liquid Glass Model & Cosmic Thinking Effort Slider Sheet

struct ModelPickerSheetView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                ThinkingEffortSliderView(effort: Binding(
                    get: { server.thinkingEffort },
                    set: { server.thinkingEffort = $0 }
                ))

                VStack(alignment: .leading, spacing: 9) {
                    Text("Aktif Yerel Model")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 9) {
                        ForEach(server.availableModels) { m in
                            let selected = server.selectedModelId == m.id
                            let isE4B = m.id.contains("e4b")
                            Button {
                                SenHaptics.light()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    server.selectedModelId = m.id
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { dismiss() }
                            } label: {
                                HStack(spacing: 13) {
                                    ModelBadgeIcon(isDeep: isE4B, isSelected: selected)
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
                                            .foregroundStyle(isE4B ? .indigo : .blue)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(12)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(selected ? (isE4B ? Color.indigo : Color.blue).opacity(0.12) : Color.primary.opacity(0.05))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(selected ? (isE4B ? Color.indigo : Color.blue).opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                                        }
                                }
                            }
                            .buttonStyle(SenSpringButtonStyle())
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

struct ModelBadgeIcon: View {
    let isDeep: Bool
    let isSelected: Bool
    @State private var glow = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDeep
                            ? [Color(red: 0.36, green: 0.26, blue: 0.96), Color(red: 0.64, green: 0.28, blue: 0.94)]
                            : [Color(red: 0.08, green: 0.56, blue: 0.98), Color(red: 0.16, green: 0.36, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .shadow(color: (isDeep ? Color.purple : Color.blue).opacity(isSelected ? 0.42 : 0.16), radius: isSelected ? 10 : 4, y: 3)

            Image(systemName: isDeep ? "sparkles" : "bolt.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(glow && isSelected ? 1.12 : 1.0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

struct ThinkingEffortSliderView: View {
    @Binding var effort: ThinkingEffort
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let levels: [ThinkingEffort] = [.off, .low, .medium, .high]

    private var currentIndex: Int {
        levels.firstIndex(of: effort) ?? 0
    }

    private var accentColor: Color {
        switch effort {
        case .off: return .secondary
        case .low: return .green
        case .medium: return .blue
        case .high: return Color(red: 0.62, green: 0.36, blue: 0.98)
        }
    }

    private var subtitleText: String {
        switch effort {
        case .off: return "Doğrudan anlık yanıt"
        case .low: return "Hafif ve hızlı akıl yürütme"
        case .medium: return "Dengeli derin analiz"
        case .high: return "Maksimum akıl yürütme ✨"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(effort.label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText())
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geo in
                let trackW = max(geo.size.width, 120)
                let thumbD: CGFloat = 36
                let usableW = max(trackW - thumbD, 1)
                let frac = CGFloat(currentIndex) / CGFloat(levels.count - 1)
                let thumbX = frac * usableW

                ZStack(alignment: .leading) {
                    // Base Track
                    Capsule()
                        .fill(Color.primary.opacity(0.09))
                        .overlay {
                            Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                        }

                    // Active Filled Track (Cosmic Animated Particle Gradient on Ultra/High!)
                    if currentIndex > 0 {
                        let fillW = thumbX + thumbD
                        ZStack {
                            if effort == .high {
                                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                                    let t = timeline.date.timeIntervalSinceReferenceDate
                                    let shift = sin(t * 1.4) * 0.18
                                    ZStack {
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.16, green: 0.38, blue: 0.98),
                                                Color(red: 0.50, green: 0.32, blue: 0.98),
                                                Color(red: 0.72, green: 0.34, blue: 0.96),
                                            ],
                                            startPoint: UnitPoint(x: 0.0 + shift, y: 0.5),
                                            endPoint: UnitPoint(x: 1.0 + shift, y: 0.5)
                                        )
                                        Canvas { ctx, size in
                                            let seeds: [(CGFloat, CGFloat, CGFloat, Double)] = [
                                                (0.12, 0.32, 2.2, 0.0), (0.20, 0.68, 1.8, 1.1), (0.28, 0.42, 2.6, 2.3),
                                                (0.39, 0.72, 1.9, 0.7), (0.48, 0.28, 2.4, 1.9), (0.56, 0.62, 2.8, 3.1),
                                                (0.65, 0.35, 1.8, 2.6), (0.74, 0.66, 2.5, 0.4), (0.82, 0.40, 2.1, 1.5),
                                            ]
                                            for (px, py, rad, phase) in seeds {
                                                let alpha = 0.45 + 0.55 * abs(sin(t * 2.2 + phase))
                                                let dx = CGFloat(sin(t * 0.9 + phase)) * 4.0
                                                let pt = CGPoint(x: px * size.width + dx, y: py * size.height)
                                                let rect = CGRect(x: pt.x - rad, y: pt.y - rad, width: rad * 2, height: rad * 2)
                                                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                                            }
                                        }
                                    }
                                }
                            } else if effort == .medium {
                                LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .leading, endPoint: .trailing)
                            } else {
                                LinearGradient(colors: [Color.green, Color.teal], startPoint: .leading, endPoint: .trailing)
                            }
                        }
                        .frame(width: fillW)
                        .clipShape(Capsule())
                    }

                    // Detent Dots
                    HStack {
                        ForEach(0..<levels.count, id: \.self) { i in
                            Circle()
                                .fill(i <= currentIndex ? Color.white.opacity(0.65) : Color.primary.opacity(0.28))
                                .frame(width: 5, height: 5)
                            if i < levels.count - 1 { Spacer() }
                        }
                    }
                    .padding(.horizontal, thumbD / 2 - 2.5)

                    // Tactile White Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbD, height: thumbD)
                        .shadow(color: .black.opacity(0.26), radius: 6, y: 2)
                        .offset(x: thumbX)
                }
                .frame(height: 40)
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let clamped = min(max(val.location.x - thumbD / 2, 0), usableW)
                            let idx = Int(round((clamped / usableW) * CGFloat(levels.count - 1)))
                            let target = levels[min(max(idx, 0), levels.count - 1)]
                            if target != effort {
                                if target == .high { SenHaptics.medium() } else { SenHaptics.light() }
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.76)) {
                                    effort = target
                                }
                            }
                        }
                )
            }
            .frame(height: 42)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(effort == .high ? Color.purple.opacity(0.38) : Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}
