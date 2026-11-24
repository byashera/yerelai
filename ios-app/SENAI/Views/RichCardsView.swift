import SwiftUI

// MARK: - Zero-Flash Markdown & sen_card / yerel_card Segment Parser

enum MessageSegment: Identifiable {
    case markdown(String)
    case codeBlock(lang: String, code: String)
    case table(headers: [String], rows: [[String]])
    case cardLoading(kind: String?)
    case visualCard(SenVisualCard)

    var id: String {
        switch self {
        case .markdown(let s): return "md_\(s.hashValue)"
        case .codeBlock(let l, let c): return "code_\(l)_\(c.hashValue)"
        case .table(let h, let r): return "tbl_\(h.joined().hashValue)_\(r.count)"
        case .cardLoading(let k): return "card_loading_\(k ?? "generic")"
        case .visualCard(let c): return "card_\(c.id)"
        }
    }
}

enum MarkdownCardParser {
    private static func extractCardKind(_ raw: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\"kind\"\\s*:\\s*\"([a-z_]+)\"", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        return String(raw[range]).lowercased()
    }

    static func parse(_ raw: String, isStreaming: Bool) -> [MessageSegment] {
        let src = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var segments: [MessageSegment] = []
        var cursor = src.startIndex

        while cursor < src.endIndex {
            guard let fenceStart = src.range(of: "```", range: cursor..<src.endIndex) else {
                let tail = String(src[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { segments.append(contentsOf: splitTables(tail)) }
                break
            }

            let before = String(src[cursor..<fenceStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty { segments.append(contentsOf: splitTables(before)) }

            let afterTicks = fenceStart.upperBound
            let lineEnd = src[afterTicks...].firstIndex(of: "\n") ?? src.endIndex
            let lang = String(src[afterTicks..<lineEnd]).trimmingCharacters(in: .whitespaces).lowercased()
            let bodyStart = lineEnd < src.endIndex ? src.index(after: lineEnd) : src.endIndex

            let isCardLang = (lang == "sen_card" || lang == "sen-card" || lang == "yerel_card" || lang == "yerel-card")

            if let fenceEnd = src.range(of: "```", range: bodyStart..<src.endIndex) {
                let body = String(src[bodyStart..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let looksLikeJsonCard = (lang == "json" && body.hasPrefix("{") && body.contains("\"kind\""))
                if (isCardLang || looksLikeJsonCard),
                   let data = body.data(using: .utf8),
                   let card = try? JSONDecoder().decode(SenVisualCard.self, from: data) {
                    segments.append(.visualCard(card))
                } else {
                    segments.append(.codeBlock(lang: lang.isEmpty ? "kod" : lang, code: body))
                }
                cursor = fenceEnd.upperBound
            } else {
                // Unclosed fence while streaming: NEVER flash raw JSON code for sen_card or ambiguous early fences!
                let partialRaw = String(src[bodyStart...])
                let partialTrimmed = partialRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let partialKind = extractCardKind(partialRaw)
                let isCardPrefix = isStreaming && (
                    isCardLang ||
                    (lang.isEmpty && (lineEnd == src.endIndex || partialTrimmed.isEmpty || partialTrimmed.hasPrefix("{"))) ||
                    "sen_card".hasPrefix(lang) ||
                    "sen-card".hasPrefix(lang) ||
                    "yerel_card".hasPrefix(lang) ||
                    "yerel-card".hasPrefix(lang) ||
                    (lang == "json" && (partialTrimmed.isEmpty || (partialTrimmed.hasPrefix("{") && (partialTrimmed.count < 56 || partialKind != nil || partialTrimmed.contains("\"kind\"")))))
                )
                if isCardPrefix {
                    segments.append(.cardLoading(kind: partialKind))
                } else {
                    let partialCode = partialRaw.trimmingCharacters(in: .newlines)
                    segments.append(.codeBlock(lang: lang.isEmpty ? "kod" : lang, code: partialCode))
                }
                break
            }
        }
        return segments
    }

    private static func splitTables(_ text: String) -> [MessageSegment] {
        let lines = text.components(separatedBy: "\n")
        var out: [MessageSegment] = []
        var buf: [String] = []
        var i = 0

        func flushBuf() {
            let joined = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.markdown(joined)) }
            buf.removeAll()
        }

        func parseRow(_ line: String) -> [String] {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") { trimmed.removeFirst() }
            if trimmed.hasSuffix("|") { trimmed.removeLast() }
            return trimmed.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        }

        func isSeparator(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("|") && t.contains("-") else { return false }
            let allowed = CharacterSet(charactersIn: "|:- ")
            return t.unicodeScalars.allSatisfy { allowed.contains($0) }
        }

        while i < lines.count {
            if i + 1 < lines.count && lines[i].contains("|") && isSeparator(lines[i + 1]) {
                let headers = parseRow(lines[i])
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count && lines[j].contains("|") && !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(parseRow(lines[j]))
                    j += 1
                }
                if headers.count >= 2 && !rows.isEmpty {
                    flushBuf()
                    out.append(.table(headers: headers, rows: rows))
                    i = j
                    continue
                }
            }
            buf.append(lines[i])
            i += 1
        }
        flushBuf()
        return out
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
        case "compatibility", "scorecard":
            CompatibilityCardView(card: card)
        case "media_list":
            MediaListCardView(card: card)
        case "image_compare":
            ImageCompareCardView(card: card)
        case "compare":
            if card.left?.image_query != nil || card.right?.image_query != nil {
                ImageCompareCardView(card: card)
            } else {
                CompareCardView(card: card)
            }
        case "rating":
            RatingCardView(card: card)
        case "checklist":
            ChecklistCardView(card: card)
        case "image_spotlight":
            ImageSpotlightCardView(card: card)
        case "choice_card":
            ChoiceQuestionnaireCardView(card: card)
        default:
            EmptyView()
        }
    }
}

struct SenShimmerBox: View {
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.28),
                                Color.clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(geo.size.width * 0.65, 60))
                        .offset(x: sweep ? geo.size.width * 1.15 : -geo.size.width * 0.75)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: height == nil ? .infinity : nil)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}

struct SenCardSkeletonView: View {
    let kind: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if kind == "image_compare" || kind == "compare" {
                SenShimmerBox(width: 150, height: 18, cornerRadius: 8)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 7) {
                            SenShimmerBox(height: 116, cornerRadius: 14)
                            SenShimmerBox(width: 90, height: 14, cornerRadius: 6)
                            SenShimmerBox(height: 11, cornerRadius: 5)
                            SenShimmerBox(width: 105, height: 11, cornerRadius: 5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if kind == "image_spotlight" {
                SenShimmerBox(width: 240, height: 175, cornerRadius: 16)
                SenShimmerBox(width: 190, height: 14, cornerRadius: 7)
            } else if kind == "scorecard" || kind == "compatibility" || kind == "choice_card" || kind == "checklist" {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SenShimmerBox(width: 150, height: 16, cornerRadius: 7)
                        Spacer()
                        SenShimmerBox(width: 66, height: 16, cornerRadius: 8)
                    }
                    SenShimmerBox(height: 14, cornerRadius: 7)
                    SenShimmerBox(width: 210, height: 14, cornerRadius: 7)
                    SenShimmerBox(height: 36, cornerRadius: 12)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                        }
                }
            } else {
                // Default / media_list skeleton (movie posters / product cards pre-drawn while streaming!)
                SenShimmerBox(width: 160, height: 18, cornerRadius: 8)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 12) {
                        SenShimmerBox(width: 68, height: 94, cornerRadius: 11)
                        VStack(alignment: .leading, spacing: 8) {
                            SenShimmerBox(width: 155, height: 15, cornerRadius: 6)
                            SenShimmerBox(height: 12, cornerRadius: 5)
                            SenShimmerBox(width: 180, height: 12, cornerRadius: 5)
                            SenShimmerBox(width: 74, height: 16, cornerRadius: 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct CompatibilityCardView: View {
    let card: SenVisualCard
    @State private var appeared: Bool = false

    private var bigScoreDisplay: String {
        if let st = card.scoreText, !st.isEmpty { return st }
        if let sc = card.score {
            if sc <= 10 { return "\(sc)/10" }
            let ten = Double(sc) / 10.0
            let formatted = String(format: "%.1f", ten).replacingOccurrences(of: ".0", with: "").replacingOccurrences(of: ".", with: ",")
            return "\(formatted)/10"
        }
        return "9/10"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Title + Status Pill
            HStack(alignment: .center, spacing: 8) {
                Text(card.title ?? "Uyum Analizi")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 6)
                if let badge = card.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Color.green.opacity(0.14)) }
                }
            }

            // Optional 2-Profile Header (e.g. 1. Kişi / 2. Kişi)
            if let profiles = card.profiles, !profiles.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(profiles.prefix(2)) { prof in
                        VStack(alignment: .leading, spacing: 3) {
                            if let em = prof.emoji, !em.isEmpty {
                                Text(em).font(.subheadline)
                            }
                            Text(prof.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            if let sub = prof.subtitle, !sub.isEmpty {
                                Text(sub)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let tr = prof.traits, !tr.isEmpty {
                                Text(tr)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary.opacity(0.85))
                                    .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider().opacity(0.45)
            }

            // Big Centered Score Hero
            VStack(spacing: 4) {
                Text(bigScoreDisplay)
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.green)
                    .scaleEffect(appeared ? 1.0 : 0.85)
                    .opacity(appeared ? 1 : 0)
                Text(card.subtitle ?? "Genel uyum puanı")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let note = card.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Clean Minimalist Category Score Rows
            if let metrics = card.metrics, !metrics.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("Kategori")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Puan")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 7)

                    Divider().opacity(0.5)

                    ForEach(metrics) { m in
                        HStack(spacing: 8) {
                            Text(m.emoji != nil ? "\(m.emoji!) \(m.label)" : m.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(m.displayValue ?? formatMetricScore(m.value))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 8)
                        Divider().opacity(0.32)
                    }
                }
            }

            // Strengths & Challenges
            if let strengths = card.strengths, !strengths.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Güçlü yönleri")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    ForEach(strengths, id: \.self) { s in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.green)
                            Text(s).font(.caption).foregroundStyle(Color.primary.opacity(0.82))
                        }
                    }
                }
            }

            if let challenges = card.challenges, !challenges.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Zorlanabilecekleri")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    ForEach(challenges, id: \.self) { ch in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.orange)
                            Text(ch).font(.caption).foregroundStyle(Color.primary.opacity(0.82))
                        }
                    }
                }
            }

            if let sum = card.summary, !sum.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("✨ Özet")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(sum)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.opacity(0.75))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.85)
                }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.18)) {
                appeared = true
            }
        }
    }

    private func formatMetricScore(_ val: Int) -> String {
        if val <= 10 { return "\(val)/10" }
        let ten = Double(val) / 10.0
        let formatted = String(format: "%.1f", ten).replacingOccurrences(of: ".0", with: "").replacingOccurrences(of: ".", with: ",")
        return "\(formatted)/10"
    }
}

// MARK: - Universal Media List Card (Movies, Tarot, Products with HD Web Images)

struct MediaListCardView: View {
    @EnvironmentObject private var server: ServerManager
    let card: SenVisualCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = card.title, !title.isEmpty {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            if let items = card.items, !items.isEmpty {
                VStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        HStack(alignment: .top, spacing: 12) {
                            ResolvedRemoteImageView(
                                url: server.imageResolveURL(for: item.image_query ?? item.title),
                                fallbackIcon: "sparkles.rectangle.stack"
                            )
                            .frame(width: 68, height: 94)
                            .clipShape(.rect(cornerRadius: 11))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text("\(idx + 1). \(item.title)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    if let yr = item.year, !yr.isEmpty {
                                        Text("(\(yr))")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let sub = item.subtitle, !sub.isEmpty {
                                    Text(sub)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(2.5)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                HStack(spacing: 6) {
                                    if let badge = item.badge, !badge.isEmpty {
                                        Text(badge)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background { Capsule().fill(Color.green.opacity(0.14)) }
                                    }
                                    if let sc = item.score, !sc.isEmpty {
                                        Text("★ \(sc)")
                                            .font(.caption2.weight(.bold).monospacedDigit())
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if let sum = card.summary, !sum.isEmpty {
                Text(sum)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Universal 2-Image Side-by-Side Comparison Card (Products, Fabrics, Zodiac)

struct ImageCompareCardView: View {
    @EnvironmentObject private var server: ServerManager
    let card: SenVisualCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = card.title, !title.isEmpty {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }

            HStack(alignment: .top, spacing: 10) {
                if let left = card.left {
                    compareColumn(left, accent: .blue)
                }
                if let right = card.right {
                    compareColumn(right, accent: .indigo)
                }
            }

            if let verdict = card.verdict, !verdict.isEmpty {
                Text("✨ \(verdict)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
            }
        }
    }

    private func compareColumn(_ side: SenCompareSide, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ResolvedRemoteImageView(
                url: server.imageResolveURL(for: side.image_query ?? side.name),
                fallbackIcon: "photo"
            )
            .frame(height: 116)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
            }

            Text("\(side.name) \(side.emoji ?? "")".trimmingCharacters(in: .whitespaces))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            if let sub = side.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let pts = side.points, !pts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pts, id: \.self) { p in
                        HStack(alignment: .top, spacing: 5) {
                            Text("•").foregroundStyle(accent)
                            Text(p)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResolvedRemoteImageView: View {
    let url: URL?
    let fallbackIcon: String

    var body: some View {
        if let url, url.host == "preview.sen.ai" {
            simulatorArtwork(for: url.query ?? "")
        } else if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                case .failure:
                    placeholder
                case .empty:
                    SenShimmerBox(cornerRadius: 0)
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private func simulatorArtwork(for query: String) -> some View {
        let q = (query.removingPercentEncoding ?? query).lowercased()
        let colors: [Color]
        let symbol: String
        let caption: String
        if q.contains("shutter") || q.contains("eskiya") {
            colors = [Color(red: 0.10, green: 0.22, blue: 0.45), Color(red: 0.22, green: 0.42, blue: 0.78)]
            symbol = "film.stack.fill"
            caption = "AFİŞ"
        } else if q.contains("se7en") || q.contains("av mevsimi") {
            colors = [Color(red: 0.36, green: 0.18, blue: 0.08), Color(red: 0.72, green: 0.38, blue: 0.14)]
            symbol = "Clapperboard" == "" ? "film.fill" : "film.fill"
            caption = "SİNEMA"
        } else if q.contains("gone") {
            colors = [Color(red: 0.12, green: 0.30, blue: 0.38), Color(red: 0.28, green: 0.54, blue: 0.66)]
            symbol = "sparkles.tv.fill"
            caption = "FİLM"
        } else if q.contains("velvet") || q.contains("kadife") || q.contains("full size") {
            colors = [Color(red: 0.18, green: 0.22, blue: 0.34), Color(red: 0.32, green: 0.38, blue: 0.56)]
            symbol = q.contains("keyboard") ? "keyboard.fill" : "square.grid.3x3.fill"
            caption = q.contains("keyboard") ? "100% TAM" : "DOKU"
        } else {
            colors = [Color(red: 0.14, green: 0.16, blue: 0.20), Color(red: 0.28, green: 0.32, blue: 0.40)]
            symbol = q.contains("keyboard") ? "keyboard" : "sparkles"
            caption = q.contains("keyboard") ? "TKL %80" : "DETAY"
        }
        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 54, height: 54)
                .offset(x: 16, y: -14)
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(caption)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.14), Color.indigo.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: fallbackIcon)
                .font(.title3)
                .foregroundStyle(.secondary.opacity(0.7))
        }
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
        let steps = card.steps ?? []
        let total = max(steps.count, 1)
        let doneCount = steps.filter { checked.contains($0.id) }.count
        let progress = CGFloat(doneCount) / CGFloat(total)

        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title ?? "Günlük Plan")
                        .font(.headline.weight(.bold))
                    Text("\(doneCount)/\(steps.count) tamamlandı")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(doneCount == steps.count && steps.count > 0 ? Color.green : Color.secondary)
                }
                Spacer()
                if let badge = card.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Color.blue.opacity(0.13)) }
                }
            }

            // Live Animated Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: doneCount == steps.count && steps.count > 0 ? [.green, .mint] : [.blue, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(progress > 0 ? 10 : 0, geo.size.width * progress))
                        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: progress)
                }
            }
            .frame(height: 6)

            if !steps.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, st in
                        let isDone = checked.contains(st.id)
                        Button {
                            SenHaptics.light()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                if isDone { checked.remove(st.id) } else { checked.insert(st.id) }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(isDone ? Color.green : Color.secondary.opacity(0.7))
                                    .contentTransition(.symbolEffect(.replace))
                                Text("\(idx + 1). \(st.label)")
                                    .font(.subheadline.weight(.medium))
                                    .strikethrough(isDone)
                                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 6)
                                if let meta = st.meta, !meta.isEmpty {
                                    Text(meta)
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(isDone ? Color.secondary : Color.blue)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background {
                                            Capsule().fill((isDone ? Color.secondary : Color.blue).opacity(0.11))
                                        }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isDone ? Color.green.opacity(0.06) : Color.primary.opacity(0.035))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.opacity(0.75))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.85)
                }
        }
    }
}


// MARK: - Native SwiftUI Code Block & Markdown Table Cards

struct CodeBlockCardView: View {
    let lang: String
    let code: String
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                    Text(lang.uppercased())
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    SenHaptics.light()
                    withAnimation(.snappy(duration: 0.2)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.snappy(duration: 0.2)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                        Text(copied ? "Kopyalandı" : "Kopyala")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(copied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(Color.primary.opacity(0.07)) }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background { Color.primary.opacity(0.05) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    let lines = code.components(separatedBy: "\n")
                    VStack(alignment: .trailing, spacing: 2.5) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                            Text("\(idx + 1)")
                                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.45))
                        }
                    }
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2.5) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(CodeSyntaxHighlighter.highlight(line))
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.background.opacity(0.65))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                }
        }
        .clipShape(.rect(cornerRadius: 15))
    }
}

private enum CodeSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "def", "return", "for", "in", "if", "else", "elif", "while", "import", "from", "as",
        "class", "try", "except", "finally", "with", "lambda", "yield", "async", "await",
        "True", "False", "None", "and", "or", "not", "is", "pass", "break", "continue",
        "func", "let", "var", "struct", "enum", "private", "public", "guard", "switch", "case",
        "const", "function", "export", "default", "new", "this", "true", "false", "null",
        "SELECT", "FROM", "WHERE", "JOIN", "GROUP", "ORDER", "BY", "LIMIT", "INSERT", "UPDATE"
    ]

    static func highlight(_ line: String) -> AttributedString {
        var result = AttributedString()
        if line.isEmpty { return AttributedString(" ") }

        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]

            // Comment (# or //)
            if ch == "#" || (ch == "/" && i + 1 < chars.count && chars[i + 1] == "/") {
                var seg = AttributedString(String(chars[i...]))
                seg.foregroundColor = Color.secondary
                result.append(seg)
                break
            }

            // String literal
            if ch == "\"" || ch == "'" {
                let quote = ch
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "\\" && j + 1 < chars.count {
                        j += 2
                        continue
                    }
                    if chars[j] == quote {
                        j += 1
                        break
                    }
                    j += 1
                }
                var seg = AttributedString(String(chars[i..<j]))
                seg.foregroundColor = Color(red: 0.28, green: 0.80, blue: 0.52)
                result.append(seg)
                i = j
                continue
            }

            // Number literal
            if ch.isNumber {
                var j = i + 1
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") {
                    j += 1
                }
                var seg = AttributedString(String(chars[i..<j]))
                seg.foregroundColor = Color(red: 0.35, green: 0.78, blue: 0.98)
                result.append(seg)
                i = j
                continue
            }

            // Identifier / keyword / function call
            if ch.isLetter || ch == "_" {
                var j = i + 1
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") {
                    j += 1
                }
                let word = String(chars[i..<j])
                var seg = AttributedString(word)
                if keywords.contains(word) {
                    seg.foregroundColor = Color(red: 0.78, green: 0.50, blue: 0.98)
                } else if j < chars.count && chars[j] == "(" {
                    seg.foregroundColor = Color(red: 0.38, green: 0.68, blue: 1.0)
                } else {
                    seg.foregroundColor = Color.primary
                }
                result.append(seg)
                i = j
                continue
            }

            var seg = AttributedString(String(ch))
            seg.foregroundColor = Color.primary.opacity(0.88)
            result.append(seg)
            i += 1
        }
        return result
    }
}

struct MarkdownTableCardView: View {
    let headers: [String]
    let rows: [[String]]
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if headers.count == 2 {
                // ChatGPT-style ultra-clean borderless 2-column table (left label, right bold value)
                HStack {
                    Text(headers[0])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(headers[1])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 8)

                Divider().opacity(0.55)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        tableCellView(row.count > 0 ? row[0] : "", isRightAligned: false, isBold: false)
                        Spacer(minLength: 12)
                        tableCellView(row.count > 1 ? row[1] : "", isRightAligned: true, isBold: true)
                    }
                    .padding(.vertical, 9)
                    Divider().opacity(0.30)
                }
            } else if headers.count <= 4 {
                // 3-4 column table: all columns left-aligned & normal weight (ChatGPT comparison table style!)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                        Text(tableCellAttributed(h))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)

                Divider().opacity(0.55)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(0..<headers.count, id: \.self) { cIdx in
                            tableCellView(cIdx < row.count ? row[cIdx] : "", isRightAligned: false, isBold: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 9)
                    Divider().opacity(0.30)
                }
            } else {
                // 5+ column table: horizontal scroll, all left-aligned
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                                Text(tableCellAttributed(h))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .frame(minWidth: 84, alignment: .leading)
                                    .padding(.trailing, 12)
                                    .padding(.vertical, 8)
                            }
                        }
                        Divider().opacity(0.55)

                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(0..<headers.count, id: \.self) { cIdx in
                                    tableCellView(cIdx < row.count ? row[cIdx] : "", isRightAligned: false, isBold: false)
                                        .frame(minWidth: 84, alignment: .leading)
                                        .padding(.trailing, 12)
                                        .padding(.vertical, 9)
                                }
                            }
                            Divider().opacity(0.30)
                        }
                    }
                }
            }

            HStack {
                if headers.count >= 5 {
                    Text("Kaydır →")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                Spacer()
                Button {
                    let tsv = ([headers] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
                    UIPasteboard.general.string = tsv
                    SenHaptics.light()
                    withAnimation(.snappy(duration: 0.2)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.snappy(duration: 0.2)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                        Text(copied ? "Kopyalandı" : "Tabloyu kopyala")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tableCellView(_ raw: String, isRightAligned: Bool, isBold: Bool) -> some View {
        let stripped = raw.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let low = stripped.lowercased()
        let isHighlightBadge = (low == "çok iyi" || low == "cok iyi" || low == "en iyi" || low == "mükemmel")
        if isHighlightBadge {
            Text(stripped)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background { Capsule().fill(Color.green.opacity(0.14)) }
        } else {
            Text(tableCellAttributed(raw))
                .font(isBold ? .subheadline.weight(.semibold).monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(isRightAligned ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tableCellAttributed(_ raw: String) -> AttributedString {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return parsed
        }
        return AttributedString(trimmed.replacingOccurrences(of: "**", with: ""))
    }
}

// MARK: - Single Location / Subject HD Spotlight Photo Card (ChatGPT style)

struct ImageSpotlightCardView: View {
    @EnvironmentObject private var server: ServerManager
    let card: SenVisualCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResolvedRemoteImageView(
                url: server.imageResolveURL(for: card.image_query ?? card.title),
                fallbackIcon: "photo.on.rectangle.angled"
            )
            .frame(height: 175)
            .frame(maxWidth: 260)
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
            }

            if let loc = card.location_label, !loc.isEmpty {
                HStack(spacing: 5) {
                    Text("Konum:")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(loc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let title = card.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ChatGPT-Style Interactive Choice Questionnaire Card

struct ChoiceQuestionnaireCardView: View {
    @EnvironmentObject private var server: ServerManager
    let card: SenVisualCard
    @State private var selections: [String: String] = [:]
    @State private var submitted: Bool = false

    var body: some View {
        let questions = card.questions ?? []
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(questions.enumerated()), id: \.element.id) { qIdx, q in
                let displayQuestion = q.question.first?.isNumber == true ? q.question : "\(qIdx + 1). \(q.question)"
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayQuestion)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    ForEach(q.options, id: \.self) { opt in
                        let current = selections[q.id] ?? q.options.first ?? ""
                        let isSelected = (current == opt)
                        Button {
                            SenHaptics.light()
                            selections[q.id] = opt
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(isSelected ? Color.primary : Color.secondary.opacity(0.38), lineWidth: isSelected ? 5 : 1.5)
                                        .frame(width: 20, height: 20)
                                }
                                Text(opt)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if qIdx < questions.count - 1 {
                    Divider().opacity(0.35)
                }
            }

            Button {
                SenHaptics.medium()
                let summaryLines = questions.map { q -> String in
                    let chosen = selections[q.id] ?? q.options.first ?? ""
                    return "\(q.question) \(chosen)"
                }
                submitted = true
                server.sendMessage("Tercihlerime göre değerlendir:\n" + summaryLines.joined(separator: "\n"))
            } label: {
                Text(submitted ? "Gönderildi ✓" : "Tercihlerime göre değerlendir")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(submitted ? Color.white : Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        Capsule().fill(submitted ? Color.green : Color.primary)
                    }
            }
            .buttonStyle(SenSpringButtonStyle())
            .disabled(submitted || server.isGenerating)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        }
    }
}
