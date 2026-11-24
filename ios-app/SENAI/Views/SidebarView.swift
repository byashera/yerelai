import SwiftUI

// MARK: - ChatGPT-Style Left Slide-Over Sidebar Drawer

struct SidebarView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("senai_theme") private var themePref: String = "light"
    @Binding var isPresented: Bool
    @Binding var showSettings: Bool
    @Binding var showModelSheet: Bool

    @State private var showSearch: Bool = false
    @State private var searchText: String = ""
    @State private var renameTarget: ChatSessionSummary? = nil
    @State private var renameDraft: String = ""
    @State private var deleteTarget: ChatSessionSummary? = nil

    private var filtered: [ChatSessionSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return server.sessions }
        return server.sessions.filter { $0.title.lowercased().contains(q) }
    }

    private var pinnedSessions: [ChatSessionSummary] {
        filtered.filter { $0.pinned == true }
    }

    private var regularSessions: [ChatSessionSummary] {
        filtered.filter { $0.pinned != true }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Brand Header + Search Circle (ChatGPT style)
            HStack {
                Text("SEN.AI")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    SenHaptics.light()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                } label: {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(SenSpringButtonStyle())
                .senGlassCircle(interactive: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if showSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Sohbetlerde ara...", text: $searchText)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Top Quick Navigation Shortcuts (ChatGPT iOS 26 style — clean monochrome, no right badge clutter)
                    VStack(spacing: 2) {
                        quickNavRow(icon: "books.vertical", title: "Kütüphane") {
                            server.useLibraryEnabled.toggle()
                            SenHaptics.light()
                            closeDrawer()
                        }
                        quickNavRow(icon: "slider.horizontal.3", title: "Özelleştir") {
                            closeDrawer()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                showModelSheet = true
                            }
                        }
                        quickNavRow(icon: "globe", title: "Web Araştırması") {
                            server.webSearchEnabled.toggle()
                            SenHaptics.light()
                            closeDrawer()
                        }
                        quickNavRow(
                            icon: themePref == "dark" ? "sun.max" : "moon",
                            title: themePref == "dark" ? "Açık Görünüm" : "Koyu Görünüm"
                        ) {
                            themePref = (themePref == "dark") ? "light" : "dark"
                            SenHaptics.light()
                        }
                    }
                    .padding(.horizontal, 10)

                    // Pinned Sessions
                    if !pinnedSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sabitlenenler")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 18)

                            ForEach(pinnedSessions) { s in
                                drawerSessionRow(s, isPinned: true)
                            }
                        }

                        Divider()
                            .opacity(0.45)
                            .padding(.horizontal, 18)
                    }

                    // Recent Sessions
                    VStack(alignment: .leading, spacing: 4) {
                        if regularSessions.isEmpty && pinnedSessions.isEmpty {
                            Text("Henüz kayıtlı sohbet yok")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(regularSessions) { s in
                                drawerSessionRow(s, isPinned: false)
                            }
                        }
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.top, 4)
            }
        }
        .overlay(alignment: .bottom) {
            // Floating Bottom Action Bar (New Chat Pill + Profile/Settings Circle)
            HStack {
                Button {
                    server.startNewChat()
                    closeDrawer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .bold))
                        Text("Yeni Sohbet")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background {
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.45, blue: 0.98), Color(red: 0.34, green: 0.28, blue: 0.92)], startPoint: .leading, endPoint: .trailing))
                            .shadow(color: Color.blue.opacity(0.32), radius: 10, y: 4)
                    }
                }
                .buttonStyle(SenSpringButtonStyle())

                Button {
                    SenHaptics.light()
                    closeDrawer()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        showSettings = true
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(SenSpringButtonStyle())
                .senGlassCircle(interactive: true)
                .accessibilityLabel("Ayarlar")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 10)
            .background {
                let bg = sidebarBackgroundColor
                LinearGradient(
                    colors: [bg.opacity(0), bg.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .background(sidebarBackgroundColor.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .frame(width: 0.7)
                .ignoresSafeArea()
        }
        .alert("Sohbeti Yeniden Adlandır", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Yeni başlık", text: $renameDraft)
            Button("İptal", role: .cancel) { renameTarget = nil }
            Button("Kaydet") {
                if let target = renameTarget {
                    let draft = renameDraft
                    renameTarget = nil
                    Task { await server.renameSession(target.id, newTitle: draft) }
                }
            }
        }
        .alert("Sohbeti Sil?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("İptal", role: .cancel) { deleteTarget = nil }
            Button("Sil", role: .destructive) {
                if let target = deleteTarget {
                    deleteTarget = nil
                    Task { await server.deleteSession(target.id) }
                }
            }
        } message: {
            Text("“\(deleteTarget?.title ?? "Bu sohbet")” kalıcı olarak silinecek.")
        }
    }

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.088, green: 0.118, blue: 0.192)
            : Color(red: 0.968, green: 0.970, blue: 0.978)
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isPresented = false
        }
    }

    private func quickNavRow(icon: String, title: String, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(Color.primary.opacity(0.06)) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func drawerSessionRow(_ s: ChatSessionSummary, isPinned: Bool) -> some View {
        let isActive = server.activeSessionId == s.id && !server.isTemporaryChat
        return Button {
            Task {
                await server.openSession(s.id)
                closeDrawer()
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isPinned ? "pin.fill" : (isActive ? "bubble.left.fill" : "bubble.left"))
                    .font(.system(size: isPinned ? 13 : 14, weight: .medium))
                    .foregroundStyle(isActive ? Color.blue : (isPinned ? Color.orange : Color.secondary.opacity(0.85)))
                    .frame(width: 18)
                Text(s.title)
                    .font(.body.weight(isActive ? .medium : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await server.togglePinSession(s.id) }
            } label: {
                Label(isPinned ? "Sabitlemeyi Kaldır" : "Sabitle", systemImage: isPinned ? "pin.slash" : "pin")
            }
            Button {
                renameDraft = s.title
                renameTarget = s
            } label: {
                Label("Yeniden Adlandır", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleteTarget = s
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    private func shortTimeLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.count <= 10 && !raw.contains("T") { return raw }
        let parts = raw.split(separator: "T")
        if parts.count == 2 {
            let timePart = String(parts[1].prefix(5))
            return timePart
        }
        return String(raw.prefix(10))
    }
}
