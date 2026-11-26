import Foundation
import Observation

struct Category: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let symbol: String

    static let all: [Category] = [
        Category(id: "khutbah", name: "Friday Khutbahs", blurb: "His Friday sermons, grouped into the series he preached them in.", symbol: "building.columns"),
        Category(id: "series", name: "Lecture Series", blurb: "Multi-part courses, from the Names of Allah to the Values of Islam.", symbol: "books.vertical"),
        Category(id: "tazkiyah", name: "Tazkiyah", blurb: "The weekly halaqah on purifying the self.", symbol: "heart.text.square"),
        Category(id: "tafseer", name: "Tafseer", blurb: "The Quran explained surah by surah, in English and Arabic.", symbol: "book"),
        Category(id: "seerah", name: "Seerah", blurb: "The life of the Prophet ﷺ, episode by episode.", symbol: "map"),
        Category(id: "ramadan", name: "Ramadan", blurb: "Nightly reflections, post-Fajr lessons and preparation, year by year.", symbol: "moon.stars"),
        Category(id: "khaterah", name: "Khaterahs", blurb: "Short reminders after Isha, most built around one hadith.", symbol: "quote.bubble"),
    ]

    static func named(_ id: String) -> Category? { all.first { $0.id == id } }
}

struct SeriesGroup: Identifiable, Hashable {
    let slug: String
    let name: String
    let category: String
    var items: [Lecture]
    var id: String { slug }

    static func == (a: SeriesGroup, b: SeriesGroup) -> Bool { a.slug == b.slug }
    func hash(into h: inout Hasher) { h.combine(slug) }

    /// Episode order when most items are numbered, newest first otherwise.
    var ordered: [Lecture] {
        let numbered = items.filter { $0.ep != nil }.count
        if Double(numbered) > Double(items.count) / 2 {
            return items.sorted { ($0.ep ?? Int.max, -$0.i) < ($1.ep ?? Int.max, -$1.i) }
        }
        return items.sorted { $0.i > $1.i }
    }

    var surah: Int? { items.first(where: { $0.sn != nil })?.sn }
    var newest: Int { items.map(\.i).min() ?? 0 }
    var latestYear: Int { items.compactMap(\.y).max() ?? 0 }
    var hours: Double { (Double(items.compactMap(\.d).reduce(0, +)) / 360).rounded() / 10 }

    /// Short card label, same trimming as the site.
    func shortName(in category: String) -> String {
        var s = name
        for p in ["Tafseer: Surat ", "Arabic Tafsir: Surat "] where s.hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        if category == "ramadan" {
            if let r = s.range(of: #"^Ramadan 20\d\d: "#, options: .regularExpression) { s.removeSubrange(r) }
            if let r = s.range(of: #" \(20\d\d\)$"#, options: .regularExpression) { s.removeSubrange(r) }
        } else if let r = s.range(of: #" \(20\d\d(–20\d\d)?\)$"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        return s
    }
}

enum LoadState: Equatable {
    case idle, loading, ready, failed(String)
}

@MainActor
@Observable
final class Library {
    var state: LoadState = .idle
    private(set) var catalog: [Lecture] = []
    private(set) var byId: [String: Lecture] = [:]
    private(set) var own: [Lecture] = []
    private(set) var seriesIndex: [String: SeriesGroup] = [:]
    private(set) var docs: [DocEntry] = []
    private(set) var docIndex: [String: Int] = [:]

    private(set) var themes: ThemesFile?
    private(set) var who: WhoFile?
    private(set) var halaqah: TZFile?

    private var shards: [Int: [String: ShardRecord]] = [:]
    private var notes: [Int: [String: LectureNotes]] = [:]

    var offlineProgress: Double? = nil

    func load() async {
        if state == .ready || state == .loading { return }
        state = .loading
        do {
            async let cat = DataCache.shared.decode([Lecture].self, "data/catalog.json")
            async let dc = DataCache.shared.decode([DocEntry].self, "data/docs.json")
            let (c, d) = try await (cat, dc)
            ingest(catalog: c, docs: d)
            state = .ready
        } catch {
            state = .failed("Couldn't load the library. Check your connection and try again.")
        }
    }

    private func ingest(catalog c: [Lecture], docs d: [DocEntry]) {
        catalog = c.sorted { $0.i < $1.i }
        byId = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        own = catalog.filter(\.isOwn)
        var idx: [String: SeriesGroup] = [:]
        for l in own {
            guard let s = l.s else { continue }
            let k = Fmt.slug(s)
            if idx[k] == nil { idx[k] = SeriesGroup(slug: k, name: s, category: l.category, items: []) }
            idx[k]?.items.append(l)
        }
        seriesIndex = idx
        docs = d
        docIndex = Dictionary(d.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
    }

    func lectures(in category: String) -> [Lecture] { own.filter { $0.category == category } }

    func series(for lecture: Lecture) -> SeriesGroup? {
        guard let s = lecture.s else { return nil }
        return seriesIndex[Fmt.slug(s)]
    }

    var years: [Int] { Array(Set(own.compactMap(\.y))).sorted(by: >) }

    // MARK: lazily loaded files

    func loadThemes() async -> ThemesFile? {
        if let themes { return themes }
        themes = try? await DataCache.shared.decode(ThemesFile.self, "data/themes.json")
        return themes
    }

    func loadWho() async -> WhoFile? {
        if let who { return who }
        who = try? await DataCache.shared.decode(WhoFile.self, "data/who.json")
        return who
    }

    func loadHalaqah() async -> TZFile? {
        if let halaqah { return halaqah }
        halaqah = try? await DataCache.shared.decode(TZFile.self, "data/tz.json")
        return halaqah
    }

    func shard(_ n: Int) async -> [String: ShardRecord] {
        if let s = shards[n] { return s }
        let s = (try? await DataCache.shared.decode([String: ShardRecord].self, "data/sh/\(n).json", maxAge: 60 * 60 * 24 * 3)) ?? [:]
        shards[n] = s
        return s
    }

    func notesShard(_ n: Int) async -> [String: LectureNotes] {
        if let s = notes[n] { return s }
        let s = (try? await DataCache.shared.decode([String: LectureNotes].self, "data/notes/\(n).json", maxAge: 60 * 60 * 24)) ?? [:]
        notes[n] = s
        return s
    }

    /// Transcript paragraphs and annotated notes for one lecture.
    func detail(for id: String) async -> (ShardRecord?, LectureNotes?) {
        guard let di = docIndex[id] else { return (nil, nil) }
        let n = docs[di].sh
        async let sh = shard(n)
        async let no = notesShard(n)
        let (s, o) = await (sh, no)
        return (s[id], o[id])
    }

    func title(for id: String) -> String { byId[id]?.title ?? id }

    // MARK: offline

    /// Downloads every notes and transcript file so the whole library works without a connection.
    func downloadEverything() async {
        let shardIds = Array(Set(docs.map(\.sh))).sorted()
        var paths = ["data/catalog.json", "data/docs.json", "data/themes.json", "data/who.json", "data/tz.json"]
        for n in shardIds { paths.append("data/notes/\(n).json"); paths.append("data/sh/\(n).json") }
        offlineProgress = 0
        var done = 0
        for p in paths {
            _ = try? await DataCache.shared.data(p, maxAge: 60 * 60 * 24)
            done += 1
            offlineProgress = Double(done) / Double(paths.count)
        }
        offlineProgress = nil
        UserDefaults.standard.set(Date(), forKey: "offlineSavedAt")
    }
}
