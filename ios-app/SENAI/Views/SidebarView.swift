import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("senai_theme") private var themePref: String = "system"
    @Binding var showSettings: Bool
    @State private var searchText: String = ""

    private var filtered: [ChatSessionSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return server.sessions }
        return server.sessions.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
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
                                Text(server.connectionRoute == .lan ? "Wi-Fi" : (server.connectionRoute == .cloudflare ? "Bulut" : "Bağlı değil"))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }

                Section("Sohbet Geçmişi") {
                    if filtered.isEmpty {
                        Text("Henüz kayıtlı sohbet yok")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { s in
                            Button {
                                Task {
                                    await server.openSession(s.id)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: server.activeSessionId == s.id ? "bubble.left.fill" : "bubble.left")
                                        .font(.caption)
                                        .foregroundStyle(server.activeSessionId == s.id ? .blue : .secondary)
                                    Text(s.title)
                                        .font(.subheadline.weight(server.activeSessionId == s.id ? .semibold : .regular))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if let dt = s.updated_at, !dt.isEmpty {
                                        Text(dt)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if server.activeSessionId == s.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Sohbetlerde ara...")
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
        }
    }
}
