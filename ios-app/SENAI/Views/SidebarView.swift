import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("senai_theme") private var themePref: String = "system"
    @Binding var showSettings: Bool
    @State private var searchText: String = ""
    @State private var renameTarget: ChatSessionSummary? = nil
    @State private var renameDraft: String = ""

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
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed Top Search Bar (never floats at the bottom of the sheet over rows!)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Sohbetlerde ara...", text: $searchText)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
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
                .padding(.top, 8)
                .padding(.bottom, 6)

                List {
                    Section {
                        Button {
                            server.startNewChat()
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.bubble.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.blue)
                                Text("Yeni Sohbet Başlat")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(server.connectionRoute == .disconnected ? Color.orange : Color.green)
                                        .frame(width: 6, height: 6)
                                    Text(server.connectionRoute == .lan ? "Wi-Fi" : (server.connectionRoute == .cloudflare ? "Uzaktan" : "Bağlı değil"))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                    }

                    if !pinnedSessions.isEmpty {
                        Section("Sabitlenenler") {
                            ForEach(pinnedSessions) { s in
                                sessionRow(s)
                            }
                        }
                    }

                    Section("Sohbet Geçmişi") {
                        if regularSessions.isEmpty && pinnedSessions.isEmpty {
                            Text("Henüz kayıtlı sohbet yok")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if regularSessions.isEmpty {
                            Text("Diğer sohbet yok")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(regularSessions) { s in
                                sessionRow(s)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("SEN.AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        themePref = (themePref == "dark") ? "light" : "dark"
                        SenHaptics.light()
                    } label: {
                        Image(systemName: themePref == "dark" ? "sun.max.fill" : "moon.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showSettings = true
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
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
        }
    }

    @ViewBuilder
    private func sessionRow(_ s: ChatSessionSummary) -> some View {
        let isPinned = s.pinned == true
        Button {
            Task {
                await server.openSession(s.id)
                dismiss()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPinned ? "pin.fill" : (server.activeSessionId == s.id ? "bubble.left.fill" : "bubble.left"))
                    .font(.caption)
                    .foregroundStyle(isPinned ? Color.orange : (server.activeSessionId == s.id ? Color.blue : Color.secondary))
                Text(s.title)
                    .font(.subheadline.weight(server.activeSessionId == s.id ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if server.activeSessionId == s.id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await server.togglePinSession(s.id) }
            } label: {
                Label(isPinned ? "Kaldır" : "Sabitle", systemImage: isPinned ? "pin.slash" : "pin.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await server.deleteSession(s.id) }
            } label: {
                Label("Sil", systemImage: "trash")
            }
            Button {
                renameDraft = s.title
                renameTarget = s
            } label: {
                Label("Adlandır", systemImage: "pencil")
            }
            .tint(.blue)
        }
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
                Task { await server.deleteSession(s.id) }
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }
}
