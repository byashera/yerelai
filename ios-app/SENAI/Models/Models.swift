import Foundation

enum ThinkingEffort: String, CaseIterable, Identifiable {
    case off = "off"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Kapalı"
        case .low: return "Düşük"
        case .medium: return "Orta"
        case .high: return "Yüksek"
        }
    }

    var icon: String {
        switch self {
        case .off: return "bolt.fill"
        case .low: return "safari"
        case .medium: return "diamond"
        case .high: return "sparkles"
        }
    }
}

struct ModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
}

struct WebSource: Identifiable, Codable, Hashable {
    var id: String { url }
    let title: String
    let url: String
    let domain: String
    let snippet: String?
}

struct WeatherDay: Identifiable, Codable, Hashable {
    var id: String { date ?? day ?? UUID().uuidString }
    let day: String?
    let date: String?
    let condition: String?
    let t_max: Double?
    let t_min: Double?
    let rain_prob: Int?
}

struct FinanceItem: Identifiable, Codable, Hashable {
    var id: String { code }
    let code: String
    let name: String?
    let rate: Double
    let symbol: String?
}

struct RichCardPayload: Identifiable, Codable, Hashable {
    var id: String { "\(kind)_\(location ?? title ?? "")" }
    let kind: String
    let title: String?
    let location: String?
    let updated_at: String?
    let temp_c: Double?
    let feels_like_c: Double?
    let humidity: Int?
    let wind_kmh: Double?
    let precip_mm: Double?
    let condition: String?
    let daily: [WeatherDay]?
    let items: [FinanceItem]?
}

// MARK: - Inline sen_card / yerel_card Models

struct SenMetric: Identifiable, Codable, Hashable {
    var id: String { label }
    let label: String
    let value: Int
}

struct SenCompareSide: Codable, Hashable {
    let name: String
    let emoji: String?
    let score: Int?
    let points: [String]?
}

struct SenChecklistStep: Identifiable, Codable, Hashable {
    var id: String { label }
    let label: String
    let meta: String?
}

struct SenVisualCard: Identifiable, Codable, Hashable {
    var id: String { "\(kind)_\(title ?? "")" }
    let kind: String
    let title: String?
    let badge: String?
    let summary: String?
    let score: Int?
    let scoreText: String?
    let emoji: String?
    let metrics: [SenMetric]?
    let left: SenCompareSide?
    let right: SenCompareSide?
    let verdict: String?
    let tags: [String]?
    let points: [String]?
    let steps: [SenChecklistStep]?

    enum CodingKeys: String, CodingKey {
        case kind, title, badge, summary, score, emoji, metrics, left, right, verdict, tags, points, steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        badge = try c.decodeIfPresent(String.self, forKey: .badge)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        metrics = try c.decodeIfPresent([SenMetric].self, forKey: .metrics)
        left = try c.decodeIfPresent(SenCompareSide.self, forKey: .left)
        right = try c.decodeIfPresent(SenCompareSide.self, forKey: .right)
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        points = try c.decodeIfPresent([String].self, forKey: .points)
        steps = try c.decodeIfPresent([SenChecklistStep].self, forKey: .steps)

        if let intScore = try? c.decodeIfPresent(Int.self, forKey: .score) {
            score = intScore
            scoreText = "\(intScore)"
        } else if let strScore = try? c.decodeIfPresent(String.self, forKey: .score) {
            score = Int(strScore.filter { $0.isNumber })
            scoreText = strScore
        } else {
            score = nil
            scoreText = nil
        }
    }
}

struct PendingPhoto: Identifiable, Hashable {
    let id = UUID()
    let data: Data
}

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let role: String // "user" | "assistant"
    var content: String
    var thinking: String = ""
    var autoPersona: String? = nil
    var webSources: [WebSource] = []
    var richCards: [RichCardPayload] = []
    var attachedImages: [Data] = []
    var rating: String? = nil // "like" | "dislike"
    var isStreaming: Bool = false
    var thinkingSeconds: Double = 0
}

struct ChatSessionSummary: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let updated_at: String?
}

enum ConnectionRoute: String {
    case disconnected = "Bağlı değil"
    case lan = "Ev Wi-Fi (LAN)"
    case cloudflare = "Sabit Köprü (Cloudflare)"
    case custom = "Özel Sunucu"
}
