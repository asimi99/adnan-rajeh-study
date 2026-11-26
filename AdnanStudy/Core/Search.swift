import Foundation
import CryptoKit

struct Moment: Hashable, Identifiable {
    let t: Double
    let hits: Int
    let snippet: String
    let highlights: [String]
    var id: Double { t }
}

struct SearchHit: Identifiable {
    let lecture: Lecture
    let moments: [Moment]
    var id: String { lecture.id }
}

struct SearchResult {
    var titles: [Lecture] = []
    var hits: [SearchHit] = []
    var partial = false
}

enum SearchEngine {
    static let buckets = 24

    /// Same normalisation as the site index: lowercase, no harakat, unified alif/ta marbuta/ya.
    static func tokens(_ text: String) -> [String] {
        var t = text.lowercased()
        t = t.replacingOccurrences(of: "[’'`]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[\u{064B}-\u{0652}\u{0670}]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[أإآ]", with: "ا", options: .regularExpression)
        t = t.replacingOccurrences(of: "ة", with: "ه")
        t = t.replacingOccurrences(of: "ى", with: "ي")
        var out: [String] = []
        var cur = ""
        func flush() {
            if cur.count >= 3 && !Stop.words.contains(cur) { out.append(cur) }
            cur = ""
        }
        for u in t.unicodeScalars {
            let v = u.value
            if (97...122).contains(v) || (48...57).contains(v) || (0x0600...0x06FF).contains(v) {
                cur.unicodeScalars.append(u)
            } else { flush() }
        }
        flush()
        return out
    }

    static func bucket(_ term: String) -> Int {
        let digest = Insecure.MD5.hash(data: Data(term.utf8))
        var r = 0
        for b in digest { r = (r * 256 + Int(b)) % buckets }
        return r
    }

    static func moments(in paras: [TimedText], terms: [String], raw: String, max: Int) -> [Moment] {
        var out: [Moment] = []
        for p in paras {
            let low = p.text.lowercased()
            var pos: String.Index? = nil
            var hits = 0
            if raw.count > 3, let r = low.range(of: raw) {
                pos = r.lowerBound
                hits = terms.count + 2
            } else {
                for term in terms {
                    if let r = low.range(of: "\\b" + NSRegularExpression.escapedPattern(for: term), options: .regularExpression) {
                        hits += 1
                        if pos == nil || r.lowerBound < pos! { pos = r.lowerBound }
                    }
                }
            }
            if hits > 0, let pos {
                out.append(Moment(t: p.t, hits: hits, snippet: snippet(p.text, low: low, at: pos), highlights: terms + (raw.count > 3 ? [raw] : [])))
            }
        }
        out.sort { ($0.hits, -$0.t) > ($1.hits, -$1.t) }
        return Array(out.prefix(max)).sorted { $0.t < $1.t }
    }

    private static func snippet(_ text: String, low: String, at pos: String.Index) -> String {
        let chars = Array(text)
        let off = Swift.min(low.distance(from: low.startIndex, to: pos), chars.count)
        var s = Swift.max(0, off - 90)
        var e = Swift.min(chars.count, off + 130)
        if s > 0, let sp = chars[0..<s].lastIndex(of: " ") { s = sp + 1 }
        if e < chars.count, let sp = chars[e...].firstIndex(of: " ") { e = sp }
        let frag = String(chars[s..<e])
        return (s > 0 ? "… " : "") + frag + (e < chars.count ? " …" : "")
    }

    @MainActor
    static func run(_ q: String, in lib: Library) async -> SearchResult {
        var result = SearchResult()
        var terms: [String] = []
        for t in tokens(q) where !terms.contains(t) { terms.append(t) }
        let raw = q.lowercased().trimmingCharacters(in: .whitespaces)

        let tq = terms.isEmpty ? [raw] : terms
        result.titles = Array(lib.own.filter { l in
            let s = (l.t + " " + (l.s ?? "")).lowercased().replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
            return tq.allSatisfy { s.contains($0) }
        }.prefix(40))
        guard !terms.isEmpty else { return result }

        var dict: [String: [Int]] = [:]
        for b in Set(terms.map(bucket)) {
            if let part = try? await DataCache.shared.decode([String: [Int]].self, "data/ix/\(b).json", maxAge: 60 * 60 * 24 * 3) {
                dict.merge(part) { a, _ in a }
            }
        }
        let docs = lib.docs
        var score: [Int: Double] = [:]
        var seen: [Int: Int] = [:]
        for term in terms {
            guard let lst = dict[term], !lst.isEmpty else { continue }
            let df = Double(lst.count / 2)
            let idf = log(1 + Double(docs.count) / Swift.max(df, 1))
            var i = 0
            while i + 1 < lst.count {
                let d = lst[i], c = lst[i + 1]
                if d < docs.count {
                    let w = Double(docs[d].w ?? 3000)
                    score[d, default: 0] += idf * (1 + log(Double(Swift.max(c, 1)))) * Swift.min(1, 3000 / w + 0.5)
                    seen[d, default: 0] += 1
                }
                i += 2
            }
        }
        var ranked = score.filter { seen[$0.key] == terms.count }
        if ranked.isEmpty { ranked = score; result.partial = !score.isEmpty }
        let top = ranked.sorted { $0.value > $1.value }.prefix(24)

        for (d, _) in top {
            let doc = docs[d]
            guard let lecture = lib.byId[doc.id] else { continue }
            let shard = await lib.shard(doc.sh)
            guard let rec = shard[doc.id] else { continue }
            let ms = moments(in: rec.p, terms: terms, raw: raw, max: 6)
            if !ms.isEmpty { result.hits.append(SearchHit(lecture: lecture, moments: ms)) }
        }
        return result
    }
}
