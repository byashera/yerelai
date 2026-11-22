import SwiftUI

// MARK: - ChatGPT-Style Grouped Card Settings View

struct SettingsView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("senai_theme") private var themePref: String = "light"
    @State private var showServerAddresses: Bool = false
    @State private var showAbout: Bool = false

    private var themeLabel: String {
        switch themePref {
        case "dark": return "Koyu"
        case "light": return "Açık"
        default: return "Sistem"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Top Connection Status Card (matches ChatGPT's top hero card)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SEN.AI Yerel Stüdyo")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(server.connectionRoute == .disconnected ? Color.orange : Color.green)
                                    .frame(width: 7, height: 7)
                                Text(server.connectionRoute == .disconnected ? "Bağlantı bekleniyor" : server.connectionRoute.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !server.activeBaseURL.isEmpty {
                                Text(server.activeBaseURL)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            SenHaptics.light()
                            Task { await server.bootstrap() }
                        } label: {
                            if server.isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            } else {
                                Text("Bağlan")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                        }
                        .background { Capsule().fill(Color.blue) }
                        .buttonStyle(SenSpringButtonStyle())
                    }
                    .padding(16)
                    .background { cardBackground }

                    // Group 1: Sunucu & Bağlantı
                    VStack(spacing: 0) {
                        Button {
                            showServerAddresses = true
                        } label: {
                            settingsRow(
                                icon: "network",
                                title: "Sunucu Adresleri",
                                detail: server.connectionRoute == .lan ? "LAN" : "Köprü",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .background { cardBackground }

                    // Group 2: SEN.AI'yı Özelleştir
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                                .font(.system(size: 17))
                                .foregroundStyle(.primary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Web Araştırması Etiketi")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text("Kapalıyken ürün/mekân soruları yine oto-aranır")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $server.webSearchEnabled)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.leading, 52).opacity(0.4)

                        HStack(spacing: 12) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 17))
                                .foregroundStyle(.primary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Yerel Kütüphane (RAG)")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text("Yüklü PDF/belgelerden yanıt üretir")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $server.useLibraryEnabled)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background { cardBackground }

                    // Group 3: Genel & Sesli İletişim
                    VStack(spacing: 0) {
                        Menu {
                            Button("Açık (Beyaz)") { themePref = "light" }
                            Button("Koyu") { themePref = "dark" }
                            Button("Sistem") { themePref = "system" }
                        } label: {
                            settingsRow(icon: "paintbrush", title: "Görünüm", detail: themeLabel, showChevron: true)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 52).opacity(0.4)

                        Menu {
                            Button("Ahmet (Erkek · Neural)") { server.ttsVoice = "tr-TR-AhmetNeural" }
                            Button("Emel (Kadın · Neural)") { server.ttsVoice = "tr-TR-EmelNeural" }
                        } label: {
                            settingsRow(
                                icon: "waveform",
                                title: "Sesli İletişim",
                                detail: server.ttsVoice.contains("Emel") ? "Emel" : "Ahmet",
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 52).opacity(0.4)

                        settingsRow(
                            icon: "cpu",
                            title: "Aktif Model",
                            detail: server.activeModelName,
                            showChevron: false
                        )
                    }
                    .background { cardBackground }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showServerAddresses) {
                ServerAddressesSettingsView()
            }
            .alert("SEN.AI Hakkında", isPresented: $showAbout) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text("SEN.AI iOS 26 Liquid Glass\nTüm sohbetler ve veriler yalnızca kendi yerel sunucunuzda saklanır.")
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .shadow(color: Color.black.opacity(0.035), radius: 8, y: 2)
    }

    private func settingsRow(icon: String, title: String, detail: String? = nil, showChevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .frame(width: 24)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct ServerAddressesSettingsView: View {
    @EnvironmentObject private var server: ServerManager

    var body: some View {
        Form {
            Section("Yerel Ağ & Köprü") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ev Wi-Fi (LAN) Adresi").font(.caption).foregroundStyle(.secondary)
                    TextField("http://192.168.1.22:8070", text: $server.lanURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sabit GitHub Gist JSON Köprüsü").font(.caption).foregroundStyle(.secondary)
                    TextField("https://gist.githubusercontent.com/...", text: $server.gistJsonURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manuel Sunucu / Tünel Adresi (Opsiyonel)").font(.caption).foregroundStyle(.secondary)
                    TextField("https://....trycloudflare.com", text: $server.customURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            Section {
                Button("Bağlantıyı Test Et ve Kaydet") {
                    Task { await server.bootstrap() }
                }
            }
        }
        .navigationTitle("Sunucu Adresleri")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PinLockView: View {
    @EnvironmentObject private var server: ServerManager
    @State private var pin: String = ""

    var body: some View {
        ZStack {
            SenAmbientBackground()
            VStack(spacing: 20) {
                SenPrismOrb(size: 62)
                Text("SEN.AI Kilitli")
                    .font(.title2.weight(.bold))
                SecureField("PIN Kodu", text: $pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced())
                    .padding(14)
                    .frame(maxWidth: 220)
                    .senGlassCapsule(interactive: false)
                Button("Kilidi Aç") {
                    Task { await server.verifyPin(pin) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
        }
    }
}
