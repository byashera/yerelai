import AVFoundation
import Photos
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
    @State private var showDeleteConfirm: Bool = false
    @State private var showScrollToBottom: Bool = false
    @State private var scrollToBottomTrigger: Int = 0
    @State private var showPlusMenu: Bool = false
    @State private var showTemporarySheet: Bool = false
    @State private var showContextSheet: Bool = false
    @State private var sidebarDragOffset: CGFloat = 0
    @State private var greetingIndex: Int = Int.random(in: 0..<6)
    @State private var placeholderIndex: Int = Int.random(in: 0..<6)
    @State private var containerWidth: CGFloat = 393
    @AppStorage("senai_initial_perms_v1") private var didRequestInitialPerms: Bool = false
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let drawerWidth = min(containerWidth * 0.82, 324)
        let currentOffset: CGFloat = showSidebar
            ? min(drawerWidth, max(0, drawerWidth + sidebarDragOffset))
            : min(drawerWidth, max(0, sidebarDragOffset))
        let sidebarProgress: CGFloat = drawerWidth > 0 ? (currentOffset / drawerWidth) : 0

        ZStack(alignment: .leading) {
            // Left Slide-Over Sidebar (interactive 1:1 finger tracking + spring snap)
            if showSidebar || sidebarDragOffset > 0 {
                SidebarView(
                    isPresented: $showSidebar,
                    showSettings: $showSettings,
                    showModelSheet: $showModelSheet
                )
                .frame(width: drawerWidth)
                .offset(x: -drawerWidth * 0.18 * (1 - sidebarProgress))
                .opacity(0.45 + 0.55 * sidebarProgress)
            }

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
                            Color.black.opacity(0.04)
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
                                        .padding(.bottom, 70)
                                    Spacer()
                                }
                            }
                            .transition(.scale(scale: 0.86, anchor: .bottomLeading).combined(with: .opacity))
                        }
                    }
                    .onAppear {
                        server.webSearchEnabled = false
                        server.useLibraryEnabled = false
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
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showSidebar = true
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                            }
                            .accessibilityLabel("Sohbet Geçmişi")
                        }

                        ToolbarItem(placement: .principal) {
                            if !server.isTemporaryChat {
                                modelPickerMenu
                            }
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
                                        Image(systemName: server.isTemporaryChat ? "checkmark.bubble" : "circle.dashed")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color.primary)
                                    }
                                    .accessibilityLabel(server.isTemporaryChat ? "Geçici Sohbeti Kapat" : "Geçici Sohbet")
                                } else {
                                    Button {
                                        SenHaptics.light()
                                        showContextSheet = true
                                    } label: {
                                        MiniContextRingButton(
                                            percent: server.contextPercent,
                                            ratio: server.contextFillRatio
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .accessibilityLabel("Bağlam Kullanımı: Yüzde \(server.contextPercent)")

                                    Menu {
                                        Button {
                                            greetingIndex = Int.random(in: 0..<6)
                                            placeholderIndex = Int.random(in: 0..<6)
                                            server.startNewChat()
                                        } label: {
                                            Label("Yeni Sohbet", systemImage: "square.and.pencil")
                                        }
                                        if !server.isTemporaryChat {
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
                                                    showDeleteConfirm = true
                                                } label: {
                                                    Label("Sil", systemImage: "trash")
                                                }
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
                    .alert("Sohbeti Yeniden Adlandır", isPresented: $showRenameAlert) {
                        TextField("Yeni başlık", text: $renameDraft)
                        Button("İptal", role: .cancel) {}
                        Button("Kaydet") {
                            let next = renameDraft
                            Task { await server.renameSession(server.activeSessionId, newTitle: next) }
                        }
                    }
                    .alert("Sohbeti Sil?", isPresented: $showDeleteConfirm) {
                        Button("İptal", role: .cancel) {}
                        Button("Sil", role: .destructive) {
                            Task { await server.deleteSession(server.activeSessionId) }
                        }
                    } message: {
                        Text("“\(server.currentSessionTitle)” sohbeti kalıcı olarak silinecek.")
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView()
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showModelSheet) {
                        ModelPickerSheetView(showSettings: $showSettings)
                            .presentationDetents([.height(520), .medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showContextSheet) {
                        ContextSheetView()
                            .presentationDetents([.height(300)])
                            .presentationDragIndicator(.visible)
                    }
                    .sheet(isPresented: $showTemporarySheet) {
                        TemporaryChatSettingsSheet(isPersonalized: $server.temporaryPersonalized)
                            .presentationDetents([.height(340)])
                            .presentationDragIndicator(.hidden)
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
                .mask {
                    RoundedRectangle(cornerRadius: 36 * sidebarProgress, style: .continuous)
                        .ignoresSafeArea()
                }
                .shadow(color: Color.black.opacity(0.14 * sidebarProgress), radius: 24, x: -6, y: 0)
                .overlay {
                    if showSidebar {
                        Color.white.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showSidebar = false
                                }
                            }
                    }
                }
                .offset(x: currentOffset)
            }
            .background {
                SenAmbientBackground()
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in containerWidth = w }
                }
                .ignoresSafeArea()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 16, coordinateSpace: .global)
                    .onChanged { value in
                        let tx = value.translation.width
                        let ty = value.translation.height
                        guard abs(tx) > abs(ty) * 1.35 else { return }
                        if !showSidebar {
                            guard value.startLocation.x < 56, tx > 0 else { return }
                            inputFocused = false
                            showPlusMenu = false
                            sidebarDragOffset = min(drawerWidth, tx)
                        } else {
                            guard tx < 0 else { return }
                            sidebarDragOffset = max(-drawerWidth, tx)
                        }
                    }
                    .onEnded { value in
                        let tx = value.translation.width
                        let predicted = value.predictedEndTranslation.width
                        if !showSidebar {
                            if value.startLocation.x < 56 && (tx > 72 || predicted > 130) {
                                SenHaptics.light()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                    showSidebar = true
                                    sidebarDragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    sidebarDragOffset = 0
                                }
                            }
                        } else {
                            if tx < -64 || predicted < -120 {
                                SenHaptics.light()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    showSidebar = false
                                    sidebarDragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    sidebarDragOffset = 0
                                }
                            }
                        }
                    }
            )
            .task {
                await requestInitialPermissionsIfNeeded()
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showSidebar)
    }

    private func requestInitialPermissionsIfNeeded() async {
        guard initialPreviewScreen == nil, !didRequestInitialPerms else { return }
        didRequestInitialPerms = true
        try? await Task.sleep(for: .milliseconds(700))
        location.requestInitialAuthorization()
        try? await Task.sleep(for: .milliseconds(500))
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        try? await Task.sleep(for: .milliseconds(400))
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
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
                Text(server.activeModelName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
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
        if server.activeModelOption?.isCloud == true { return Color(red: 0.96, green: 0.62, blue: 0.04) }
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

    private var heroPromptSubtitle: String {
        let lines = [
            "nasıl yardımcı olabilirim?",
            "bugün birlikte ne üretelim?",
            "aklında ne var, nereden başlayalım?",
            "hazırım, ne üzerinde çalışıyoruz?",
            "bir fikrin, kodun ya da sorun mu var?",
            "bugün hangi konuyu çözelim?",
        ]
        return lines[greetingIndex % lines.count]
    }

    private var composerPlaceholder: String {
        if server.isTemporaryChat { return "Geçici sohbet" }
        let items = [
            "SEN.AI'ye bir şey sor...",
            "Bir soru sor veya kod yapıştır...",
            "Bugün neyi araştıralım?",
            "Aklındaki fikri yaz veya fotoğraf ekle...",
            "Karşılaştırma, tablo veya hızlı bir soru...",
            "Mesajını yaz...",
        ]
        return items[placeholderIndex % items.count]
    }

    // MARK: - Temporary Chat Hero (ChatGPT IMG_5025.jpg exact match — no extra icon or pill box)

    private var temporaryChatHero: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                Spacer(minLength: inputFocused ? 40 : 175)

                Text("Geçici sohbet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary.opacity(0.75))

                Text("Bu sohbet, geçmişinde görünmeyecek.")
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
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

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
                    Text(heroPromptSubtitle)
                        .font(inputFocused ? .title2.weight(.bold) : .title.weight(.bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.primary, Color(red: 0.23, green: 0.51, blue: 0.96)], startPoint: .leading, endPoint: .trailing)
                        )
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
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
                    if let originTitle = server.messages.first?.forkedFromTitle, !originTitle.isEmpty {
                        let originId = server.messages.first?.forkedFromId
                        HStack {
                            Spacer()
                            Button {
                                if let oid = originId, server.sessions.contains(where: { $0.id == oid }) {
                                    SenHaptics.light()
                                    Task { await server.openSession(oid) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.blue)
                                    Text("**\(originTitle)** sohbetinden yeni dal oluşturuldu")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(SenSpringButtonStyle())
                            .senGlassCapsule(interactive: originId != nil)
                            Spacer()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
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
                            if showScrollToBottom {
                                withAnimation(.snappy(duration: 0.20)) {
                                    showScrollToBottom = false
                                }
                            }
                        }
                        .onDisappear {
                            if !server.messages.isEmpty && !showScrollToBottom {
                                withAnimation(.snappy(duration: 0.20)) {
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
        let isExpanded = inputFocused || !isEmpty || hasActivePills
        let cornerRadius: CGFloat = isExpanded ? 28 : 24

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

                // Single Persistent TextField (never swaps view identity on character threshold so keyboard stays locked!)
                HStack(alignment: .bottom, spacing: 6) {
                    plusButton

                    TextField(
                        composerPlaceholder,
                        text: $draft,
                        axis: .vertical
                    )
                    .lineLimit(1...6)
                    .font(.body)
                    .focused($inputFocused)
                    .padding(.vertical, isExpanded ? 11 : 6)

                    trailingActionButton(isEmpty: isEmpty)
                        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isEmpty)
                }
                .padding(.horizontal, isExpanded ? 10 : 8)
                .padding(.vertical, isExpanded ? 8 : 4)
            }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.72))
            }
            .senGlassRounded(radius: cornerRadius, interactive: false)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.07),
                radius: isExpanded ? 16 : 10,
                y: isExpanded ? 5 : 3
            )
            .padding(.horizontal, isExpanded ? 12 : 24)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.34, dampingFraction: 0.80), value: isExpanded)
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
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(colorScheme == .dark ? Color(.tertiarySystemBackground) : Color.white)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 8, y: 2)
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
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
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
                    .background {
                        Circle()
                            .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.45, blue: 0.98), Color(red: 0.31, green: 0.27, blue: 0.90)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .shadow(color: Color.blue.opacity(0.32), radius: 8, y: 3)
            }
            .buttonStyle(SenSpringButtonStyle())
            .transition(.scale(scale: 0.75).combined(with: .opacity))
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
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating.speed(0.5))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.15, green: 0.39, blue: 0.92), Color(red: 0.31, green: 0.27, blue: 0.90)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .shadow(color: Color.blue.opacity(0.36), radius: 10, y: 3)
            }
            .buttonStyle(SenSpringButtonStyle())
            .transition(.scale(scale: 0.75).combined(with: .opacity))
            .accessibilityLabel("Sesli Ajan Modu")
        }
    }

    // MARK: - iOS 26 Floating Liquid Glass (+) Popover Menu (ChatGPT-style translucent glass, monochrome single-line rows)

    private var plusPopoverMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            plusMenuRow(icon: "camera", title: "Kamera", isActive: false) {
                showPlusMenu = false
                showCamera = true
            }
            plusMenuRow(icon: "photo.on.rectangle", title: "Fotoğraflar", isActive: false) {
                showPlusMenu = false
                showPhotoPicker = true
            }
            plusMenuRow(icon: "globe", title: "Web'de araştır", isActive: server.webSearchEnabled) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    server.webSearchEnabled.toggle()
                    showPlusMenu = false
                }
            }
            plusMenuRow(icon: "books.vertical", title: "Kütüphane", isActive: server.useLibraryEnabled) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                    server.useLibraryEnabled.toggle()
                    showPlusMenu = false
                }
            }
            plusMenuRow(icon: "gearshape", title: "Ayarlar", isActive: false) {
                showPlusMenu = false
                showSettings = true
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(width: 264)
        .senGlassRounded(radius: 30, interactive: true)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 22, y: 8)
    }

    private func plusMenuRow(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SenHaptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    }
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
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
                            UnevenRoundedRectangle(
                                topLeadingRadius: 20,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 6,
                                topTrailingRadius: 20,
                                style: .continuous
                            )
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 20,
                                    bottomLeadingRadius: 20,
                                    bottomTrailingRadius: 6,
                                    topTrailingRadius: 20,
                                    style: .continuous
                                )
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                            }
                            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
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
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    ModelBadgeIcon(
                        modelId: msg.modelId ?? server.selectedModelId,
                        isSelected: msg.isStreaming,
                        size: 24
                    )
                    Text("SEN.AI")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(server.modelDisplayName(for: msg.modelId))
                        .font(.system(size: 11, weight: .regular).italic())
                        .foregroundStyle(.secondary.opacity(0.82))
                    if let persona = msg.autoPersona, !persona.isEmpty {
                        Text("Uzman: \(persona)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background { Capsule().fill(.secondary.opacity(0.12)) }
                    }
                    Spacer(minLength: 0)
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
                    case .cardLoading(let kind):
                        SenCardSkeletonView(kind: kind)
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
                                Task { await server.forkChat(at: msg.id) }
                            } label: {
                                Label("Bu Mesajdan Yeni Dal Oluştur", systemImage: "arrow.triangle.branch")
                            }
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
                                if let snip = src.snippet, !snip.isEmpty {
                                    Text(snip)
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
        VStack(spacing: 14) {
            Text("Geçici sohbet ayarları")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .padding(.top, 18)

            optionCard(
                title: "Kişiselleştirilmiş",
                subtitle: "Bu sohbet bellekten, eklentilerden ve özel talimatlardan yararlanabilir",
                selected: isPersonalized
            ) {
                SenHaptics.light()
                isPersonalized = true
            }

            optionCard(
                title: "Kişiselleştirilmemiş",
                subtitle: "Bu sohbet belleği, eklentileri ve özel talimatları yoksayacak",
                selected: !isPersonalized
            ) {
                SenHaptics.light()
                isPersonalized = false
            }

            Button {
                SenHaptics.light()
                dismiss()
            } label: {
                Text("Bitti")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        Capsule().fill(Color.primary)
                    }
            }
            .buttonStyle(SenSpringButtonStyle())
            .padding(.top, 4)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 20)
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
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.primary)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? Color.primary : Color.primary.opacity(0.10), lineWidth: selected ? 1.5 : 0.8)
                    }
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ThinkingEffortSliderView(
                        effort: Binding(
                            get: { server.thinkingEffort },
                            set: { server.thinkingEffort = $0 }
                        ),
                        supportsMax: server.supportsMaxThinking
                    )

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Aktif Model")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Yerel · Bulut")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background { Capsule().fill(Color.primary.opacity(0.07)) }
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 9) {
                            ForEach(server.availableModels) { m in
                                let selected = server.selectedModelId == m.id
                                let isOrion = m.isCloud || m.id.lowercased().contains("orion")
                                let isE4B = !isOrion && m.id.lowercased().contains("e4b")
                                let accent: Color = isOrion
                                    ? Color(red: 0.90, green: 0.56, blue: 0.08)
                                    : (isE4B ? Color.purple : Color.teal)
                                Button {
                                    SenHaptics.light()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                        server.selectedModelId = m.id
                                        if !server.supportsMaxThinking && server.thinkingEffort == .max {
                                            server.thinkingEffort = .high
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { dismiss() }
                                } label: {
                                    HStack(spacing: 13) {
                                        ModelBadgeIcon(modelId: m.id, isSelected: selected, size: 42)
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(m.name)
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(.primary)
                                                Text(m.badge)
                                                    .font(.system(size: 10.5, weight: .bold))
                                                    .foregroundStyle(accent)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background {
                                                        Capsule()
                                                            .fill(accent.opacity(0.14))
                                                            .overlay {
                                                                Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 0.7)
                                                            }
                                                    }
                                            }
                                            Text(m.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(accent)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    .padding(13)
                                    .senGlassRounded(radius: 20, interactive: true)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(selected ? accent.opacity(0.52) : Color.clear, lineWidth: 1.3)
                                    }
                                }
                                .buttonStyle(SenSpringButtonStyle())
                            }
                        }
                    }
                }
                .padding(18)
            }
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
    let modelId: String
    let isSelected: Bool
    var size: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var spin = false

    private var isOrion: Bool { modelId.lowercased().contains("orion") }
    private var isAureon: Bool { !isOrion && modelId.lowercased().contains("e4b") }

    var body: some View {
        let radius = size * 0.30
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(backgroundGradient)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(isOrion ? 0.26 : 0.34), lineWidth: 0.9)
                }
                .shadow(color: glowColor.opacity(isSelected ? 0.44 : 0.18), radius: isSelected ? 10 : 4, y: 3)

            if isOrion {
                // Orion: Obsidian-Gold 3-Star Belt + Dashed Orbit Ring
                Circle()
                    .stroke(Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.65), style: StrokeStyle(lineWidth: max(1, size * 0.03), dash: [3, 2.5]))
                    .frame(width: size * 0.72, height: size * 0.72)
                    .rotationEffect(.degrees(spin ? 360 : 0))

                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.75, blue: 0.14))
                        .frame(width: size * 0.14, height: size * 0.14)
                        .offset(x: -size * 0.16, y: size * 0.12)
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.20, height: size * 0.20)
                    Circle()
                        .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                        .frame(width: size * 0.14, height: size * 0.14)
                        .offset(x: size * 0.16, y: -size * 0.12)
                }
                .scaleEffect(pulse ? 1.09 : 0.94)
            } else if isAureon {
                // Aureon 1.1: Violet-Gold Orbital Star
                Circle()
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: max(1, size * 0.03), dash: [3.5, 2.5]))
                    .frame(width: size * 0.74, height: size * 0.74)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.10 : 0.94)
            } else {
                // Sage 1: Emerald-Cyan Luminous Prism
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.10 : 0.94)
            }
        }
        .onAppear {
            guard !reduceMotion, isSelected else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    private var backgroundGradient: LinearGradient {
        if isOrion {
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.12), Color(red: 0.14, green: 0.11, blue: 0.09), Color(red: 0.68, green: 0.36, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if isAureon {
            return LinearGradient(
                colors: [Color(red: 0.24, green: 0.19, blue: 0.68), Color(red: 0.49, green: 0.22, blue: 0.92), Color(red: 0.88, green: 0.32, blue: 0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.08, green: 0.72, blue: 0.65), Color(red: 0.06, green: 0.73, blue: 0.51)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glowColor: Color {
        if isOrion { return Color(red: 0.96, green: 0.62, blue: 0.04) }
        if isAureon { return Color.purple }
        return Color.teal
    }
}

struct ThinkingEffortSliderView: View {
    @Binding var effort: ThinkingEffort
    var supportsMax: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragFraction: CGFloat? = nil

    private var levels: [ThinkingEffort] {
        supportsMax ? [.off, .low, .medium, .high, .max] : [.off, .low, .medium, .high]
    }

    private var currentIndex: Int {
        levels.firstIndex(of: effort) ?? 0
    }

    private var displayFraction: CGFloat {
        dragFraction ?? (CGFloat(currentIndex) / CGFloat(max(1, levels.count - 1)))
    }

    private var accentColor: Color {
        switch effort {
        case .off: return .secondary
        case .low: return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .medium: return Color(red: 0.02, green: 0.52, blue: 0.78)
        case .high: return Color(red: 0.49, green: 0.23, blue: 0.93)
        case .max: return Color(red: 0.88, green: 0.11, blue: 0.28)
        }
    }

    private var subtitleText: String {
        switch effort {
        case .off: return "Doğrudan hızlı yanıt."
        case .low: return "Hızlı ve öz akıl yürütme."
        case .medium: return "Dengeli akıl yürütme."
        case .high: return "Derin analiz ve hata ayıklama."
        case .max: return "Maksimum derinlik ve uzun analiz."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(effort.label)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(accentColor)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.22), value: effort)

                    if effort == .max {
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.needle.fill")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("Yüksek Bağlam Kullanımı")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .foregroundStyle(Color(red: 0.88, green: 0.11, blue: 0.28))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .senGlassCapsule(interactive: false, tint: .red)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.2), value: effort)
            }

            GeometryReader { geo in
                let trackW = max(geo.size.width, 120)
                let thumbD: CGFloat = 34
                let usableW = max(trackW - thumbD, 1)
                let frac = min(max(displayFraction, 0), 1)
                let thumbX = frac * usableW
                let isDragging = dragFraction != nil

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.09))
                        .overlay {
                            Capsule().strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.8)
                        }

                    if frac > 0.01 {
                        let fillW = max(thumbX + thumbD, thumbD)
                        ZStack {
                            if effort == .max {
                                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                                    let t = timeline.date.timeIntervalSinceReferenceDate
                                    let shift = sin(t * 2.8) * 0.18
                                    ZStack {
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.60, green: 0.11, blue: 0.11),
                                                Color(red: 0.86, green: 0.15, blue: 0.15),
                                                Color(red: 0.96, green: 0.25, blue: 0.37),
                                                Color(red: 0.98, green: 0.44, blue: 0.52),
                                            ],
                                            startPoint: UnitPoint(x: 0.0 + shift, y: 0.5),
                                            endPoint: UnitPoint(x: 1.0 + shift, y: 0.5)
                                        )
                                        Canvas { ctx, size in
                                            let seeds: [(Double, CGFloat, CGFloat, Double, Bool)] = [
                                                (0.02, 0.26, 2.5, 0.95, true),  (0.08, 0.72, 2.0, 1.15, false),
                                                (0.14, 0.44, 2.9, 1.05, true),  (0.20, 0.20, 1.8, 1.25, false),
                                                (0.26, 0.66, 2.6, 0.92, true),  (0.32, 0.35, 2.2, 1.18, false),
                                                (0.38, 0.78, 2.7, 1.08, true),  (0.44, 0.28, 1.9, 1.32, false),
                                                (0.50, 0.54, 3.0, 0.98, true),  (0.56, 0.70, 2.1, 1.22, false),
                                                (0.62, 0.32, 2.6, 1.10, true),  (0.68, 0.60, 2.0, 1.28, false),
                                                (0.74, 0.24, 2.4, 1.02, true),  (0.80, 0.48, 2.8, 0.96, true),
                                                (0.86, 0.74, 1.9, 1.20, false), (0.92, 0.40, 2.3, 1.12, true),
                                            ]
                                            for (phase, py, rad, speed, isBright) in seeds {
                                                let prog = (t * speed + phase).truncatingRemainder(dividingBy: 1.0)
                                                let xNorm = CGFloat(1.0 - prog)
                                                let px = xNorm * max(size.width - 12, 1)
                                                let pyJitter = py * size.height + CGFloat(sin(t * 4.0 + phase * 10.0)) * 2.0
                                                let edgeFade = min(xNorm * 4.5, (1.0 - xNorm) * 6.0, 1.0)
                                                let alpha = Double(edgeFade) * (0.65 + 0.35 * abs(sin(t * 5.2 + phase * 8.0)))
                                                var trail = Path()
                                                trail.move(to: CGPoint(x: px, y: pyJitter))
                                                trail.addLine(to: CGPoint(x: px + rad * 4.2, y: pyJitter))
                                                ctx.stroke(trail, with: .color(Color.white.opacity(alpha * 0.42)), style: StrokeStyle(lineWidth: rad * 0.9, lineCap: .round))
                                                let rect = CGRect(x: px - rad, y: pyJitter - rad, width: rad * 2, height: rad * 2)
                                                ctx.fill(Path(ellipseIn: rect), with: .color((isBright ? Color.white : Color(red: 1.0, green: 0.80, blue: 0.84)).opacity(alpha)))
                                            }
                                        }
                                    }
                                }
                            } else if effort == .high {
                                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                                    let t = timeline.date.timeIntervalSinceReferenceDate
                                    ZStack {
                                        LinearGradient(
                                            colors: [Color(red: 0.15, green: 0.39, blue: 0.92), Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.66, green: 0.33, blue: 0.97)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        Canvas { ctx, size in
                                            let seeds: [(Double, CGFloat, CGFloat, Double)] = [
                                                (0.05, 0.30, 1.8, 0.42), (0.20, 0.68, 1.6, 0.55), (0.36, 0.42, 2.1, 0.48),
                                                (0.52, 0.72, 1.7, 0.50), (0.68, 0.28, 2.0, 0.44), (0.84, 0.56, 1.8, 0.52),
                                            ]
                                            for (phase, py, rad, speed) in seeds {
                                                let prog = (t * speed + phase).truncatingRemainder(dividingBy: 1.0)
                                                let px = CGFloat(1.0 - prog) * max(size.width - 12, 1)
                                                let pyPos = py * size.height
                                                let rect = CGRect(x: px - rad, y: pyPos - rad, width: rad * 2, height: rad * 2)
                                                ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.75)))
                                            }
                                        }
                                    }
                                }
                            } else if effort == .medium {
                                LinearGradient(
                                    colors: [Color(red: 0.02, green: 0.59, blue: 0.41), Color(red: 0.01, green: 0.52, blue: 0.78), Color(red: 0.15, green: 0.39, blue: 0.92)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                LinearGradient(
                                    colors: [Color(red: 0.20, green: 0.83, blue: 0.60), Color(red: 0.02, green: 0.71, blue: 0.83)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                        }
                        .frame(width: fillW)
                        .clipShape(Capsule())
                    }

                    HStack {
                        ForEach(0..<levels.count, id: \.self) { i in
                            let dotFrac = CGFloat(i) / CGFloat(max(1, levels.count - 1))
                            Circle()
                                .fill(dotFrac <= frac ? Color.white.opacity(0.74) : Color.primary.opacity(0.28))
                                .frame(width: 5, height: 5)
                            if i < levels.count - 1 { Spacer() }
                        }
                    }
                    .padding(.horizontal, thumbD / 2 - 2.5)

                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbD, height: thumbD)
                        .overlay {
                            Circle()
                                .fill(accentColor.opacity(effort == .off ? 0.25 : 0.85))
                                .frame(width: 12, height: 12)
                        }
                        .scaleEffect(isDragging ? 1.10 : 1.0)
                        .shadow(color: (effort == .max ? Color.red : Color.black).opacity(isDragging ? 0.44 : 0.26), radius: isDragging ? 10 : 6, y: 2)
                        .offset(x: thumbX)
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isDragging)
                }
                .frame(height: 38)
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let clamped = min(max((val.location.x - thumbD / 2) / usableW, 0), 1)
                            dragFraction = clamped
                            let idx = Int(round(clamped * CGFloat(levels.count - 1)))
                            let target = levels[min(max(idx, 0), levels.count - 1)]
                            if target != effort {
                                if target == .max || target == .high { SenHaptics.medium() } else { SenHaptics.light() }
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
            .frame(height: 40)

            HStack {
                ForEach(levels) { lv in
                    Button {
                        if lv == .max || lv == .high { SenHaptics.medium() } else { SenHaptics.light() }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) {
                            effort = lv
                        }
                    } label: {
                        Text(lv.label)
                            .font(.system(size: 11, weight: effort == lv ? .bold : .medium))
                            .foregroundStyle(effort == lv ? accentColor : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .senGlassRounded(radius: 22, interactive: false)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(effort == .max ? Color.red.opacity(0.42) : (effort == .high ? Color.indigo.opacity(0.32) : Color.clear), lineWidth: 1.2)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: effort)
    }
}

// MARK: - iOS Native Mini Context Ring & Activity-Ring Liquid Glass Context Sheet

struct MiniContextRingButton: View {
    let percent: Int
    let ratio: Double

    private var ringColor: Color {
        if percent >= 88 { return .red }
        if percent >= 70 { return .orange }
        return Color(red: 0.14, green: 0.52, blue: 0.98)
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.14), lineWidth: 2.3)
                Circle()
                    .trim(from: 0, to: max(0.04, ratio))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.45, dampingFraction: 0.82), value: ratio)
            }
            .frame(width: 15, height: 15)

            Text("%\(percent)")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(percent >= 70 ? ringColor : .primary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .senGlassCapsule(interactive: true)
    }
}

struct ContextSheetView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss

    private var ringColor: Color {
        if server.contextPercent >= 88 { return .red }
        if server.contextPercent >= 70 { return .orange }
        return Color(red: 0.14, green: 0.52, blue: 0.98)
    }

    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(0.03, server.contextFillRatio))
                        .stroke(
                            AngularGradient(
                                colors: [ringColor.opacity(0.65), ringColor, ringColor],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: server.contextFillRatio)

                    VStack(spacing: 1) {
                        Text("%\(server.contextPercent)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text("Bağlam")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(server.activeModelName)
                            .font(.headline.weight(.bold))
                        if let badge = server.activeModelOption?.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ringColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background { Capsule().fill(ringColor.opacity(0.14)) }
                        }
                    }
                    Text("~\(fmt(server.estimatedContextTokens)) / \(fmt(server.activeContextLimit)) token")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(server.activeModelOption?.isCloud == true ? "256K Bulut Bağlam Penceresi" : "Yerel GPU Slot Bağlam Penceresi")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .senGlassRounded(radius: 24, interactive: false)

            Button {
                SenHaptics.medium()
                Task {
                    await server.compactCurrentSession()
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if server.isCompacting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.subheadline.weight(.bold))
                    }
                    Text(server.isCompacting ? "Sıkıştırılıyor..." : "Konuşmayı Sıkıştır (/compact)")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.45, blue: 0.98), Color(red: 0.35, green: 0.28, blue: 0.92)], startPoint: .leading, endPoint: .trailing))
                }
            }
            .disabled(server.isCompacting || server.messages.count < 2)
            .opacity(server.messages.count < 2 ? 0.5 : 1)
            .buttonStyle(SenSpringButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
    }
}
