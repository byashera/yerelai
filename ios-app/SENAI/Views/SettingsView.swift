import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var server: ServerManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("senai_theme") private var themePref: String = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section("Bağlantı Durumu") {
                    HStack {
                        Label(server.connectionRoute.rawValue, systemImage: server.connectionRoute == .disconnected ? "wifi.slash" : "checkmark.circle.fill")
                            .foregroundStyle(server.connectionRoute == .disconnected ? .orange : .green)
                        Spacer()
                        if server.isConnecting {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if !server.activeBaseURL.isEmpty {
                        Text(server.activeBaseURL)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Button("Yeniden Bağlan") {
                        Task { await server.bootstrap() }
                    }
                }

                Section("Sunucu Adresleri") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ev Wi-Fi (LAN) Adresi").font(.caption).foregroundStyle(.secondary)
                        TextField("http://192.168.1.22:8070", text: $server.lanURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sabit GitHub Gist JSON Köprüsü").font(.caption).foregroundStyle(.secondary)
                        TextField("https://gist.githubusercontent.com/.../raw/senai.json", text: $server.gistJsonURL)
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

                Section("Görünüm & Ses") {
                    Picker("Tema", selection: $themePref) {
                        Text("Sistem").tag("system")
                        Text("Açık").tag("light")
                        Text("Koyu").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Picker("Türkçe Sesli Okuma", selection: $server.ttsVoice) {
                        Text("Ahmet (Erkek · Neural)").tag("tr-TR-AhmetNeural")
                        Text("Emel (Kadın · Neural)").tag("tr-TR-EmelNeural")
                    }

                    Toggle("Canlı Web Araştırması", isOn: $server.webSearchEnabled)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") {
                        Task { await server.bootstrap() }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
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
                Text("Devam etmek için erişim PIN kodunu girin.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SecureField("PIN Kodu", text: $pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced())
                    .padding(14)
                    .frame(maxWidth: 220)
                    .senGlassCapsule(interactive: false)

                if let err = server.pinError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Button {
                    Task { await server.verifyPin(pin) }
                } label: {
                    Text("Kilidi Aç")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 200, height: 46)
                }
                .buttonStyle(SenSpringButtonStyle())
                .senGlassCapsule(interactive: true, tint: .blue)
                .disabled(pin.isEmpty)
            }
            .padding(28)
        }
    }
}
