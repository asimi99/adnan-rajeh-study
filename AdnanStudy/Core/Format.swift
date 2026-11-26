import Foundation

enum Fmt {
    /// 1:02:03 or 2:03
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, x = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, x) }
        return String(format: "%d:%02d", m, x)
    }

    /// "1 h 05" or "42 min"
    static func duration(_ seconds: Int?) -> String {
        guard let s = seconds, s > 0 else { return "" }
        let h = s / 3600
        let m = Int((Double(s % 3600) / 60).rounded())
        if h > 0 { return String(format: "%d h %02d", h, m) }
        return "\(m) min"
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func date(full: String?, approx: String?) -> String {
        if let d = full {
            let p = d.split(separator: "-").map(String.init)
            if p.count == 3, let m = Int(p[1]), let day = Int(p[2]), m >= 1, m <= 12 {
                return "\(day) \(months[m - 1]) \(p[0])"
            }
        }
        if let a = approx {
            let p = a.split(separator: "-").map(String.init)
            if p.count >= 2, let m = Int(p[1]), m >= 1, m <= 12 { return "~\(months[m - 1]) \(p[0])" }
        }
        return ""
    }

    /// Theme lecture dates are either YYYY-MM-DD or YYYY-MM.
    static func looseDate(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        return s.count > 7 ? date(full: s, approx: nil) : date(full: nil, approx: s)
    }

    static func isArabic(_ s: String?) -> Bool {
        guard let s else { return false }
        var a = 0, l = 0
        for u in s.unicodeScalars {
            if (0x0600...0x06FF).contains(u.value) { a += 1 }
            else if (65...90).contains(u.value) || (97...122).contains(u.value) { l += 1 }
        }
        return a > l
    }

    static func arabicNumber(_ n: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(n).map { c in
            if let v = c.wholeNumberValue { return digits[v] }
            return c
        })
    }

    static func slug(_ s: String?) -> String {
        let lower = (s ?? "").lowercased()
        var out = ""
        var lastDash = false
        for u in lower.unicodeScalars {
            let ok = (97...122).contains(u.value) || (48...57).contains(u.value) || (0x0600...0x06FF).contains(u.value)
            if ok { out.unicodeScalars.append(u); lastDash = false }
            else if !lastDash { out.append("-"); lastDash = true }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(60))
    }

    static func youTubeURL(_ id: String, _ t: Double = 0) -> URL {
        let ts = t > 0 ? "&t=\(Int(t))s" : ""
        return URL(string: "https://www.youtube.com/watch?v=\(id)\(ts)")!
    }
}

/// A verse range like 73:6-9
struct VerseRange: Hashable {
    let surah: Int
    let from: Int
    let to: Int

    var keys: [String] { (from...max(from, min(to, from + 9))).map { "\(surah):\($0)" } }

    var arabicLabel: String {
        let r = from == to ? Fmt.arabicNumber(from) : "\(Fmt.arabicNumber(from))–\(Fmt.arabicNumber(to))"
        return "سورة \(Quran.arabic(surah)) \(r)"
    }

    var label: String {
        let r = from == to ? "\(from)" : "\(from)–\(to)"
        return "\(Quran.name(surah)) \(surah):\(r)"
    }

    static func parse(_ s: String?) -> [VerseRange] {
        guard let s else { return [] }
        return s.split(separator: ",").compactMap { part in
            let p = part.trimmingCharacters(in: .whitespaces)
            let halves = p.split(separator: ":")
            guard halves.count == 2, let sur = Int(halves[0]) else { return nil }
            let ab = halves[1].split(separator: "-")
            guard let a = Int(ab[0]) else { return nil }
            let b = ab.count > 1 ? (Int(ab[1]) ?? a) : a
            return VerseRange(surah: sur, from: a, to: b)
        }
    }
}
