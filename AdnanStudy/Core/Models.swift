import Foundation

// MARK: - Catalog

struct Lecture: Decodable, Identifiable, Hashable {
    let id: String
    let t: String
    let d: Int?
    let cat: String
    let s: String?
    let ep: Int?
    let lab: String?
    let date: String?
    let ad: String?
    let g: Bool?
    let skip: Bool?
    let tx: Bool?
    let lang: String?
    let i: Int
    let sp: String?
    let dt: String?
    let y: Int?
    let sn: Int?
    let dup: String?

    static func == (a: Lecture, b: Lecture) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// The title shown in lists, same rule as the site.
    var title: String { s != nil ? (lab ?? dt ?? t) : (dt ?? t) }
    var series: String? { s }
    var dateText: String { Fmt.date(full: date, approx: ad) }
    var durationText: String { Fmt.duration(d) }

    var category: String {
        if cat.hasPrefix("ramadan") { return "ramadan" }
        if cat == "tafseer-ar" { return "tafseer" }
        if cat == "other" { return "khaterah" }
        return cat
    }

    var isOwn: Bool {
        !(g ?? false) && !(skip ?? false) && dup == nil &&
        !["course", "ramadan-taraweeh", "prayer/event"].contains(cat)
    }
}

struct DocEntry: Decodable {
    let id: String
    let w: Int?
    let sh: Int
}

// MARK: - Flexible tuple rows ([12, "text"])

struct TimedText: Decodable, Hashable {
    let t: Double
    let text: String
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        if (try? c.decodeNil()) == true { t = -1 } else { t = (try? c.decode(Double.self)) ?? -1 }
        text = (try? c.decode(String.self)) ?? ""
    }
}

struct ShardRecord: Decodable {
    let p: [TimedText]
    let ch: [TimedText]?
}

// MARK: - Notes

struct Verse: Decodable, Hashable {
    let ar: String
    let en: String
}

struct OutlineItem: Decodable, Hashable {
    let start: Double
    let end: Double
    let heading: String
    let gist: String?
    let verses: String?
    var isAside: Bool { ["Opening", "Outro", "Interlude"].contains(heading) }
}

struct NoteTheme: Decodable, Hashable {
    let theme: String
    let label: String?
    let start: Double?
    let end: Double?
    let weight: Int?
    let note: String?
}

struct NoteQuran: Decodable, Hashable {
    let ref: String
    let surah: String?
    let start: Double?
    let point: String?
    let conf: String?
    let keys: [String]?
}

struct HadithFull: Decodable, Hashable {
    let full_ar: String?
    let full_en: String?
    let ar_block: String?
    let en_block: String?
    let grade: String?
    let status: String?
    let sources: [String]?
}

struct NoteHadith: Decodable, Hashable {
    let gist: String?
    let source: String?
    let start: Double?
    let full: HadithFull?
}

struct LectureNotes: Decodable {
    let vc: String?
    let vck: [String]?
    let vt: [String: Verse]?
    let speaker: String?
    let speaker_note: String?
    let title: String?
    let one_line: String?
    let summary: String?
    let outline: [OutlineItem]?
    let themes: [NoteTheme]?
    let quran: [NoteQuran]?
    let hadith: [NoteHadith]?
    let takeaways: [String]?
}

// MARK: - Themes

struct TimeRef: Decodable, Hashable {
    let id: String
    let t: Double
}

struct ThemeSpan: Decodable, Hashable {
    let start: Double
    let end: Double
    let weight: Int?
    let note: String?
}

struct ThemeLecture: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let date: String?
    let series: String?
    let ep: Int?
    let spans: [ThemeSpan]
    let w: Int?
}

struct Cite: Decodable, Hashable {
    let id: String
    let start: Double
    let point: String?
}

struct ThemeQuran: Decodable, Hashable {
    let ref: String
    let surah: String?
    let keys: [String]?
    let cites: [Cite]?
}

struct ThemeHadith: Decodable, Hashable {
    let id: String
    let start: Double
    let gist: String
    let source: String?
}

struct SynthPoint: Decodable, Hashable {
    let text: String
    let refs: [TimeRef]?
}

struct SynthSub: Decodable, Hashable {
    let heading: String
    let points: [SynthPoint]
}

struct SynthSection: Decodable, Hashable {
    let heading: String
    let intro: String?
    let body: String?
    let subs: [SynthSub]?
}

struct Synth: Decodable, Hashable {
    let summary: String?
    let sections: [SynthSection]?
    let khutbah_seeds: [SynthPoint]?
}

struct Theme: Decodable, Hashable, Identifiable {
    let slug: String
    let label: String
    let n: Int
    let lectures: [ThemeLecture]
    let quran: [ThemeQuran]
    let hadith: [ThemeHadith]
    let synth: Synth?
    var id: String { slug }

    static func == (a: Theme, b: Theme) -> Bool { a.slug == b.slug }
    func hash(into h: inout Hasher) { h.combine(slug) }

    var shortLabel: String {
        var s = label.split(whereSeparator: { $0 == ":" || $0 == "(" }).first.map(String.init) ?? label
        for cut in [" vs ", " and other "] {
            if let r = s.range(of: cut) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

struct ThemeDomain: Decodable {
    let name: String
    let themes: [String]
}

struct ThemesFile: Decodable {
    let themes: [Theme]
    let domains: [ThemeDomain]
    let verses: [String: Verse]
}

// MARK: - About the Shaykh

struct WhoFormat: Decodable, Hashable {
    let name: String
    let n: Int
    let hours: Int
    let from: Int?
    let to: Int?
}

struct WhoCite: Decodable, Hashable {
    let id: String
    let t: Double
    let point: String?
}

struct WhoVerse: Decodable, Hashable {
    let ref: String
    let n: Int
    let ar: String
    let en: String
    let cites: [WhoCite]
}

struct WhoFact: Decodable, Hashable {
    let category: String
    let claim: String
    let refs: [TimeRef]?
    let confidence: String?
}

struct WhoThemeRef: Decodable, Hashable {
    let slug: String
    let label: String
    let n: Int
}

struct WhoDomain: Decodable {
    let name: String
    let themes: [WhoThemeRef]
}

struct WhoProfile: Decodable {
    let facts: [WhoFact]
}

struct WhoFile: Decodable {
    let formats: [WhoFormat]
    let span: [Int]?
    let total: Int
    let hours: Int
    let domains: [WhoDomain]
    let verses: [WhoVerse]
    let profile: WhoProfile?
    let noted: Int
}

// MARK: - Tazkiyah halaqah

struct TZTopic: Decodable, Hashable {
    let t: Double
    let title: String
    let gist: String
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = (try? c.decode(Double.self)) ?? 0
        title = (try? c.decode(String.self)) ?? ""
        gist = (try? c.decode(String.self)) ?? ""
    }
}

struct TZRecital: Decodable, Hashable {
    let t: Double
    let surah: Int
    let from: Int
    let to: Int
    let name: String
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = (try? c.decode(Double.self)) ?? 0
        surah = (try? c.decode(Int.self)) ?? 0
        from = (try? c.decode(Int.self)) ?? 0
        to = (try? c.decode(Int.self)) ?? 0
        name = (try? c.decode(String.self)) ?? ""
    }
    var label: String { "\(name) \(surah):\(from)\(to != from ? "–\(to)" : "")" }
}

struct TZLesson: Decodable, Hashable, Identifiable {
    let n: Int
    let date: String
    let min: Int
    let title: String
    let obj: [String]?
    let topics: [TZTopic]?
    let ex: [String]?
    let q: [TZRecital]?
    var id: Int { n }
}

struct TZUse: Decodable, Hashable {
    let t: Double
    let n: Int
    let instr: String?
    let feel: [String]?
    let usual: [String]?
    let should: [String]?
    let answers: [String]?
}

struct TZExercise: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let instr: String?
    let uses: [TZUse]
}

struct TZPhase: Decodable, Hashable {
    let r: [Int]
    let title: String
    let blurb: String
}

struct TZFile: Decodable {
    let L: [TZLesson]
    let EX: [TZExercise]
    let PH: [TZPhase]
}
