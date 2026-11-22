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
    @AppStorage("senai_web_search") var webSearchEnabled: Bool = false
    @AppStorage("senai_use_library") var useLibraryEnabled: Bool = false
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
    @Published var isSearchingWeb: Bool = false
    @Published var searchingSitesCount: Int = 0
    @Published var searchingDomain: String = ""
    @Published var isTemporaryChat: Bool = false
    @Published var temporaryPersonalized: Bool = true
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

    func imageResolveURL(for query: String?) -> URL? {
        guard let q = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !q.isEmpty, !activeBaseURL.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(activeBaseURL)/api/image-resolve?q=\(encoded)")
    }

    private var streamTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    private lazy var urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.httpCookieStorage = .shared
        cfg.httpAdditionalHeaders = ["X-SENAI-Client": "ios-native"]
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
        guard let url = URL(string: "\(base)/api/auth/state") else { return false }
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
        // Native iOS IPA bypasses PIN via X-SENAI-Client: ios-native header
        requiresPin = false
        await fetchSessions()
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

    func faviconURL(for domain: String) -> URL? {
        let clean = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, activeBaseURL != "https://preview.sen.ai",
              let enc = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(enc)&sz=64")
    }

    func startNewChat() {
        stopGeneration()
        stopSpeaking()
        isTemporaryChat = false
        activeSessionId = "ios_\(UUID().uuidString.prefix(10).lowercased())"
        messages = []
        SenHaptics.light()
    }

    func startTemporaryChat() {
        stopGeneration()
        stopSpeaking()
        isTemporaryChat = true
        activeSessionId = "tmp_\(UUID().uuidString.prefix(10).lowercased())"
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

    func sendMessage(_ rawText: String, images: [Data] = [], autoSpeak: Bool = false, userCity: String? = nil) {
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
        isSearchingWeb = false
        searchingSitesCount = 0
        searchingDomain = ""
        statusLine = images.isEmpty ? "" : "Görsel yükleniyor..."

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
            if !images.isEmpty { statusLine = "" }

            let historyPayload: [[String: Any]] = messages.dropLast().enumerated().map { idx, m in
                let isLatestUser = (idx == messages.count - 2)
                return [
                    "role": m.role,
                    "content": m.content,
                    "thinking": m.thinking,
                    "attachments": isLatestUser ? uploadedAtts : [],
                ]
            }

            var bodyObj: [String: Any] = [
                "session_id": activeSessionId,
                "model_id": selectedModelId,
                "thinking_effort": thinkingEffort.rawValue,
                "web_search": webSearchEnabled,
                "use_library": useLibraryEnabled,
                "ignore_memory": isTemporaryChat && !temporaryPersonalized,
                "messages": historyPayload,
            ]
            if let city = userCity, !city.isEmpty {
                bodyObj["user_city"] = city
            }

            await performSSEStream(bodyObj: bodyObj, assistantId: assistantId, autoSpeak: autoSpeak)
        }
    }

    func regenerateLast() {
        guard !isGenerating else { return }
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == "user" }) else { return }
        let lastUser = messages[lastUserIdx]
        messages = Array(messages.prefix(lastUserIdx))
        sendMessage(lastUser.content, images: lastUser.attachedImages)
    }

    func stopGeneration() {
        streamTask?.cancel()
        streamTask = nil
        if isGenerating {
            isGenerating = false
            isSearchingWeb = false
            searchingSitesCount = 0
            searchingDomain = ""
            statusLine = ""
            if let idx = messages.indices.last, messages[idx].role == "assistant" {
                messages[idx].isStreaming = false
            }
            Task {
                guard let url = URL(string: "\(activeBaseURL)/api/chat/stop") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                _ = try? await urlSession.data(for: req)
            }
        }
    }

    private func performSSEStream(bodyObj: [String: Any], assistantId: String, autoSpeak: Bool = false) async {
        let startTime = Date()
        var pendingAnswer = ""
        var pendingThinking = ""
        var lastFlush = Date()

        func flushBuffers(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastFlush) >= 0.05 else { return }
            if !pendingThinking.isEmpty || !pendingAnswer.isEmpty {
                let tAdd = pendingThinking
                let aAdd = pendingAnswer
                pendingThinking = ""
                pendingAnswer = ""
                lastFlush = now
                let secs = now.timeIntervalSince(startTime)
                updateAssistant(assistantId) {
                    if !tAdd.isEmpty {
                        $0.thinking += tAdd
                        $0.thinkingSeconds = secs
                    }
                    if !aAdd.isEmpty {
                        $0.content += aAdd
                    }
                }
            }
        }

        defer {
            flushBuffers(force: true)
            isGenerating = false
            isSearchingWeb = false
            searchingSitesCount = 0
            searchingDomain = ""
            statusLine = ""
            var finalSpokenText = ""
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].isStreaming = false
                finalSpokenText = messages[idx].content
            }
            if !isTemporaryChat {
                Task { await saveCurrentSession() }
            }
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
                    let stage = (ev["stage"] as? String) ?? ""
                    if stage == "web_search" {
                        isSearchingWeb = true
                        let cnt = (ev["sites_count"] as? Int) ?? max(1, searchingSitesCount)
                        let dom = (ev["domain"] as? String) ?? ""
                        withAnimation(.snappy(duration: 0.22)) {
                            searchingSitesCount = max(searchingSitesCount, cnt)
                            if !dom.isEmpty { searchingDomain = dom }
                        }
                    } else if stage == "generating" || stage == "model_loading" {
                        isSearchingWeb = false
                    }
                case "thinking_delta", "thinking":
                    if let delta = ev["delta"] as? String {
                        isSearchingWeb = false
                        pendingThinking += delta
                        flushBuffers()
                    }
                case "answer_delta", "text":
                    if let delta = ev["delta"] as? String {
                        isSearchingWeb = false
                        statusLine = ""
                        pendingAnswer += delta
                        flushBuffers()
                    }
                case "auto_persona":
                    flushBuffers(force: true)
                    if let name = ev["name"] as? String {
                        updateAssistant(assistantId) { $0.autoPersona = name }
                    }
                case "web_search":
                    flushBuffers(force: true)
                    if let srcs = ev["sources"],
                       let sData = try? JSONSerialization.data(withJSONObject: srcs),
                       let parsed = try? JSONDecoder().decode([WebSource].self, from: sData) {
                        if !parsed.isEmpty {
                            withAnimation(.snappy(duration: 0.22)) {
                                searchingSitesCount = parsed.count
                            }
                        }
                        updateAssistant(assistantId) { $0.webSources = parsed }
                    }
                case "rich_card":
                    flushBuffers(force: true)
                    if let cardObj = ev["card"],
                       let cData = try? JSONSerialization.data(withJSONObject: cardObj),
                       let parsed = try? JSONDecoder().decode(RichCardPayload.self, from: cData) {
                        updateAssistant(assistantId) { $0.richCards.append(parsed) }
                    }
                case "error":
                    flushBuffers(force: true)
                    let err = (ev["detail"] as? String) ?? (ev["error"] as? String) ?? "Üretim hatası"
                    updateAssistant(assistantId) { $0.content = "Hata: \(err)" }
                default:
                    break
                }
            }
        } catch is CancellationError {
            // Cancelled cleanly
        } catch {
            flushBuffers(force: true)
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

    var currentSessionTitle: String {
        if let existing = sessions.first(where: { $0.id == activeSessionId }), !existing.title.isEmpty {
            return existing.title
        }
        return String(messages.first(where: { $0.role == "user" })?.content.prefix(48) ?? "Yeni Sohbet")
    }

    var isCurrentSessionPinned: Bool {
        sessions.first(where: { $0.id == activeSessionId })?.pinned == true
    }

    var currentTranscriptForShare: String {
        messages.map { m in
            let who = m.role == "user" ? "Sen" : "SEN.AI"
            return "\(who):\n\(m.content)"
        }.joined(separator: "\n\n---\n\n")
    }

    private func saveCurrentSession(customTitle: String? = nil, customPinned: Bool? = nil) async {
        guard !activeBaseURL.isEmpty, !messages.isEmpty,
              let url = URL(string: "\(activeBaseURL)/api/sessions") else { return }
        let existing = sessions.first(where: { $0.id == activeSessionId })
        let title = customTitle ?? existing?.title ?? String(messages.first(where: { $0.role == "user" })?.content.prefix(48) ?? "Yeni Sohbet")
        let pinned = customPinned ?? existing?.pinned ?? false

        let serialized: [[String: Any]] = messages.map { m in
            var dict: [String: Any] = ["id": m.id, "role": m.role, "content": m.content, "thinking": m.thinking]
            if let ap = m.autoPersona { dict["auto_persona"] = ap }
            if let r = m.rating { dict["rating"] = r }
            return dict
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": activeSessionId,
            "title": title,
            "pinned": pinned,
            "messages": serialized,
        ])
        _ = try? await urlSession.data(for: req)
        await fetchSessions()
    }

    func togglePinSession(_ sid: String) async {
        guard !activeBaseURL.isEmpty else { return }
        let nextPinned = !(sessions.first(where: { $0.id == sid })?.pinned ?? false)
        if let idx = sessions.firstIndex(where: { $0.id == sid }) {
            sessions[idx].pinned = nextPinned
        }
        SenHaptics.light()
        if sid == activeSessionId && !messages.isEmpty {
            await saveCurrentSession(customPinned: nextPinned)
            return
        }
        await patchSessionMeta(sid: sid, newTitle: nil, newPinned: nextPinned)
    }

    func renameSession(_ sid: String, newTitle: String) async {
        let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !activeBaseURL.isEmpty else { return }
        if let idx = sessions.firstIndex(where: { $0.id == sid }) {
            sessions[idx].title = clean
        }
        SenHaptics.light()
        if sid == activeSessionId && !messages.isEmpty {
            await saveCurrentSession(customTitle: clean)
            return
        }
        await patchSessionMeta(sid: sid, newTitle: clean, newPinned: nil)
    }

    private func patchSessionMeta(sid: String, newTitle: String?, newPinned: Bool?) async {
        guard let getUrl = URL(string: "\(activeBaseURL)/api/sessions/\(sid)"),
              let postUrl = URL(string: "\(activeBaseURL)/api/sessions") else { return }
        do {
            let (data, _) = try await urlSession.data(from: getUrl)
            guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let t = newTitle { obj["title"] = t }
            if let p = newPinned { obj["pinned"] = p }
            var req = URLRequest(url: postUrl)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: obj)
            _ = try? await urlSession.data(for: req)
            await fetchSessions()
        } catch {}
    }

    func deleteSession(_ sid: String) async {
        guard !activeBaseURL.isEmpty,
              let url = URL(string: "\(activeBaseURL)/api/sessions/\(sid)") else { return }
        sessions.removeAll { $0.id == sid }
        if activeSessionId == sid {
            startNewChat()
        }
        SenHaptics.medium()
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
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
        isGenerating = false
        isSearchingWeb = false
        searchingSitesCount = 0
        sessions = [
            ChatSessionSummary(id: "p1", title: "Hafta sonu verimli rutin planı", updated_at: "Bugün", pinned: true),
            ChatSessionSummary(id: "p2", title: "Akrep ve Oğlak uyumu", updated_at: "Bugün", pinned: true),
            ChatSessionSummary(id: "p3", title: "Oyuncu koltuğu karşılaştırması", updated_at: "Dün", pinned: false),
            ChatSessionSummary(id: "p4", title: "Psikolojik gerilim film listesi", updated_at: "Dün", pinned: false),
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
                updated_at: "Canlı · 16:40",
                temp_c: 18.4,
                feels_like_c: 17.6,
                humidity: 58,
                wind_kmh: 9.2,
                precip_mm: 0,
                condition: "Parçalı Bulutlu",
                daily: [
                    WeatherDay(day: "Bugün", date: nil, condition: "Parçalı Bulutlu", t_max: 21, t_min: 11, rain_prob: 5),
                    WeatherDay(day: "Yarın", date: nil, condition: "Güneşli", t_max: 23, t_min: 10, rain_prob: 0),
                    WeatherDay(day: "Sal", date: nil, condition: "Yağmur", t_max: 17, t_min: 9, rain_prob: 45),
                    WeatherDay(day: "Çar", date: nil, condition: "Açık", t_max: 19, t_min: 8, rain_prob: 0),
                    WeatherDay(day: "Per", date: nil, condition: "Bulutlu", t_max: 18, t_min: 8, rain_prob: 15),
                ],
                items: nil
            )
            let compatMd = """
            Hava bugün Manisa'da oldukça keyifli, hafif bir ceket yeterli olur. ☀️

            ```sen_card
            {"kind":"scorecard","title":"AKREP ♏ × OĞLAK ♑","badge":"Yüksek uyum","score":"9,5/10","subtitle":"Genel uyum puanı","note":"Astrolojik, eğlence amaçlı değerlendirme","metrics":[{"emoji":"❤️","label":"Aşk","value":"9,5/10"},{"emoji":"🔥","label":"Tutku","value":"10/10"},{"emoji":"🛡️","label":"Güven ve sadakat","value":"9,5/10"},{"emoji":"💬","label":"İletişim","value":"8,5/10"}],"strengths":["Karşılıklı sadakat ve yüksek güven","Birlikte uzun vadeli hedeflere yürüme"],"challenges":["İki tarafın da inatçı olabilmesi"],"summary":"Birbirlerine alan tanıdıklarında çok sağlam ve kalıcı bir bağ kurarlar."}
            ```
            """
            messages = [
                ChatMessage(id: "u1", role: "user", content: "Hava durumu nasıl ve Akrep Oğlak uyumu?"),
                ChatMessage(
                    id: "a1",
                    role: "assistant",
                    content: compatMd,
                    thinking: "internal thought hidden",
                    webSources: [
                        WebSource(title: "Manisa Canlı Hava Durumu — 18.4°C", url: "https://open-meteo.com", domain: "open-meteo.com", snippet: nil),
                        WebSource(title: "Meteoroloji Genel Müdürlüğü", url: "https://mgm.gov.tr", domain: "mgm.gov.tr", snippet: nil),
                        WebSource(title: "Hava Tahmin Raporu", url: "https://accuweather.com", domain: "accuweather.com", snippet: nil),
                    ],
                    richCards: [sampleWeather],
                    rating: "like",
                    thinkingSeconds: 2.3
                ),
            ]
        } else if screen == "media_list" {
            let moviesMd = """
            ### 🎬 Seçtiğim Yerli & Psikolojik Gerilim Filmleri
            Gizem, psikolojik derinlik ve ters köşe seviyorsan tam senlik 3 film seçtim:

            ```sen_card
            {"kind":"media_list","title":"Sana önereceğim filmler","items":[{"title":"Shutter Island","year":"2010","subtitle":"Gizem, psikoloji ve akıl oyunları. Sonuna kadar merak ettirir.","badge":"İlk önerim","score":"8.2","image_query":"Shutter Island movie poster"},{"title":"Se7en","year":"1995","subtitle":"Karanlık suç hikâyesi, psikolojik gerilim ve unutulmaz final.","score":"8.6","image_query":"Se7en movie poster"},{"title":"Gone Girl","year":"2014","subtitle":"Manipülasyon, sırlar ve sürekli değişen şüpheler.","score":"8.1","image_query":"Gone Girl movie poster"}]}
            ```

            ***
            * **Benim ilk tercihim Shutter Island:** İzlemediysen konusunu hiç araştırmadan aç.
            * **Polisiye alternatifi:** Yerli istersen *Av Mevsimi* ve *Eşkıya* da harika seçimlerdir. 🍿
            """
            messages = [
                ChatMessage(id: "um1", role: "user", content: "Psikolojik gerilim ve ters köşe film önerir misin?"),
                ChatMessage(id: "am1", role: "assistant", content: moviesMd, thinking: "ok", rating: "like", thinkingSeconds: 1.8),
            ]
        } else if screen == "image_compare" {
            let cmpMd = """
            Hem oyun hem yazı için mekanik klavye boyut farkı **masa alanı ve numerik tuş ihtiyacında** ortaya çıkıyor:

            ```sen_card
            {"kind":"image_compare","title":"Klavye Boyut Karşılaştırması","left":{"name":"Tam Boyut (Full Size)","emoji":"⌨️","subtitle":"%100 · Numerik tuş takımlı","image_query":"full size mechanical keyboard","points":["Numerik tuşlar mevcut","Excel ve veri girişi için ideal","Masada daha fazla yer kaplar"]},"right":{"name":"TKL (Tenkeyless)","emoji":"🚀","subtitle":"%80 · Kompakt ve ergonomik","image_query":"TKL tenkeyless mechanical keyboard","points":["Fare hareketi için geniş alan","Kolay taşınır ve minimalist","Oyun ve kodlama için favori"]},"verdict":"Oyun ve günlük kodlama için TKL (%80) çok daha ergonomik bir seçimdir."}
            ```
            """
            messages = [
                ChatMessage(id: "uc1", role: "user", content: "Bana mekanik klavye önerisi ve boyut farkını gösterir misin?"),
                ChatMessage(
                    id: "ac1",
                    role: "assistant",
                    content: cmpMd,
                    webSources: [
                        WebSource(title: "Mekanik Klavye Rehberi", url: "https://itopya.com", domain: "itopya.com", snippet: nil),
                        WebSource(title: "Keychron & Akko Modelleri", url: "https://trendyol.com", domain: "trendyol.com", snippet: nil),
                    ],
                    rating: "like"
                ),
            ]
        } else if screen == "chat_more" {
            let richMd = """
            Hem odaklanabileceğin hem de dinlenmeye vakit ayırabileceğin dengeli bir gün planı hazırladım:

            ```sen_card
            {"kind":"checklist","title":"Verimli Günlük Plan","badge":"5 Adım","steps":[{"label":"Sabah kahvesi ve 20 dk yürüyüş","meta":"09:00"},{"label":"Derin odak çalışma bloğu","meta":"10:30"},{"label":"Öğle molası ve ekran arası","meta":"13:00"},{"label":"Spor veya esneme rutini","meta":"17:30"},{"label":"Akşam film keyfi & kitap","meta":"21:00"}]}
            ```

            | Özellik | Seviye |
            | --- | --- |
            | Odak süresi | 3,5 saat |
            | Dinlenme dengesi | 9/10 |
            | Sürdürülebilirlik | 10/10 |
            """
            messages = [
                ChatMessage(id: "u2", role: "user", content: "Günlük verimli bir rutin planı yapar mısın?"),
                ChatMessage(id: "a2", role: "assistant", content: richMd, rating: "like"),
            ]
        } else if screen == "code_table" {
            let codeTableMd = """
            İşte hem renklendirilmiş **Python stok hesaplayıcı** hem de minimalist **envanter tablosu**:

            ```python
            def stok_degeri(urunler):
                # Toplam envanter değerini hesaplar
                toplam = sum(u["adet"] * u["fiyat"] for u in urunler)
                return f"{toplam:,.2f} TL"
            ```

            | Ürün Kodu | Ürün Adı | Stok | Toplam |
            | --- | --- | --- | --- |
            | ELK-01 | Mavi Tişört | 150 | 36.000 TL |
            | ELK-02 | Keten Gömlek | 85 | 41.650 TL |
            | ELK-03 | Spor Şapka | 210 | 37.800 TL |
            """
            messages = [
                ChatMessage(id: "u3", role: "user", content: "Python stok hesaplama kodu ve örnek envanter tablosu yazar mısın?"),
                ChatMessage(id: "a3", role: "assistant", content: codeTableMd, autoPersona: "Veri & Excel Analisti", rating: "like"),
            ]
        } else if screen == "spotlight_table" {
            let spotlightMd = """
            Gassal dizisindeki imamın görev yaptığı cami **İstanbul Beykoz'daki Kılıçlı Köyü Camii**'dir.

            ```sen_card
            {"kind":"image_spotlight","title":"Kılıçlı Köyü Camii","subtitle":"Beykoz, İstanbul · Gassal Dizisi Çekim Mekanı","location_label":"Beykoz, İstanbul","image_query":"Kılıçlı Köyü Camii Beykoz İstanbul"}
            ```

            | Özellik | Değerlendirme | Durum |
            | --- | --- | --- |
            | **Konum Doğruluğu** | Beykoz Kılıçlı Köyü | Çok iyi |
            | **Kaynak Güveni** | 5 bağımsız haber sitesi | En iyi |
            | **Çekim Atmosferi** | Doğal köy dokusu | Başarılı |
            """
            messages = [
                ChatMessage(id: "usp1", role: "user", content: "Gassal dizisindeki imamın camisi gerçekte nerede?"),
                ChatMessage(
                    id: "asp1",
                    role: "assistant",
                    content: spotlightMd,
                    thinking: "internal",
                    webSources: [
                        WebSource(title: "Gassal Dizisi Nerede Çekildi? Kılıçlı Köyü Camii", url: "https://referansturk.com.tr", domain: "referansturk.com.tr", snippet: "Gassal dizisinin cami sahneleri Beykoz Kılıçlı Köyü'nde çekildi."),
                        WebSource(title: "Gassal Çekim Mekanları", url: "https://milligazete.com.tr", domain: "milligazete.com.tr", snippet: "İstanbul Beykoz ilçesine bağlı Kılıçlı Mahallesi."),
                        WebSource(title: "Televizyon Gazetesi — Gassal", url: "https://televizyongazetesi.com", domain: "televizyongazetesi.com", snippet: "TRT Tabii yapımı Gassal dizisi mekanları."),
                    ],
                    rating: "like",
                    thinkingSeconds: 1.9
                ),
            ]
        } else if screen == "choice_card" {
            let choiceMd = """
            Sana tam nokta atışı bir öneri yapabilmem için aşağıdan seçim yapabilirsin:

            ```sen_card
            {"kind":"choice_card","title":"Tercihlerini seç","subtitle":"Hızlı 2 adımlı seçim","questions":[{"question":"Hangi kategori?","options":["Film & Dizi","Klavye & Ekipman","Günlük Plan"]},{"question":"Önceliğin nedir?","options":["Fiyat / Performans","En Yüksek Kalite","Hızlı Çözüm"]}]}
            ```
            """
            messages = [
                ChatMessage(id: "uch1", role: "user", content: "Bana harika bir öneri yapar mısın?"),
                ChatMessage(id: "ach1", role: "assistant", content: choiceMd, rating: "like"),
            ]
        } else if screen == "searching" {
            isGenerating = true
            isSearchingWeb = true
            searchingSitesCount = 3
            searchingDomain = "referansturk.com.tr"
            messages = [
                ChatMessage(id: "us1", role: "user", content: "Gassal dizisindeki imamın camisi gerçekte nerede?"),
                ChatMessage(id: "as1", role: "assistant", content: "", isStreaming: true),
            ]
        } else {
            messages = []
        }
    }
}
