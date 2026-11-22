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

    enum CodingKeys: String, CodingKey {
        case day, day_label, date, condition, t_max, max_c, t_min, min_c, rain_prob, precip_prob
    }

    init(day: String?, date: String?, condition: String?, t_max: Double?, t_min: Double?, rain_prob: Int?) {
        self.day = day
        self.date = date
        self.condition = condition
        self.t_max = t_max
        self.t_min = t_min
        self.rain_prob = rain_prob
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? (try? c.decodeIfPresent(String.self, forKey: .day_label))
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        condition = try? c.decodeIfPresent(String.self, forKey: .condition)
        t_max = (try? c.decodeIfPresent(Double.self, forKey: .t_max)) ?? (try? c.decodeIfPresent(Double.self, forKey: .max_c))
        t_min = (try? c.decodeIfPresent(Double.self, forKey: .t_min)) ?? (try? c.decodeIfPresent(Double.self, forKey: .min_c))
        rain_prob = (try? c.decodeIfPresent(Int.self, forKey: .rain_prob)) ?? (try? c.decodeIfPresent(Int.self, forKey: .precip_prob))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(day, forKey: .day)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(condition, forKey: .condition)
        try c.encodeIfPresent(t_max, forKey: .t_max)
        try c.encodeIfPresent(t_min, forKey: .t_min)
        try c.encodeIfPresent(rain_prob, forKey: .rain_prob)
    }
}

struct WeatherCurrentNested: Codable, Hashable {
    let temp_c: Double?
    let apparent_c: Double?
    let feels_like_c: Double?
    let humidity: Int?
    let wind_kmh: Double?
    let precipitation_mm: Double?
    let precip_mm: Double?
    let condition: String?
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

    enum CodingKeys: String, CodingKey {
        case kind, title, location, city, country, updated_at
        case temp_c, feels_like_c, apparent_c, humidity, wind_kmh, precip_mm, precipitation_mm, condition
        case current, daily, items
    }

    init(
        kind: String,
        title: String? = nil,
        location: String? = nil,
        updated_at: String? = nil,
        temp_c: Double? = nil,
        feels_like_c: Double? = nil,
        humidity: Int? = nil,
        wind_kmh: Double? = nil,
        precip_mm: Double? = nil,
        condition: String? = nil,
        daily: [WeatherDay]? = nil,
        items: [FinanceItem]? = nil
    ) {
        self.kind = kind
        self.title = title
        self.location = location
        self.updated_at = updated_at
        self.temp_c = temp_c
        self.feels_like_c = feels_like_c
        self.humidity = humidity
        self.wind_kmh = wind_kmh
        self.precip_mm = precip_mm
        self.condition = condition
        self.daily = daily
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        title = try? c.decodeIfPresent(String.self, forKey: .title)

        let rawLoc = try? c.decodeIfPresent(String.self, forKey: .location)
        let rawCity = try? c.decodeIfPresent(String.self, forKey: .city)
        let rawCountry = try? c.decodeIfPresent(String.self, forKey: .country)
        if let rawLoc, !rawLoc.isEmpty {
            location = rawLoc
        } else if let rawCity, !rawCity.isEmpty {
            if let rawCountry, !rawCountry.isEmpty {
                location = "\(rawCity), \(rawCountry)"
            } else {
                location = rawCity
            }
        } else {
            location = nil
        }

        updated_at = try? c.decodeIfPresent(String.self, forKey: .updated_at)
        let nested = try? c.decodeIfPresent(WeatherCurrentNested.self, forKey: .current)

        temp_c = (try? c.decodeIfPresent(Double.self, forKey: .temp_c)) ?? nested?.temp_c
        feels_like_c = (try? c.decodeIfPresent(Double.self, forKey: .feels_like_c))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .apparent_c))
            ?? nested?.feels_like_c
            ?? nested?.apparent_c
        humidity = (try? c.decodeIfPresent(Int.self, forKey: .humidity)) ?? nested?.humidity
        wind_kmh = (try? c.decodeIfPresent(Double.self, forKey: .wind_kmh)) ?? nested?.wind_kmh
        precip_mm = (try? c.decodeIfPresent(Double.self, forKey: .precip_mm))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .precipitation_mm))
            ?? nested?.precip_mm
            ?? nested?.precipitation_mm
        condition = (try? c.decodeIfPresent(String.self, forKey: .condition)) ?? nested?.condition
        daily = try? c.decodeIfPresent([WeatherDay].self, forKey: .daily)
        items = try? c.decodeIfPresent([FinanceItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(updated_at, forKey: .updated_at)
        try c.encodeIfPresent(temp_c, forKey: .temp_c)
        try c.encodeIfPresent(feels_like_c, forKey: .feels_like_c)
        try c.encodeIfPresent(humidity, forKey: .humidity)
        try c.encodeIfPresent(wind_kmh, forKey: .wind_kmh)
        try c.encodeIfPresent(precip_mm, forKey: .precip_mm)
        try c.encodeIfPresent(condition, forKey: .condition)
        try c.encodeIfPresent(daily, forKey: .daily)
        try c.encodeIfPresent(items, forKey: .items)
    }
}

// MARK: - Inline sen_card / yerel_card Models

struct SenMetric: Identifiable, Codable, Hashable {
    var id: String { label }
    let label: String
    let value: Int
    let displayValue: String?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case label, value, score, emoji
    }

    init(label: String, value: Int, displayValue: String? = nil, emoji: String? = nil) {
        self.label = label
        self.value = value
        self.displayValue = displayValue
        self.emoji = emoji
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        emoji = try? c.decodeIfPresent(String.self, forKey: .emoji)
        if let iv = try? c.decode(Int.self, forKey: .value) {
            value = iv
            displayValue = nil
        } else if let dv = try? c.decode(Double.self, forKey: .value) {
            value = Int(round(dv <= 10 ? dv * 10 : dv))
            displayValue = dv <= 10 ? "\(String(format: "%.1f", dv).replacingOccurrences(of: ".0", with: "").replacingOccurrences(of: ".", with: ","))/10" : "%\(Int(round(dv)))"
        } else if let sv = (try? c.decode(String.self, forKey: .value)) ?? (try? c.decode(String.self, forKey: .score)) {
            displayValue = sv
            let nums = sv.components(separatedBy: CharacterSet(charactersIn: "0123456789.,").inverted).first ?? ""
            let dbl = Double(nums.replacingOccurrences(of: ",", with: ".")) ?? 80
            value = Int(round(dbl <= 10 ? dbl * 10 : dbl))
        } else {
            value = 0
            displayValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(emoji, forKey: .emoji)
    }
}

struct SenCompareSide: Codable, Hashable {
    let name: String
    let emoji: String?
    let subtitle: String?
    let image_query: String?
    let score: Int?
    let points: [String]?
}

struct SenMediaItem: Identifiable, Codable, Hashable {
    var id: String { "\(title)_\(year ?? "")" }
    let title: String
    let year: String?
    let subtitle: String?
    let badge: String?
    let image_query: String?
    let score: String?
}

struct SenProfileItem: Identifiable, Codable, Hashable {
    var id: String { "\(label ?? "")_\(title)" }
    let label: String?
    let title: String
    let subtitle: String?
    let traits: String?
    let emoji: String?
}

struct SenChecklistStep: Identifiable, Codable, Hashable {
    var id: String { label }
    let label: String
    let meta: String?
}

struct SenVisualCard: Identifiable, Decodable, Hashable {
    var id: String { "\(kind)_\(title ?? "")" }
    let kind: String
    let title: String?
    let subtitle: String?
    let badge: String?
    let summary: String?
    let note: String?
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
    let items: [SenMediaItem]?
    let profiles: [SenProfileItem]?
    let strengths: [String]?
    let challenges: [String]?

    enum CodingKeys: String, CodingKey {
        case kind, title, subtitle, badge, summary, note, score, emoji, metrics, left, right, verdict, tags, points, steps, items, profiles, strengths, challenges
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
        badge = try? c.decodeIfPresent(String.self, forKey: .badge)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        emoji = try? c.decodeIfPresent(String.self, forKey: .emoji)
        metrics = try? c.decodeIfPresent([SenMetric].self, forKey: .metrics)
        left = try? c.decodeIfPresent(SenCompareSide.self, forKey: .left)
        right = try? c.decodeIfPresent(SenCompareSide.self, forKey: .right)
        verdict = try? c.decodeIfPresent(String.self, forKey: .verdict)
        tags = try? c.decodeIfPresent([String].self, forKey: .tags)
        points = try? c.decodeIfPresent([String].self, forKey: .points)
        steps = try? c.decodeIfPresent([SenChecklistStep].self, forKey: .steps)
        items = try? c.decodeIfPresent([SenMediaItem].self, forKey: .items)
        profiles = try? c.decodeIfPresent([SenProfileItem].self, forKey: .profiles)
        strengths = try? c.decodeIfPresent([String].self, forKey: .strengths)
        challenges = try? c.decodeIfPresent([String].self, forKey: .challenges)

        if let intScore = try? c.decodeIfPresent(Int.self, forKey: .score) {
            score = intScore
            scoreText = intScore <= 10 ? "\(intScore)/10" : "%\(intScore)"
        } else if let dblScore = try? c.decodeIfPresent(Double.self, forKey: .score) {
            score = Int(round(dblScore <= 10 ? dblScore * 10 : dblScore))
            scoreText = dblScore <= 10 ? "\(String(format: "%.1f", dblScore).replacingOccurrences(of: ".0", with: "").replacingOccurrences(of: ".", with: ","))/10" : "%\(Int(round(dblScore)))"
        } else if let strScore = try? c.decodeIfPresent(String.self, forKey: .score) {
            let clean = strScore.components(separatedBy: CharacterSet(charactersIn: "0123456789.,").inverted).first ?? ""
            let dbl = Double(clean.replacingOccurrences(of: ",", with: ".")) ?? 85
            score = Int(round(dbl <= 10 ? dbl * 10 : dbl))
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
    var title: String
    let updated_at: String?
    var pinned: Bool? = false
}

enum ConnectionRoute: String {
    case disconnected = "Bağlı değil"
    case lan = "Ev Wi-Fi (LAN)"
    case cloudflare = "Sabit Köprü (Cloudflare)"
    case custom = "Özel Sunucu"
}
