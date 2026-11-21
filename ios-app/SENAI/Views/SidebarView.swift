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
                        Label("Yeni Sohbet Başlat", systemImage: "plus.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                    }
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
                                HStack {
                                    Text(s.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if server.activeSessionId == s.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
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
