import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class ServerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // Persistent User Preferences
    @AppStorage("senai_lan_url") var lanURL: String = "http://192.168.1.22:8070"
    @AppStorage("senai_gist_url") var gistJsonURL: String = "https://gist.githubusercontent.com/byashera/a2d7ef6a838e83f17d72860b91d9458c/raw/yerelai_tunnel.json"
    @AppStorage("senai_custom_url") var customURL: String = ""
    @AppStorage("senai_tts_voice") var ttsVoice: String = "tr-TR-AhmetNeural"
    @AppStorage("senai_web_search") var webSearchEnabled: Bool = true
    @AppStorage("senai_model_id") var selectedModelId: String = "gemma-4-e4b-4bit"
    @AppStorage("senai_thinking") var thinkingEffortRaw: String = ThinkingEffort.off.rawValue

    // Live Connection & Auth State
    @Published var activeBaseURL: String = ""
    @Published var connectionRoute: ConnectionRoute = .disconnected
    @Published var isConnecting: Bool = false
    @Published var connectionError: String? = nil
    @Published var requiresPin: Bool = false
    @Published var pinError: String? = nil

    // Chat State
    @Published var sessions: [ChatSessionSummary] = []
    @Published var activeSessionId: String = UUID().uuidString.prefix(12).lowercased()
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var statusLine: String = ""
    @Published var speakingMessageId: String? = nil

    let availableModels: [ModelOption] = [
        ModelOption(id: "gemma-4-e2b-4bit", name: "Gemma 4 E2B", subtitle: "Hızlı yanıt"),
        ModelOption(id: "gemma-4-e4b-4bit", name: "Gemma 4 E4B", subtitle: "Derin analiz"),
    ]

    var thinkingEffort: ThinkingEffort {
        get { ThinkingEffort(rawValue: thinkingEffortRaw) ?? .off }
        set { thinkingEffortRaw = newValue.rawValue; objectWillChange.send() }
    }

    var activeModelName: String {
        availableModels.first(where: { $0.id == selectedModelId })?.name ?? "SEN.AI"
    }

    private var streamTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    private lazy var urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.httpCookieStorage = .shared
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    // MARK: - Smart Dual-Route Discovery (LAN 1.4s -> GitHub Gist JSON -> Custom URL)

    func bootstrap() async {
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        // 1. Try local Wi-Fi LAN first (blazing instant speed at home)
        let cleanLan = normalizeBase(lanURL)
        if !cleanLan.isEmpty, await probeHealth(cleanLan, timeout: 1.2) {
            activeBaseURL = cleanLan
            connectionRoute = .lan
            await checkAuthAndLoad()
            return
        }

        // 2. Try permanent GitHub Gist JSON Bridge (auto-resolves live Cloudflare HTTPS URL with 1 retry)
        let cleanGist = gistJsonURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanGist.isEmpty, let resolved = await resolveGistURL(cleanGist) {
            for attempt in 0..<2 {
                if await probeHealth(resolved, timeout: 8.0) {
                    activeBaseURL = resolved
                    connectionRoute = .cloudflare
                    await checkAuthAndLoad()
                    return
                }
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(600))
                }
            }
        }

        // 3. Fallback to manual custom URL if configured
        let cleanCustom = normalizeBase(customURL)
        if !cleanCustom.isEmpty, await probeHealth(cleanCustom, timeout: 4.0) {
            activeBaseURL = cleanCustom
            connectionRoute = .custom
            await checkAuthAndLoad()
            return
        }

        connectionRoute = .disconnected
        connectionError = "SEN.AI sunucusuna ulaşılamadı. Ev Wi-Fi veya Ayarlar > GitHub Köprü adresini kontrol edin."
    }

    private func normalizeBase(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func probeHealth(_ base: String, timeout: TimeInterval) async -> Bool {
        guard let url = URL(string: "\(base)/api/auth/status") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        do {
            let (_, resp) = try await urlSession.data(for: req)
            if let http = resp as? HTTPURLResponse, (200...401).contains(http.statusCode) {
                return true
            }
        } catch {}
        return false
    }

    private func resolveGistURL(_ rawUrl: String) async -> String? {
        guard let url = URL(string: rawUrl) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8.0
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, _) = try await urlSession.data(for: req)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["url", "tunnel_url", "active_url", "endpoint"] {
                    if let val = json[key] as? String, val.hasPrefix("http") {
                        return normalizeBase(val)
                    }
                }
            }
        } catch {}
        return nil
    }

    // MARK: - Auth & Sessions

    private func checkAuthAndLoad() async {
        guard let url = URL(string: "\(activeBaseURL)/api/auth/status") else { return }
        do {
            let (data, _) = try await urlSession.data(from: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let unlocked = (obj["unlocked"] as? Bool) ?? true
                let pinEnabled = (obj["pin_enabled"] as? Bool) ?? false
                requiresPin = pinEnabled && !unlocked
                if !requiresPin {
                    await fetchSessions()
                }
            }
        } catch {}
    }

    func verifyPin(_ pin: String) async {
        pinError = nil
        guard let url = URL(string: "\(activeBaseURL)/api/auth/verify") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["pin": pin])
        do {
            let (data, resp) = try await urlSession.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                requiresPin = false
                SenHaptics.success()
                await fetchSessions()
            } else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                pinError = msg ?? "Hatalı PIN."
            }
        } catch {
            pinError = "Bağlantı hatası: \(error.localizedDescription)"
        }
    }

    func fetchSessions() async {
        guard !activeBaseURL.isEmpty, let url = URL(string: "\(activeBaseURL)/api/sessions") else { return }
        do {
            let (data, resp) = try await urlSession.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                requiresPin = true
                return
            }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = obj["sessions"] {
                let raw = try JSONSerialization.data(withJSONObject: arr)
                let decoded = try JSONDecoder().decode([ChatSessionSummary].self, from: raw)
                sessions = decoded
            }
        } catch {}
    }

    func openSession(_ sid: String) async {
        stopGeneration()
        guard !activeBaseURL.isEmpty, let url = URL(string: "\(activeBaseURL)/api/sessions/\(sid)") else { return }
        do {
            let (data, _) = try await urlSession.data(from: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msgs = obj["messages"] as? [[String: Any]] {
                activeSessionId = sid
                messages = msgs.enumerated().map { idx, m in
                    var wsList: [WebSource] = []
                    if let ws = m["web_search"] as? [String: Any],
                       let srcs = ws["sources"],
                       let sData = try? JSONSerialization.data(withJSONObject: srcs),
                       let parsed = try? JSONDecoder().decode([WebSource].self, from: sData) {
                        wsList = parsed
                    }
                    var rcList: [RichCardPayload] = []
                    if let rcs = m["rich_cards"],
                       let rData = try? JSONSerialization.data(withJSONObject: rcs),
                       let parsed = try? JSONDecoder().decode([RichCardPayload].self, from: rData) {
                        rcList = parsed
                    }
                    return ChatMessage(
                        id: (m["id"] as? String) ?? "\(sid)_\(idx)",
                        role: (m["role"] as? String) ?? "assistant",
                        content: (m["content"] as? String) ?? "",
                        thinking: (m["thinking"] as? String) ?? "",
                        autoPersona: m["auto_persona"] as? String,
                        webSources: wsList,
                        richCards: rcList,
                        rating: m["rating"] as? String
                    )
                }
            }
        } catch {}
    }

    func startNewChat() {
        stopGeneration()
        stopSpeaking()
        activeSessionId = "ios_\(UUID().uuidString.prefix(10).lowercased())"
        messages = []
        SenHaptics.light()
    }

    // MARK: - Live SSE Streaming (/api/chat) + Image Upload (/api/upload)

    func uploadImage(_ data: Data, filename: String = "photo.jpg") async -> [String: Any]? {
        guard !activeBaseURL.isEmpty, let url = URL(string: "\(activeBaseURL)/api/upload") else { return nil }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        do {
            let (respData, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: respData) as? [String: Any]
        } catch {
            return nil
        }
    }

    func sendMessage(_ rawText: String, images: [Data] = [], autoSpeak: Bool = false) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !images.isEmpty), !isGenerating else { return }
        guard !activeBaseURL.isEmpty else {
            connectionError = "Önce sunucuya bağlanın."
            return
        }

        let finalPrompt = trimmed.isEmpty ? "Bu görseli incele ve kısaca Türkçe açıkla." : trimmed
        SenHaptics.light()
        let userMsg = ChatMessage(id: UUID().uuidString, role: "user", content: finalPrompt, attachedImages: images)
        let assistantId = UUID().uuidString
        let assistantMsg = ChatMessage(id: assistantId, role: "assistant", content: "", isStreaming: true)
        messages.append(userMsg)
        messages.append(assistantMsg)

        isGenerating = true
        statusLine = images.isEmpty ? "Bağlanıyor..." : "Görsel yükleniyor..."

        streamTask = Task {
            var uploadedAtts: [[String: Any]] = []
            for (idx, imgData) in images.enumerated() {
                if let meta = await uploadImage(imgData, filename: "ios_photo_\(idx + 1).jpg") {
                    uploadedAtts.append([
                        "id": meta["id"] ?? "",
                        "name": meta["name"] ?? "photo.jpg",
                        "kind": "image",
                    ])
                }
            }
            if !images.isEmpty { statusLine = "Görsel analiz ediliyor..." }

            let historyPayload: [[String: Any]] = messages.dropLast().enumerated().map { idx, m in
                let isLatestUser = (idx == messages.count - 2)
                return [
                    "role": m.role,
                    "content": m.content,
                    "thinking": m.thinking,
                    "attachments": isLatestUser ? uploadedAtts : [],
                ]
            }

            let bodyObj: [String: Any] = [
                "session_id": activeSessionId,
                "model_id": selectedModelId,
                "thinking_effort": thinkingEffort.rawValue,
                "web_search": webSearchEnabled,
                "use_library": false,
                "messages": historyPayload,
            ]

            await performSSEStream(bodyObj: bodyObj, assistantId: assistantId, autoSpeak: autoSpeak)
        }
    }

    func stopGeneration() {
        streamTask?.cancel()
        streamTask = nil
        if isGenerating {
            isGenerating = false
            statusLine = ""
            if let idx = messages.indices.last, messages[idx].role == "assistant" {
                messages[idx].isStreaming = false
            }
            Task {
                guard let url = URL(string: "\(activeBaseURL)/api/stop") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                _ = try? await urlSession.data(for: req)
            }
        }
    }

    private func performSSEStream(bodyObj: [String: Any], assistantId: String, autoSpeak: Bool = false) async {
        let startTime = Date()
        defer {
            isGenerating = false
            statusLine = ""
            var finalSpokenText = ""
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].isStreaming = false
                finalSpokenText = messages[idx].content
            }
            Task { await saveCurrentSession() }
            if autoSpeak, !finalSpokenText.isEmpty {
                Task { await toggleSpeak(messageId: assistantId, text: finalSpokenText) }
            }
        }

        guard let url = URL(string: "\(activeBaseURL)/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj)

        do {
            let (bytes, response) = try await urlSession.bytes(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    requiresPin = true
                    return
                }
                if http.statusCode != 200 {
                    updateAssistant(assistantId) { $0.content = "Sunucu hatası (HTTP \(http.statusCode))." }
                    return
                }
            }

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                guard let data = jsonStr.data(using: .utf8),
                      let ev = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = ev["type"] as? String else { continue }

                switch type {
                case "status":
                    if let msg = ev["message"] as? String { statusLine = msg }
                case "thinking_delta", "thinking":
                    if let delta = ev["delta"] as? String {
                        let secs = Date().timeIntervalSince(startTime)
                        updateAssistant(assistantId) {
                            $0.thinking += delta
                            $0.thinkingSeconds = secs
                        }
                    }
                case "answer_delta", "text":
                    if let delta = ev["delta"] as? String {
                        statusLine = ""
                        updateAssistant(assistantId) { $0.content += delta }
                    }
                case "auto_persona":
                    if let name = ev["name"] as? String {
                        updateAssistant(assistantId) { $0.autoPersona = name }
                    }
                case "web_search":
                    if let srcs = ev["sources"],
                       let sData = try? JSONSerialization.data(withJSONObject: srcs),
                       let parsed = try? JSONDecoder().decode([WebSource].self, from: sData) {
                        updateAssistant(assistantId) { $0.webSources = parsed }
                    }
                case "rich_card":
                    if let cardObj = ev["card"],
                       let cData = try? JSONSerialization.data(withJSONObject: cardObj),
                       let parsed = try? JSONDecoder().decode(RichCardPayload.self, from: cData) {
                        updateAssistant(assistantId) { $0.richCards.append(parsed) }
                    }
                case "error":
                    let err = (ev["detail"] as? String) ?? (ev["error"] as? String) ?? "Üretim hatası"
                    updateAssistant(assistantId) { $0.content = "Hata: \(err)" }
                default:
                    break
                }
            }
        } catch is CancellationError {
            // Cancelled cleanly
        } catch {
            updateAssistant(assistantId) {
                if $0.content.isEmpty {
                    $0.content = "Bağlantı kesildi: \(error.localizedDescription)"
                }
            }
        }
    }

    private func updateAssistant(_ id: String, _ mutate: (inout ChatMessage) -> Void) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            mutate(&messages[idx])
        }
    }

    private func saveCurrentSession() async {
        guard !activeBaseURL.isEmpty, !messages.isEmpty,
              let url = URL(string: "\(activeBaseURL)/api/sessions/\(activeSessionId)") else { return }
        let title = messages.first(where: { $0.role == "user" })?.content.prefix(48) ?? "Yeni Sohbet"
        let serialized: [[String: Any]] = messages.map { m in
            var dict: [String: Any] = ["id": m.id, "role": m.role, "content": m.content, "thinking": m.thinking]
            if let ap = m.autoPersona { dict["auto_persona"] = ap }
            if let r = m.rating { dict["rating"] = r }
            return dict
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["title": String(title), "messages": serialized])
        _ = try? await urlSession.data(for: req)
        await fetchSessions()
    }

    // MARK: - Rating (Like / Dislike -> SFT & DPO)

    func rateMessage(_ messageId: String, rating: String) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }), idx > 0 else { return }
        let assistantText = messages[idx].content
        let userText = messages[0..<idx].last(where: { $0.role == "user" })?.content ?? ""
        guard !userText.isEmpty, !assistantText.isEmpty else { return }

        messages[idx].rating = rating
        SenHaptics.light()

        guard let url = URL(string: "\(activeBaseURL)/api/dataset/rate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "user_text": userText,
            "assistant_text": assistantText,
            "rating": rating,
            "model_id": selectedModelId,
        ])
        _ = try? await urlSession.data(for: req)
    }

    // MARK: - Turkish Neural TTS (/api/tts)

    func toggleSpeak(messageId: String, text: String) async {
        if speakingMessageId == messageId {
            stopSpeaking()
            return
        }
        stopSpeaking()
        guard !activeBaseURL.isEmpty, let url = URL(string: "\(activeBaseURL)/api/tts") else { return }
        speakingMessageId = messageId

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "voice": ttsVoice])
        do {
            let (data, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                speakingMessageId = nil
                return
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            audioPlayer = player
            player.play()
        } catch {
            speakingMessageId = nil
        }
    }

    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        speakingMessageId = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.speakingMessageId = nil
        }
    }

    // MARK: - Simulator Preview State (Used ONLY when launched with --preview-screen)

    func applyPreviewState(screen: String) {
        activeBaseURL = "https://preview.sen.ai"
        connectionRoute = .cloudflare
        connectionError = nil
        requiresPin = false
        sessions = [
            ChatSessionSummary(id: "p1", title: "Manisa hava durumu ve hafta sonu planı", updated_at: "Bugün"),
            ChatSessionSummary(id: "p2", title: "Oğlak ve Akrep uyumu", updated_at: "Bugün"),
            ChatSessionSummary(id: "p3", title: "SwiftUI Liquid Glass mimarisi", updated_at: "Dün"),
            ChatSessionSummary(id: "p4", title: "Envanter Excel tablosu", updated_at: "Dün"),
        ]
        activeSessionId = "p2"
        if screen == "models" {
            thinkingEffort = .high
        }

        if screen == "chat" || screen == "sources" {
            let sampleWeather = RichCardPayload(
                kind: "weather",
                title: nil,
                location: "Manisa, Türkiye",
                updated_at: "Canlı · 02:45",
                temp_c: 12.4,
                feels_like_c: 11.2,
                humidity: 73,
                wind_kmh: 3.1,
                precip_mm: 0,
                condition: "Parçalı Bulutlu",
                daily: [
                    WeatherDay(day: "Bugün", date: nil, condition: "Parçalı Bulutlu", t_max: 19, t_min: 10, rain_prob: 0),
                    WeatherDay(day: "Yarın", date: nil, condition: "Açık", t_max: 22, t_min: 8, rain_prob: 5),
                    WeatherDay(day: "Sal", date: nil, condition: "Yağmur", t_max: 17, t_min: 7, rain_prob: 40),
                    WeatherDay(day: "Çar", date: nil, condition: "Güneşli", t_max: 14, t_min: 4, rain_prob: 0),
                    WeatherDay(day: "Per", date: nil, condition: "Bulutlu", t_max: 15, t_min: 5, rain_prob: 10),
                ],
                items: nil
            )
            let compatMd = """
            İki burç arasında hem duygusal derinlik hem de güçlü bir güven bağı oluşur.

            ```sen_card
            {"kind":"compatibility","title":"Oğlak ♑ × Akrep ♏","score":88,"badge":"Güçlü Bağ","summary":"Sağlam adımlar ile yüksek sadakatin birleşimi uzun soluklu bir denge kurar.","metrics":[{"label":"💖 Aşk","value":89},{"label":"🛡️ Güven","value":94},{"label":"💬 İletişim","value":82}]}
            ```

            **⚡ Güçlü Yönler:** Birbirlerinin hedeflerini sessizce ama kararlılıkla desteklerler. ✨
            """
            messages = [
                ChatMessage(id: "u1", role: "user", content: "Manisa hava durumu nasıl ve Oğlak Akrep uyumu?"),
                ChatMessage(
                    id: "a1",
                    role: "assistant",
                    content: compatMd,
                    thinking: "Kullanıcı hem Manisa canlı hava durumunu hem de Oğlak–Akrep uyumunu sordu. Önce hava kartını, ardından net uyum kartını ve kısa özeti sunuyorum.",
                    webSources: [
                        WebSource(title: "Manisa Canlı Hava Durumu — 12.4°C", url: "https://open-meteo.com", domain: "open-meteo.com", snippet: nil),
                        WebSource(title: "Meteoroloji Genel Müdürlüğü", url: "https://mgm.gov.tr", domain: "mgm.gov.tr", snippet: nil),
                    ],
                    richCards: [sampleWeather],
                    rating: "like",
                    thinkingSeconds: 1.4
                ),
            ]
        } else if screen == "chat_more" {
            let richMd = """
            Hafta sonu için hem harika bir bilim kurgu önerisi hem de verimli bir gün planı hazırladım:

            ```sen_card
            {"kind":"rating","title":"Interstellar (Yıldızlararası)","emoji":"🎬","score":"8.9/10","tags":["Bilim Kurgu","Epik","Duygusal"],"points":["Hans Zimmer'in unutulmaz müzikleri","Gerçek astrofizik temelli kara delik sahneleri","Güçlü baba-kız hikayesi"],"summary":"Görsel şölen ve duygusal derinliği bir arada arıyorsan ilk sıraya koyabilirsin."}
            ```

            ```sen_card
            {"kind":"checklist","title":"Verimli Hafta Sonu Planı","badge":"4 Adım","steps":[{"label":"Sabah kahvesi ve 20 dk yürüyüş","meta":"09:30"},{"label":"Odaklı çalışma veya proje bloğu","meta":"11:00"},{"label":"Kısa mola ve öğle yemeği","meta":"13:30"},{"label":"Akşam film keyfi: Interstellar","meta":"21:00"}]}
            ```
            """
            messages = [
                ChatMessage(id: "u2", role: "user", content: "Film önerisi ve hafta sonu planı yapar mısın?"),
                ChatMessage(
                    id: "a2",
                    role: "assistant",
                    content: richMd,
                    webSources: [
                        WebSource(title: "Interstellar — IMDb (8.7)", url: "https://imdb.com", domain: "imdb.com", snippet: nil),
                        WebSource(title: "Bilim Kurgu En İyiler", url: "https://rottentomatoes.com", domain: "rottentomatoes.com", snippet: nil),
                    ],
                    rating: "like"
                ),
            ]
        } else if screen == "code_table" {
            let codeTableMd = """
            İşte hem temiz bir **Python stok hesaplayıcı** hem de karşılaştırmalı **envanter tablosu**:

            ```python
            def stok_degeri(urunler):
                toplam = sum(u["adet"] * u["fiyat"] for u in urunler)
                return f"{toplam:,.2f} TL"
            ```

            | Ürün Kodu | Ürün Adı | Stok | Birim Fiyat | Toplam |
            | --- | --- | --- | --- | --- |
            | ELK-01 | Mavi Tişört | 150 | 240 TL | 36.000 TL |
            | ELK-02 | Keten Gömlek | 85 | 490 TL | 41.650 TL |
            | ELK-03 | Spor Şapka | 210 | 180 TL | 37.800 TL |

            Tek dokunuşla kodu veya tabloyu kopyalayabilirsin. ✨
            """
            messages = [
                ChatMessage(id: "u3", role: "user", content: "Python stok hesaplama kodu ve örnek envanter tablosu yazar mısın?"),
                ChatMessage(
                    id: "a3",
                    role: "assistant",
                    content: codeTableMd,
                    autoPersona: "Veri & Excel Analisti",
                    rating: "like"
                ),
            ]
        } else {
            messages = []
        }
    }
}
