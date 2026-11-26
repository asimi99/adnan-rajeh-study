import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var lib
    @Environment(UserStore.self) private var store

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learn from Sh. Adnan Rajeh").font(.title2.weight(.bold))
                    Text("His khutbahs, lessons and reminders, organised so you can study a subject from start to finish or just browse. Tap any line of a lecture's notes and the video jumps to that moment.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            let cont = Array(store.continueWatching(lib).prefix(4))
            if !cont.isEmpty {
                Section("Continue watching") {
                    ForEach(cont) { e in
                        NavigationLink(value: Route.lecture(e.lecture.id, Double(e.progress.t))) { LectureRow(lecture: e.lecture, progress: e.progress) }
                    }
                }
            }

            Section("Study by subject") {
                NavigationLink(value: Route.themes) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Themes", systemImage: "square.grid.2x2").font(.headline)
                        Text("What he teaches on patience, marriage, purpose, justice and a hundred other subjects, with every lecture where it comes up.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Browse his teaching") {
                ForEach(Category.all) { c in
                    NavigationLink(value: Route.category(c.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(c.name, systemImage: c.symbol).font(.headline)
                            Text(c.blurb).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Start here")
    }
}

struct BrowseView: View {
    var body: some View {
        List {
            Section {
                ForEach(Category.all) { c in
                    NavigationLink(value: Route.category(c.id)) { Label(c.name, systemImage: c.symbol) }
                }
            }
            Section {
                NavigationLink(value: Route.years) { Label("By year", systemImage: "calendar") }
                NavigationLink(value: Route.who) { Label("About the Shaykh", systemImage: "person.text.rectangle") }
                NavigationLink(value: Route.halaqah) { Label("Tazkiyah Halaqah", systemImage: "headphones") }
            }
        }
        .navigationTitle("Browse")
    }
}

struct CategoryView: View {
    let categoryId: String
    @Environment(Library.self) private var lib

    struct Block: Identifiable {
        let title: String
        let groups: [SeriesGroup]
        var id: String { title }
    }

    var body: some View {
        let c = Category.named(categoryId)
        let items = lib.lectures(in: categoryId)
        let groups = Dictionary(grouping: items.filter { $0.s != nil }, by: { $0.s! })
            .map { SeriesGroup(slug: Fmt.slug($0.key), name: $0.key, category: categoryId, items: $0.value) }
        let single = items.filter { $0.s == nil }
        List {
            if let c {
                Section { Text(c.blurb).font(.callout).foregroundStyle(.secondary) }
            }
            ForEach(blocks(groups)) { b in
                Section(b.title) {
                    ForEach(b.groups) { g in
                        NavigationLink(value: Route.series(g.slug)) {
                            HStack {
                                Text(g.shortName(in: categoryId))
                                Spacer()
                                if let s = g.surah, g.name.contains("Surat ") {
                                    Text(Quran.arabic(s)).font(.arabic(17)).foregroundStyle(.secondary)
                                } else {
                                    Text("\(g.items.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !single.isEmpty {
                Section("Single talks") {
                    ForEach(single) { l in
                        NavigationLink(value: Route.lecture(l.id, 0)) { LectureRow(lecture: l) }
                    }
                }
            }
        }
        .navigationTitle(c?.name ?? "")
    }

    /// Same grouping as the site: tafseer by surah, Ramadan by year, the rest by latest year.
    private func blocks(_ groups: [SeriesGroup]) -> [Block] {
        let bySurah: (SeriesGroup, SeriesGroup) -> Bool = { ($0.surah ?? 999) < ($1.surah ?? 999) }
        switch categoryId {
        case "tafseer":
            let en = groups.filter { $0.name.hasPrefix("Tafseer: Surat ") }.sorted(by: bySurah)
            let ar = groups.filter { $0.name.hasPrefix("Arabic Tafsir: ") }.sorted(by: bySurah)
            let rest = groups.filter { !$0.name.hasPrefix("Tafseer: Surat ") && !$0.name.hasPrefix("Arabic Tafsir: ") }
                .sorted { $0.newest < $1.newest }
            return [Block(title: "Overviews", groups: rest), Block(title: "Surah by surah", groups: en),
                    Block(title: "Arabic tafsir, surah by surah", groups: ar)].filter { !$0.groups.isEmpty }
        case "ramadan":
            func yr(_ s: String) -> String {
                if let r = s.range(of: #"20\d\d"#, options: .regularExpression) { return String(s[r]) }
                return "0"
            }
            let years = Array(Set(groups.map { yr($0.name) })).sorted(by: >)
            return years.map { y in
                Block(title: y == "0" ? "Other" : "Ramadan \(y)",
                      groups: groups.filter { yr($0.name) == y }.sorted { $0.name < $1.name })
            }
        case "khaterah", "khutbah", "series":
            let sorted = groups.sorted { $0.newest < $1.newest }
            let years = Array(Set(sorted.map(\.latestYear))).sorted(by: >)
            return years.map { y in Block(title: y > 0 ? String(y) : "Other", groups: sorted.filter { $0.latestYear == y }) }
        default:
            return [Block(title: "Series", groups: groups.sorted { $0.newest < $1.newest })]
        }
    }
}

struct SeriesView: View {
    let slug: String
    @Environment(Library.self) private var lib
    @Environment(UserStore.self) private var store

    var body: some View {
        if let g = lib.seriesIndex[slug] {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if let s = g.surah {
                            Text("سورة \(Quran.arabic(s))").font(.arabic(26)).frame(maxWidth: .infinity)
                            Text("\(Quran.name(s)) · \(s)").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        Text(Category.named(g.category)?.name ?? "").font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                        Text(g.name).font(Fmt.isArabic(g.name) ? .arabic(22) : .title3.weight(.bold))
                        Text("\(g.items.count) lectures · \(g.hours.formatted()) hours").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(Array(g.ordered.enumerated()), id: \.element.id) { pair in
                        let l = pair.element
                        NavigationLink(value: Route.lecture(l.id, 0)) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(l.ep ?? (pair.offset + 1))").font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                                LectureRow(lecture: l, showSeries: false, progress: store.progress(l.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle(g.shortName(in: g.category))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("No such series", systemImage: "questionmark.folder")
        }
    }
}

struct YearsView: View {
    @Environment(Library.self) private var lib
    var body: some View {
        List(lib.years, id: \.self) { y in
            NavigationLink(value: Route.year(y)) {
                HStack {
                    Text(String(y)).font(.headline)
                    Spacer()
                    Text("\(lib.own.filter { $0.y == y }.count)").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("By year")
    }
}

struct YearView: View {
    let year: Int
    @Environment(Library.self) private var lib

    var body: some View {
        let items = lib.own.filter { $0.y == year }.sorted { $0.i < $1.i }
        List {
            ForEach(Category.all.filter { c in items.contains { $0.category == c.id } }) { c in
                let inCat = items.filter { $0.category == c.id }
                let series = orderedUnique(inCat.compactMap(\.s))
                Section(c.name) {
                    ForEach(series, id: \.self) { s in
                        NavigationLink(value: Route.series(Fmt.slug(s))) { Text(s) }
                    }
                    ForEach(inCat.filter { $0.s == nil }) { l in
                        NavigationLink(value: Route.lecture(l.id, 0)) { LectureRow(lecture: l) }
                    }
                }
            }
        }
        .navigationTitle(String(year))
    }

    private func orderedUnique(_ xs: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for x in xs where !seen.contains(x) { seen.insert(x); out.append(x) }
        return out
    }
}
