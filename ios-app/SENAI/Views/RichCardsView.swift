import SwiftUI

// MARK: - Zero-Flash Markdown & sen_card / yerel_card Segment Parser

enum MessageSegment: Identifiable {
    case markdown(String)
    case cardLoading
    case visualCard(SenVisualCard)

    var id: String {
        switch self {
        case .markdown(let s): return "md_\(s.hashValue)"
        case .cardLoading: return "card_loading"
        case .visualCard(let c): return "card_\(c.id)"
        }
    }
}

enum MarkdownCardParser {
    static func parse(_ raw: String, isStreaming: Bool) -> [MessageSegment] {
        let src = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var segments: [MessageSegment] = []
        var cursor = src.startIndex

        while cursor < src.endIndex {
            guard let fenceStart = src.range(of: "```", range: cursor..<src.endIndex) else {
                let tail = String(src[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { segments.append(.markdown(tail)) }
                break
            }

            let before = String(src[cursor..<fenceStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty { segments.append(.markdown(before)) }

            let afterTicks = fenceStart.upperBound
            let lineEnd = src[afterTicks...].firstIndex(of: "\n") ?? src.endIndex
            let lang = String(src[afterTicks..<lineEnd]).trimmingCharacters(in: .whitespaces).lowercased()
            let bodyStart = lineEnd < src.endIndex ? src.index(after: lineEnd) : src.endIndex

            let isCardLang = (lang == "sen_card" || lang == "sen-card" || lang == "yerel_card" || lang == "yerel-card")
            let isCardPrefix = isStreaming && (
                (!lang.isEmpty && ("sen_card".hasPrefix(lang) || "yerel_card".hasPrefix(lang))) ||
                (lang.isEmpty && String(src[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
            )

            if let fenceEnd = src.range(of: "```", range: bodyStart..<src.endIndex) {
                let body = String(src[bodyStart..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isCardLang, let data = body.data(using: .utf8),
                   let card = try? JSONDecoder().decode(SenVisualCard.self, from: data) {
                    segments.append(.visualCard(card))
                } else {
                    let fullFence = String(src[fenceStart.lowerBound..<fenceEnd.upperBound])
                    segments.append(.markdown(fullFence))
                }
                cursor = fenceEnd.upperBound
            } else {
                // Unclosed fence while streaming
                if isCardLang || isCardPrefix {
                    segments.append(.cardLoading)
                } else {
                    let rest = String(src[fenceStart.lowerBound...])
                    segments.append(.markdown(rest))
                }
                break
            }
        }
        return segments
    }
}

// MARK: - Server Rich Cards (Weather & Finance)

struct WeatherCardView: View {
    let card: RichCardPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.location ?? "Hava Durumu")
                        .font(.subheadline.weight(.bold))
                    if let upd = card.updated_at {
                        let cleanUpd = upd.hasPrefix("Canlı") ? upd : "Canlı · \(upd)"
                        Text(cleanUpd)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        if let t = card.temp_c {
                            Text(String(format: "%.1f°C", t))
                                .font(.title2.weight(.bold).monospacedDigit())
                        }
                        if let cond = card.condition {
                            Text(cond)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: weatherSymbol(for: card.condition))
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 34, height: 34)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.14))
                        }
                }
            }

            // Compact 1-row stats strip (fits all 4 cleanly without right-edge clipping)
            HStack(spacing: 5) {
                if let f = card.feels_like_c {
                    statChip("Hissedilen \(String(format: "%.0f°", f))")
                }
                if let h = card.humidity {
                    statChip("Nem %\(h)")
                }
                if let w = card.wind_kmh {
                    statChip("\(String(format: "%.1f", w)) km/s")
                }
                if let p = card.precip_mm {
                    statChip("\(String(format: "%.0f", p)) mm")
                }
            }

            // Apple Weather style 5-column single horizontal forecast strip
            if let days = card.daily, !days.isEmpty {
                HStack(spacing: 5) {
                    ForEach(days.prefix(5)) { d in
                        VStack(spacing: 3) {
                            Text(d.day ?? "-")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: weatherSymbol(for: d.condition))
                                .font(.caption)
                                .foregroundStyle(.blue)
                            if let hi = d.t_max, let lo = d.t_min {
                                Text("\(Int(hi.rounded()))°/\(Int(lo.rounded()))°")
                                    .font(.caption2.monospacedDigit())
                                    .lineLimit(1)
                            }
                            if let rp = d.rain_prob {
                                Text("%\(rp)")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.background.opacity(0.75))
                        }
                    }
                }
            }
        }
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.12), Color.indigo.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.22), lineWidth: 0.8)
                }
        }
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(.background.opacity(0.75))
            }
    }

    private func weatherSymbol(for condition: String?) -> String {
        let c = (condition ?? "").lowercased()
        if c.contains("yağmur") || c.contains("sağanak") { return "cloud.rain.fill" }
        if c.contains("kar") { return "cloud.snow.fill" }
        if c.contains("güneş") || c.contains("açık") { return "sun.max.fill" }
        if c.contains("sis") { return "cloud.fog.fill" }
        if c.contains("fırtına") { return "cloud.bolt.rain.fill" }
        return "cloud.sun.fill"
    }
}

struct FinanceCardView: View {
    let card: RichCardPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.title ?? "Canlı Döviz Kurları")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let upd = card.updated_at {
                    Text(upd).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let items = card.items {
                HStack(spacing: 8) {
                    ForEach(items) { it in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.code)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f ₺", it.rate))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(.background.opacity(0.8))
                        }
                    }
                }
            }
        }
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.22), lineWidth: 0.8)
                }
        }
    }
}

// MARK: - Inline Visual Cards (Compatibility, Compare, Rating, Checklist)

struct SenVisualCardView: View {
    let card: SenVisualCard

    var body: some View {
        switch card.kind {
        case "compatibility":
            CompatibilityCardView(card: card)
        case "compare":
            CompareCardView(card: card)
        case "rating":
            RatingCardView(card: card)
        case "checklist":
            ChecklistCardView(card: card)
        default:
            EmptyView()
        }
    }
}

struct CardLoadingPlaceholder: View {
    var body: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text("Görsel kart hazırlanıyor...")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.secondary.opacity(0.10))
        }
    }
}

struct CompatibilityCardView: View {
    let card: SenVisualCard
    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        let score = min(max(card.score ?? 80, 0), 100)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title ?? "Uyum Analizi")
                        .font(.headline.weight(.bold))
                    if let badge = card.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background { Capsule().fill(Color.blue.opacity(0.13)) }
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.08))
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 5.5)
                    Circle()
                        .trim(from: 0, to: animatedProgress * (CGFloat(score) / 100.0))
                        .stroke(
                            LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("%\(score)")
                        .font(.caption.weight(.heavy).monospacedDigit())
                }
                .frame(width: 56, height: 56)
            }

            if let metrics = card.metrics, !metrics.isEmpty {
                VStack(spacing: 8) {
                    ForEach(metrics) { m in
                        let c = semanticColor(for: m.label)
                        VStack(spacing: 4) {
                            HStack {
                                Text(m.label).font(.caption.weight(.semibold))
                                Spacer()
                                Text("%\(m.value)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(c)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(c)
                                        .frame(width: geo.size.width * animatedProgress * CGFloat(min(max(m.value, 0), 100)) / 100.0)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }

            if let sum = card.summary, !sum.isEmpty {
                Text(sum)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.background.opacity(0.75))
                    }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.indigo.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.pink.opacity(0.24), Color.blue.opacity(0.26)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.9
                        )
                }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.78, bounce: 0.14)) {
                animatedProgress = 1.0
            }
        }
    }

    private func semanticColor(for label: String) -> Color {
        let s = label.lowercased()
        if s.contains("aşk") || s.contains("tutku") || s.contains("romant") || s.contains("kalp") { return .pink }
        if s.contains("güven") || s.contains("sadakat") || s.contains("sağlam") { return .green }
        if s.contains("iletişim") || s.contains("anlayış") || s.contains("sohbet") { return .blue }
        if s.contains("kariyer") || s.contains("enerji") || s.contains("hedef") { return .orange }
        return .indigo
    }
}

struct CompareCardView: View {
    let card: SenVisualCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title ?? "Karşılaştırma")
                .font(.headline.weight(.bold))

            if let left = card.left { sideBox(left, accent: .blue) }
            if let right = card.right { sideBox(right, accent: .indigo) }

            if let verdict = card.verdict, !verdict.isEmpty {
                Text("✨ \(verdict)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.background.opacity(0.75))
                    }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.8)
                }
        }
    }

    private func sideBox(_ side: SenCompareSide, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(side.emoji ?? "") \(side.name)".trimmingCharacters(in: .whitespaces))
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let sc = side.score {
                    Text("%\(sc)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(accent.opacity(0.14)) }
                }
            }
            if let pts = side.points {
                ForEach(pts, id: \.self) { p in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(accent)
                        Text(p).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.opacity(0.8))
        }
    }
}

struct RatingCardView: View {
    let card: SenVisualCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(card.emoji ?? "") \(card.title ?? "Öneri")".trimmingCharacters(in: .whitespaces))
                        .font(.headline.weight(.bold))
                    if let tags = card.tags, !tags.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(tags.prefix(3), id: \.self) { t in
                                Text(t)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background { Capsule().fill(Color.orange.opacity(0.14)) }
                            }
                        }
                    }
                }
                Spacer()
                if let st = card.scoreText {
                    Text("★ \(st)")
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                        }
                }
            }
            if let pts = card.points {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pts, id: \.self) { p in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.orange)
                            Text(p).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let sum = card.summary {
                Text(sum)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.background.opacity(0.75))
                    }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.8)
                }
        }
    }
}

struct ChecklistCardView: View {
    let card: SenVisualCard
    @State private var checked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(card.title ?? "Hızlı Plan")
                    .font(.headline.weight(.bold))
                Spacer()
                if let badge = card.badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(Color.blue.opacity(0.13)) }
                }
            }
            if let steps = card.steps {
                VStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, st in
                        let isDone = checked.contains(st.id)
                        Button {
                            SenHaptics.light()
                            if isDone { checked.remove(st.id) } else { checked.insert(st.id) }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isDone ? .green : .secondary)
                                Text("\(idx + 1). \(st.label)")
                                    .font(.caption.weight(.medium))
                                    .strikethrough(isDone)
                                    .foregroundStyle(isDone ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if let meta = st.meta {
                                    Text(meta)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(9)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.background.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.8)
                }
        }
    }
}
