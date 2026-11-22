import PhotosUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var server: ServerManager
    @StateObject private var voice = VoiceInputManager()
    @StateObject private var location = LocationManager()

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
    @State private var bentoAppeared: Bool = false
    @State private var showRenameAlert: Bool = false
    @State private var renameDraft: String = ""
    @State private var showScrollToBottom: Bool = false
    @State private var scrollToBottomTrigger: Int = 0
    @State private var showPlusMenu: Bool = false
    @State private var showTemporarySheet: Bool = false
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(geo.size.width * 0.84, 340)

            ZStack(alignment: .leading) {
                NavigationStack {
                    ZStack {
                        SenAmbientBackground()
                            .ignoresSafeArea(.keyboard)

                        VStack(spacing: 0) {
                            if server.connectionRoute == .disconnected && !server.isConnecting {
                                floatingOfflinePill
                            }

                            if server.messages.isEmpty {
                                if server.isTemporaryChat {
                                    temporaryChatHero
                                } else {
                                    welcomeHero
                                }
                            } else {
                                messageStream
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            floatingComposer
                        }

                        // iOS 26 Floating Liquid Glass (+) Popover Menu
                        if showPlusMenu {
                            Color.black.opacity(0.08)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        showPlusMenu = false
                                    }
                                }
                                .transition(.opacity)

                            VStack {
                                Spacer()
                                HStack {
                                    plusPopoverMenu
                                        .padding(.leading, 14)
                                        .padding(.bottom, 74)
                                    Spacer()
                                }
                            }
                            .transition(.scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity))
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
                        } else if initialPreviewScreen == "temporary" {
                            server.isTemporaryChat = true
                        } else if initialPreviewScreen == "plus_menu" {
                            server.webSearchEnabled = true
                            server.useLibraryEnabled = true
                            showPlusMenu = true
                        } else if initialPreviewScreen == "composer_pills" {
                            server.webSearchEnabled = true
                            server.useLibraryEnabled = true
                            draft = "Gassal dizisindeki imamın camisi nerede?"
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
                                inputFocused = false
                                showPlusMenu = false
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    showSidebar = true
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                            }
                            .accessibilityLabel("Sohbet Geçmişi")
                        }

                        ToolbarItem(placement: .principal) {
                            modelPickerMenu
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: 6) {
                                if server.messages.isEmpty {
                                    Button {
                                        SenHaptics.light()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                            server.isTemporaryChat.toggle()
                                        }
                                    } label: {
                                        Image(systemName: server.isTemporaryChat ? "bubble.left.fill" : "circle.dashed")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(server.isTemporaryChat ? Color.blue : Color.primary)
                                    }
                                    .accessibilityLabel(server.isTemporaryChat ? "Geçici Sohbeti Kapat" : "Geçici Sohbet")
                                } else {
                                    Button {
                                        server.startNewChat()
                                    } label: {
                                        Image(systemName: "square.and.pencil")
                                    }
                                    .accessibilityLabel("Yeni Sohbet")

                                    if !server.isTemporaryChat {
                                        Menu {
                                            Section(server.currentSessionTitle) {
                                                ShareLink(item: server.currentTranscriptForShare) {
                                                    Label("Paylaş", systemImage: "square.and.arrow.up")
                                                }
                                                Button {
                                                    Task { await server.togglePinSession(server.activeSessionId) }
                                                } label: {
                                                    Label(
                                                        server.isCurrentSessionPinned ? "Sabitlemeyi Kaldır" : "Sabitle",
                                                        systemImage: server.isCurrentSessionPinned ? "pin.slash" : "pin"
                                                    )
                                                }
                                                Button {
                                                    renameDraft = server.currentSessionTitle
                                                    showRenameAlert = true
                                                } label: {
                                                    Label("Yeniden Adlandır", systemImage: "pencil")
                                                }
                                                Divider()
                                                Button(role: .destructive) {
                                                    Task { await server.deleteSession(server.activeSessionId) }
                                                } label: {
                                                    Label("Sil", systemImage: "trash")
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                        }
                                        .accessibilityLabel("Sohbet Seçenekleri")
                                    }
                                }
                            }
                        }
                    }
                    .alert("Sohbeti Yeniden Adlandır", isPresented: $showRenameAlert) {
                        TextField("Yeni başlık", text: $renameDraft)
                        Button("İptal", role: .cancel) {}
                        Button("Kaydet") {
                            let next = renameDraft
                            Task { await server.renameSession(server.activeSessionId, newTitle: next) }
                        }
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView()
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showModelSheet) {
                        ModelPickerSheetView(showSettings: $showSettings)
                            .presentationDetents([.height(420), .medium])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showTemporarySheet) {
                        TemporaryChatSettingsSheet(isPersonalized: $server.temporaryPersonalized)
                            .presentationDetents([.height(320)])
                            .presentationDragIndicator(.visible)
                    }
                    .fullScreenCover(isPresented: $showCamera) {
                        InstantCameraView(
                            onCapture: { jpegData in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    pendingPhotos.append(PendingPhoto(data: jpegData))
                                }
                            },
                            onOpenGallery: {
                                showPhotoPicker = true
                            }
                        )
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
                .disabled(showSidebar)

                // ChatGPT-Style Slide-Over Left Sidebar Drawer
                if showSidebar {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                showSidebar = false
                            }
                        }
                        .transition(.opacity)

                    SidebarView(
                        isPresented: $showSidebar,
                        showSettings: $showSettings,
                        showModelSheet: $showModelSheet
                    )
                    .frame(width: drawerWidth)
                    .shadow(color: Color.black.opacity(0.16), radius: 22, x: 6, y: 0)
                    .transition(.move(edge: .leading))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showSidebar)
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

    // MARK: - Temporary Chat Hero (ChatGPT-style)

    private var temporaryChatHero: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Spacer(minLength: inputFocused ? 30 : 120)

                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .padding(.bottom, 2)

                Text("Geçici sohbet")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.primary)

                Text("Bu sohbet geçmişte görünmez veya yerel belleğinizi güncellemez.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Button {
                    SenHaptics.light()
                    showTemporarySheet = true
                } label: {
                    HStack(spacing: 5) {
                        Text(server.temporaryPersonalized ? "Kişiselleştirilmiş" : "Kişiselleştirilmemiş")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .senGlassCapsule(interactive: true)
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { inputFocused = false }
    }

    // MARK: - Flagship 2x2 Bento Welcome Hero

    private var welcomeHero: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: inputFocused ? 14 : 22) {
                Spacer(minLength: inputFocused ? 14 : 44)

                SenPrismOrb(size: inputFocused ? 46 : 64)

                VStack(spacing: 6) {
                    Text(turkishGreeting)
                        .font(inputFocused ? .headline.weight(.semibold) : .title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("birlikte ne çözelim?")
                        .font(inputFocused ? .title2.weight(.bold) : .title.weight(.bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.primary, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                        .multilineTextAlignment(.center)
                    Text(server.connectionRoute == .disconnected ? "Sunucu bekleniyor · Ayarlar'dan bağlanın" : "\(server.connectionRoute.rawValue) · \(server.activeModelName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                if !inputFocused {
                    let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: cols, spacing: 10) {
                        bentoCard(
                            title: "Hava Durumu",
                            subtitle: "Konuma göre canlı tahmin",
                            icon: "cloud.sun.fill",
                            tint: .blue,
                            prompt: "Hava durumu nasıl?",
                            delay: 0.04,
                            useLocation: true
                        )
                        bentoCard(
                            title: "Film Önerisi",
                            subtitle: "Zevkine göre afişli liste",
                            icon: "film.fill",
                            tint: .orange,
                            prompt: "Bana film önerisi yapar mısın?",
                            delay: 0.09
                        )
                        bentoCard(
                            title: "Burç Uyumu",
                            subtitle: "Kişisel uyum analizi",
                            icon: "heart.fill",
                            tint: .pink,
                            prompt: "Burç uyumu karşılaştırmak istiyorum",
                            delay: 0.14
                        )
                        bentoCard(
                            title: "Günlük Plan",
                            subtitle: "İnteraktif rutin oluştur",
                            icon: "checklist",
                            tint: .green,
                            prompt: "Günlük veya haftalık plan oluşturmak istiyorum",
                            delay: 0.19
                        )
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .onAppear {
                        if !bentoAppeared {
                            withAnimation(.spring(duration: 0.50, bounce: 0.16)) {
                                bentoAppeared = true
                            }
                        }
                    }
                }

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: inputFocused)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { inputFocused = false }
    }

    private func bentoCard(title: String, subtitle: String, icon: String, tint: Color, prompt: String, delay: Double, useLocation: Bool = false) -> some View {
        Button {
            if useLocation {
                Task {
                    let city = await location.requestCityOnce()
                    server.sendMessage(prompt, userCity: city)
                }
            } else {
                server.sendMessage(prompt)
            }
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
        .opacity(bentoAppeared ? 1 : 0)
        .offset(y: bentoAppeared ? 0 : 14)
        .animation(.spring(duration: 0.48, bounce: 0.18).delay(delay), value: bentoAppeared)
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
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    if server.isSearchingWeb {
                        LiveWebSearchStatusView(
                            sitesCount: max(1, server.searchingSitesCount),
                            domain: server.searchingDomain
                        )
                            .padding(.horizontal, 2)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if server.isGenerating,
                              let last = server.messages.last,
                              last.role == "assistant",
                              last.content.isEmpty,
                              last.thinking.isEmpty {
                        SenStreamingDot()
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .transition(.opacity)
                    } else if !server.statusLine.isEmpty {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini)
                            Text(server.statusLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    Color.clear
                        .frame(height: 28)
                        .id("BOTTOM_ANCHOR")
                        .onAppear {
                            withAnimation(.snappy(duration: 0.22)) {
                                showScrollToBottom = false
                            }
                        }
                        .onDisappear {
                            if !server.messages.isEmpty {
                                withAnimation(.snappy(duration: 0.22)) {
                                    showScrollToBottom = true
                                }
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .senSoftScrollEdge()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: server.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: inputFocused) { _, focused in
                if focused && !server.messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: scrollToBottomTrigger) { _, _ in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Floating iOS 26 Unified White / Liquid Glass Composer (NO Full-Width Box!)

    private var floatingComposer: some View {
        let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingPhotos.isEmpty
        let hasActivePills = server.webSearchEnabled || server.useLibraryEnabled
        let isExpanded = hasActivePills || !pendingPhotos.isEmpty || draft.contains("\n") || draft.count > 26
        let cornerRadius: CGFloat = isExpanded ? 24 : 26

        return VStack(spacing: 8) {
            // Soft White / Liquid Glass Scroll-to-Bottom (↓) button
            if showScrollToBottom && !inputFocused && !server.messages.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        SenHaptics.light()
                        scrollToBottomTrigger += 1
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .fill(colorScheme == .dark ? Color(.secondarySystemBackground).opacity(0.90) : Color.white.opacity(0.92))
                            }
                    }
                    .buttonStyle(SenSpringButtonStyle())
                    .senGlassCircle(interactive: true)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 10, y: 4)
                    .accessibilityLabel("En Alta İn")
                    Spacer()
                }
                .transition(.scale(scale: 0.78).combined(with: .opacity))
            }

            // Unified Floating Composer Card (White Liquid Glass + Soft Shadow, Tags INSIDE!)
            VStack(alignment: .leading, spacing: 8) {
                // Pending Photos INSIDE top of card
                if !pendingPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
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
                                                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
                                            }
                                        Button {
                                            SenHaptics.light()
                                            withAnimation(.snappy(duration: 0.22)) {
                                                pendingPhotos.removeAll { $0.id == ph.id }
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(Color.white, Color.black.opacity(0.75))
                                        }
                                        .offset(x: 6, y: -6)
                                    }
                                    .padding(.top, 6)
                                    .padding(.trailing, 6)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Active Tool Pills INSIDE top of Composer Card (ChatGPT-style `Düşün ×` pill design)
                if hasActivePills {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if server.webSearchEnabled {
                                composerInsidePill(
                                    title: "Araştır",
                                    icon: "globe",
                                    tint: Color.blue
                                ) {
                                    SenHaptics.light()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                                        server.webSearchEnabled = false
                                    }
                                }
                            }
                            if server.useLibraryEnabled {
                                composerInsidePill(
                                    title: "Kütüphane",
                                    icon: "books.vertical.fill",
                                    tint: Color.indigo
                                ) {
                                    SenHaptics.light()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                                        server.useLibraryEnabled = false
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, pendingPhotos.isEmpty ? 10 : 2)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if isExpanded {
                    // Multi-row layout: TextField on top, controls (+ | mic | send) below
                    TextField(
                        server.isTemporaryChat ? "Geçici sohbete sor..." : "SEN.AI'ye sor...",
                        text: $draft,
                        axis: .vertical
                    )
                    .lineLimit(1...5)
                    .font(.body)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.top, hasActivePills || !pendingPhotos.isEmpty ? 2 : 12)

                    HStack(spacing: 8) {
                        plusButton
                        Spacer()
                        micButton
                        trailingActionButton(isEmpty: isEmpty)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                } else {
                    // Compact single-row Liquid Glass Pill
                    HStack(alignment: .center, spacing: 6) {
                        plusButton

                        TextField(
                            server.isTemporaryChat ? "Geçici sohbete sor..." : "SEN.AI'ye sor...",
                            text: $draft,
                            axis: .vertical
                        )
                        .lineLimit(1...5)
                        .font(.body)
                        .focused($inputFocused)
                        .padding(.vertical, 9)

                        micButton
                        trailingActionButton(isEmpty: isEmpty)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(.secondarySystemBackground).opacity(0.88) : Color.white.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                                lineWidth: 0.8
                            )
                    }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08),
                radius: 16,
                y: 5
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.30, dampingFraction: 0.84), value: isExpanded)
        }
    }

    private func composerInsidePill(title: String, icon: String, tint: Color, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint.opacity(0.82))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(colorScheme == .dark ? tint.opacity(0.18) : Color.white)
                    .overlay {
                        Capsule()
                            .strokeBorder(tint.opacity(0.24), lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07), radius: 6, y: 2)
            }
        }
        .buttonStyle(SenSpringButtonStyle())
    }

    private var plusButton: some View {
        Button {
            SenHaptics.light()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                showPlusMenu.toggle()
            }
        } label: {
            Image(systemName: showPlusMenu ? "xmark" : "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(SenSpringButtonStyle())
        .accessibilityLabel("Araçlar ve Ekler")
    }

    private var micButton: some View {
        Button {
            voice.toggleRecording { text in
                draft = text
            }
        } label: {
            Image(systemName: voice.isRecording ? "waveform.circle.fill" : "mic")
                .font(.system(size: 17))
                .foregroundStyle(voice.isRecording ? Color.red : Color.secondary)
                .frame(width: 32, height: 34)
        }
        .accessibilityLabel("Sesle Yaz")
    }

    @ViewBuilder
    private func trailingActionButton(isEmpty: Bool) -> some View {
        if server.isGenerating {
            Button {
                server.stopGeneration()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(Color.red) }
            }
            .accessibilityLabel("Durdur")
        } else if !isEmpty {
            Button {
                let text = draft
                let imgs = pendingPhotos.map(\.data)
                draft = ""
                pendingPhotos = []
                inputFocused = false
                showPlusMenu = false
                server.sendMessage(text, images: imgs, userCity: location.currentCity)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(Color.blue) }
            }
            .buttonStyle(SenSpringButtonStyle())
            .accessibilityLabel("Gönder")
        } else {
            Button {
                SenHaptics.light()
                showPlusMenu = false
                showVoiceMode = true
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background { Circle().fill(Color.blue) }
            }
            .buttonStyle(SenSpringButtonStyle())
            .accessibilityLabel("Canlı Sesli Sohbet")
        }
    }

    // MARK: - iOS 26 Floating Liquid Glass (+) Popover Menu (ChatGPT-style)

    private var plusPopoverMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            plusMenuRow(icon: "camera", title: "Kamera", tint: Color.primary, isActive: false) {
                showPlusMenu = false
                showCamera = true
            }
            plusMenuRow(icon: "photo.on.rectangle", title: "Fotoğraflar", tint: Color.primary, isActive: false) {
                showPlusMenu = false
                showPhotoPicker = true
            }
            plusMenuRow(icon: "globe", title: "Web'de Araştır", tint: Color.blue, isActive: server.webSearchEnabled) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    server.webSearchEnabled.toggle()
                    showPlusMenu = false
                }
            }
            plusMenuRow(icon: "books.vertical", title: "Kütüphane", tint: Color.indigo, isActive: server.useLibraryEnabled) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    server.useLibraryEnabled.toggle()
                    showPlusMenu = false
                }
            }
            plusMenuRow(icon: "gearshape", title: "Ayarlar", tint: Color.primary, isActive: false) {
                showPlusMenu = false
                showSettings = true
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(width: 248)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(colorScheme == .dark ? Color(.secondarySystemBackground).opacity(0.94) : Color.white.opacity(0.95))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06), lineWidth: 0.8)
                }
        }
        .senGlassRounded(radius: 28, interactive: true)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.14), radius: 24, y: 10)
    }

    private func plusMenuRow(icon: String, title: String, tint: Color, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SenHaptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isActive ? tint : Color.primary)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(isActive ? tint.opacity(0.16) : Color.primary.opacity(0.06))
                    }
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isActive ? tint : Color.primary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(SenSpringButtonStyle())
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
                    Spacer(minLength: 48)
                    Text(msg.content)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.primary.opacity(0.065))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                                }
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = msg.content
                                SenHaptics.light()
                            } label: {
                                Label("Kopyala", systemImage: "doc.on.doc")
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

                // Detay-free Apple/ChatGPT-style Thinking Pill:
                // Animated "Düşünüyor..." while thinking, then static "✦ X sn düşündü" badge
                if !msg.thinking.isEmpty {
                    let isActivelyThinking = msg.isStreaming && msg.content.isEmpty
                    let secs = max(1, Int(round(msg.thinkingSeconds)))
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2.weight(.semibold))
                            .symbolEffect(.pulse, isActive: isActivelyThinking)
                        if isActivelyThinking {
                            Text("Düşünüyor...")
                                .font(.caption.weight(.semibold))
                        } else {
                            Text("\(secs) sn düşündü")
                                .font(.caption.weight(.semibold))
                                .contentTransition(.numericText())
                        }
                    }
                    .foregroundStyle(isActivelyThinking ? .blue : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(isActivelyThinking ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.10))
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

                // ChatGPT-Style Clean Action Row + Overlapping Favicon "Kaynaklar" Capsule
                if !msg.isStreaming && !msg.content.isEmpty {
                    HStack(spacing: 15) {
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

                        Button {
                            Task { await server.toggleSpeak(messageId: msg.id, text: msg.content) }
                        } label: {
                            Image(systemName: server.speakingMessageId == msg.id ? "stop.circle.fill" : "speaker.wave.2")
                                .foregroundStyle(server.speakingMessageId == msg.id ? .blue : .secondary)
                        }

                        ShareLink(item: msg.content) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.secondary)
                        }

                        Menu {
                            Button {
                                server.regenerateLast()
                            } label: {
                                Label("Yeniden Üret", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.secondary)
                        }

                        if !msg.webSources.isEmpty {
                            Button {
                                SenHaptics.light()
                                onShowSources(msg.webSources)
                            } label: {
                                HStack(spacing: 6) {
                                    HStack(spacing: -6) {
                                        ForEach(Array(msg.webSources.prefix(3).enumerated()), id: \.offset) { idx, src in
                                            SiteFaviconView(domain: src.domain, fallbackIndex: idx, size: 18)
                                                .overlay {
                                                    Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.3)
                                                }
                                        }
                                    }
                                    Text("Kaynaklar")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(SenSpringButtonStyle())
                            .senGlassCapsule(interactive: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14.5, weight: .regular))
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private func markdownAttributed(_ text: String) -> AttributedString {
        // Normalize block-level Markdown (* bullets, - bullets, ### headings, *** horizontal rules)
        // so raw '*', '###', or '***' characters NEVER show up on screen!
        let normalizedLines: [String] = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .compactMap { rawLine in
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed == "***" || trimmed == "---" || trimmed == "___" {
                    return nil
                }
                if trimmed.hasPrefix("### ") {
                    let h = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    return "**\(h)**"
                }
                if trimmed.hasPrefix("## ") {
                    let h = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    return "**\(h)**"
                }
                if trimmed.hasPrefix("# ") {
                    let h = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    return "**\(h)**"
                }
                if trimmed.hasPrefix("* ") {
                    return "• " + String(trimmed.dropFirst(2))
                }
                if trimmed.hasPrefix("- ") {
                    return "• " + String(trimmed.dropFirst(2))
                }
                return rawLine
            }
        let cleaned = normalizedLines.joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(cleaned)
    }
}

struct SiteFaviconView: View {
    @EnvironmentObject private var server: ServerManager
    let domain: String
    let fallbackIndex: Int
    var size: CGFloat = 20

    private let palette: [Color] = [.blue, .orange, .indigo, .teal, .purple]

    var body: some View {
        let initial = String(domain.prefix(1)).uppercased()
        let bg = palette[fallbackIndex % palette.count]
        Group {
            if let url = server.faviconURL(for: domain) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .background(Color.white)
                    default:
                        fallbackCircle(initial: initial, bg: bg)
                    }
                }
            } else {
                fallbackCircle(initial: initial, bg: bg)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func fallbackCircle(initial: String, bg: Color) -> some View {
        Circle()
            .fill(bg)
            .overlay {
                Text(initial.isEmpty ? "W" : initial)
                    .font(.system(size: max(8, size * 0.48), weight: .bold))
                    .foregroundStyle(Color.white)
            }
    }
}

struct LiveWebSearchStatusView: View {
    let sitesCount: Int
    let domain: String
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.blue)
                .scaleEffect(pulse ? 1.12 : 0.94)
                .animation(.easeInOut(duration: 0.90).repeatForever(autoreverses: true), value: pulse)

            HStack(spacing: 4) {
                Text("\(sitesCount)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.28, dampingFraction: 0.80), value: sitesCount)
                Text("web sitesi aranıyor")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.secondary)

                if !domain.isEmpty {
                    Text("· \(domain)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.blue.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(.opacity)
                }
            }
            .opacity(pulse ? 1.0 : 0.64)
            .animation(.easeInOut(duration: 0.90).repeatForever(autoreverses: true), value: pulse)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .senGlassCapsule(interactive: false)
        .padding(.vertical, 2)
        .onAppear { pulse = true }
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
            List(Array(sources.enumerated()), id: \.element.id) { idx, src in
                if let url = URL(string: src.url) {
                    Link(destination: url) {
                        HStack(alignment: .top, spacing: 12) {
                            SiteFaviconView(domain: src.domain, fallbackIndex: idx, size: 28)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(src.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(2)
                                Text(src.domain)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Color.blue)
                                if !src.snippet.isEmpty {
                                    Text(src.snippet)
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 3)
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

struct TemporaryChatSettingsSheet: View {
    @Binding var isPersonalized: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                optionCard(
                    title: "Kişiselleştirilmiş",
                    subtitle: "Yanıtlarda mevcut yerel bellek ve tercihlerinizi kullanır ancak bu sohbeti kaydetmez.",
                    selected: isPersonalized
                ) {
                    SenHaptics.light()
                    isPersonalized = true
                }

                optionCard(
                    title: "Kişiselleştirilmemiş",
                    subtitle: "Tamamen sıfır bağlamla çalışır; ne mevcut belleğinizi okur ne de bu sohbeti kaydeder.",
                    selected: !isPersonalized
                ) {
                    SenHaptics.light()
                    isPersonalized = false
                }

                Spacer(minLength: 4)
            }
            .padding(16)
            .navigationTitle("Geçici sohbet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func optionCard(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.blue : Color.secondary.opacity(0.4))
            }
            .padding(14)
            .senGlassRounded(radius: 20, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1.2)
            }
        }
        .buttonStyle(SenSpringButtonStyle())
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
                                            .foregroundStyle(isE4B ? Color.indigo : Color.blue)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(14)
                                .senGlassRounded(radius: 22, interactive: true)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(
                                            selected ? (isE4B ? Color.indigo : Color.blue).opacity(0.45) : Color.clear,
                                            lineWidth: 1.2
                                        )
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
    @State private var dragFraction: CGFloat? = nil

    private let levels: [ThinkingEffort] = [.off, .low, .medium, .high]

    private var currentIndex: Int {
        levels.firstIndex(of: effort) ?? 0
    }

    private var displayFraction: CGFloat {
        dragFraction ?? (CGFloat(currentIndex) / CGFloat(levels.count - 1))
    }

    private var accentColor: Color {
        switch effort {
        case .off: return .secondary
        case .low: return .green
        case .medium: return .blue
        case .high: return Color(red: 0.96, green: 0.30, blue: 0.56)
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
                    .animation(.snappy(duration: 0.22), value: effort)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.2), value: effort)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geo in
                let trackW = max(geo.size.width, 120)
                let thumbD: CGFloat = 36
                let usableW = max(trackW - thumbD, 1)
                let frac = min(max(displayFraction, 0), 1)
                let thumbX = frac * usableW
                let isDragging = dragFraction != nil

                ZStack(alignment: .leading) {
                    // Base Track
                    Capsule()
                        .fill(Color.primary.opacity(0.09))
                        .overlay {
                            Capsule().strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.8)
                        }

                    // Smooth Continuous Active Fill (Faster Crimson/Rose Particles Flowing Right -> Left on High!)
                    if frac > 0.01 {
                        let fillW = max(thumbX + thumbD, thumbD)
                        ZStack {
                            if effort == .high || frac > 0.82 {
                                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                                    let t = timeline.date.timeIntervalSinceReferenceDate
                                    let shift = sin(t * 2.1) * 0.16
                                    ZStack {
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.24, green: 0.26, blue: 0.94),
                                                Color(red: 0.62, green: 0.22, blue: 0.86),
                                                Color(red: 0.95, green: 0.24, blue: 0.46),
                                            ],
                                            startPoint: UnitPoint(x: 0.0 + shift, y: 0.5),
                                            endPoint: UnitPoint(x: 1.0 + shift, y: 0.5)
                                        )
                                        Canvas { ctx, size in
                                            // 18 glowing crimson/rose & bright spark particles streaming RIGHT -> LEFT from the thumb
                                            let seeds: [(Double, CGFloat, CGFloat, Double, Bool)] = [
                                                (0.03, 0.28, 2.3, 0.52, true),  (0.11, 0.72, 1.9, 0.68, false),
                                                (0.18, 0.45, 2.8, 0.60, true),  (0.24, 0.22, 1.7, 0.78, false),
                                                (0.31, 0.64, 2.4, 0.55, true),  (0.38, 0.36, 2.1, 0.72, false),
                                                (0.45, 0.78, 2.6, 0.64, true),  (0.52, 0.26, 1.8, 0.82, false),
                                                (0.59, 0.54, 2.9, 0.58, true),  (0.66, 0.70, 2.0, 0.74, false),
                                                (0.73, 0.32, 2.5, 0.62, true),  (0.80, 0.60, 1.9, 0.80, false),
                                                (0.86, 0.24, 2.2, 0.66, true),  (0.92, 0.48, 2.7, 0.54, true),
                                                (0.15, 0.52, 1.6, 0.86, false), (0.42, 0.42, 2.0, 0.70, true),
                                                (0.68, 0.46, 2.3, 0.65, true),  (0.89, 0.74, 1.8, 0.76, false),
                                            ]
                                            for (phase, py, rad, speed, isCrimson) in seeds {
                                                // Travel smoothly from right (1.0) to left (0.0)
                                                let prog = (t * speed + phase).truncatingRemainder(dividingBy: 1.0)
                                                let xNorm = CGFloat(1.0 - prog)
                                                let px = xNorm * max(size.width - 14, 1)
                                                let pyJitter = py * size.height + CGFloat(sin(t * 3.2 + phase * 10.0)) * 2.2
                                                // Fade in right next to thumb, stay bright in middle, fade out at far left
                                                let edgeFade = min(xNorm * 4.0, (1.0 - xNorm) * 6.0, 1.0)
                                                let twinkle = 0.65 + 0.35 * abs(sin(t * 4.5 + phase * 8.0))
                                                let alpha = Double(edgeFade) * twinkle

                                                let coreColor: Color = isCrimson
                                                    ? Color(red: 1.0, green: 0.42, blue: 0.58)
                                                    : Color(red: 1.0, green: 0.86, blue: 0.90)

                                                // Soft crimson halo + crisp bright core
                                                let haloR = rad * 2.1
                                                let haloRect = CGRect(x: px - haloR, y: pyJitter - haloR, width: haloR * 2, height: haloR * 2)
                                                ctx.fill(Path(ellipseIn: haloRect), with: .color(Color(red: 1.0, green: 0.22, blue: 0.42).opacity(alpha * 0.45)))

                                                let coreRect = CGRect(x: px - rad, y: pyJitter - rad, width: rad * 2, height: rad * 2)
                                                ctx.fill(Path(ellipseIn: coreRect), with: .color(coreColor.opacity(alpha)))
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
                            let dotFrac = CGFloat(i) / CGFloat(levels.count - 1)
                            Circle()
                                .fill(dotFrac <= frac ? Color.white.opacity(0.70) : Color.primary.opacity(0.28))
                                .frame(width: 5, height: 5)
                            if i < levels.count - 1 { Spacer() }
                        }
                    }
                    .padding(.horizontal, thumbD / 2 - 2.5)

                    // Tactile Smooth Thumb (scales subtly while dragging)
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbD, height: thumbD)
                        .scaleEffect(isDragging ? 1.10 : 1.0)
                        .shadow(color: (effort == .high ? Color.pink : Color.black).opacity(isDragging ? 0.42 : 0.26), radius: isDragging ? 10 : 6, y: 2)
                        .offset(x: thumbX)
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isDragging)
                }
                .frame(height: 40)
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let clamped = min(max((val.location.x - thumbD / 2) / usableW, 0), 1)
                            dragFraction = clamped
                            let idx = Int(round(clamped * CGFloat(levels.count - 1)))
                            let target = levels[min(max(idx, 0), levels.count - 1)]
                            if target != effort {
                                if target == .high { SenHaptics.medium() } else { SenHaptics.light() }
                                withAnimation(.snappy(duration: 0.22)) {
                                    effort = target
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
                                dragFraction = nil
                            }
                        }
                )
            }
            .frame(height: 42)
        }
        .padding(14)
        .senGlassRounded(radius: 22, interactive: false)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(effort == .high ? Color(red: 0.95, green: 0.28, blue: 0.52).opacity(0.42) : Color.clear, lineWidth: 1.2)
        }
    }
}
