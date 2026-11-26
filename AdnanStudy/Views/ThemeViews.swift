import SwiftUI

struct ThemesView: View {
    @Environment(Library.self) private var lib
    @State private var query = ""
    @State private var file: ThemesFile?

    var body: some View {
        Group {
            if let f = file {
                List {
                    if query.isEmpty {
                        Section {
                            Text("Pick a subject to read what he teaches on it and open every lecture where he takes it up.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(domains(f)) { d in
                            Section(d.name) {
                                ForEach(d.themes) { t in row(t) }
                            }
                        }
                    } else {
                        let q = query.lowercased()
                        let xs = f.themes.filter { $0.label.lowercased().contains(q) || $0.slug.contains(q) }
                        if xs.isEmpty {
                            Text("No theme by that name. Search finds any word he has said.").foregroundStyle(.secondary)
                        }
                        ForEach(xs) { t in row(t) }
                    }
                }
                .searchable(text: $query, prompt: "Patience, marriage, hypocrisy…")
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Themes")
        .task { file = await lib.loadThemes() }
    }

    private func row(_ t: Theme) -> some View {
        NavigationLink(value: Route.theme(t.slug)) {
            HStack {
                Text(t.shortLabel)
                Spacer()
                Text("\(t.n)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    struct DomainGroup: Identifiable {
        let name: String
        let themes: [Theme]
        var id: String { name }
    }

    private func domains(_ f: ThemesFile) -> [DomainGroup] {
        let by = Dictionary(f.themes.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        return f.domains.compactMap { d -> DomainGroup? in
            var name = d.name
            if name.hasPrefix("The self: ") { name = String(name.dropFirst("The self: ".count)) }
            name = name.prefix(1).uppercased() + name.dropFirst()
            let ts = d.themes.compactMap { by[$0] }.sorted { $0.n > $1.n }
            return ts.isEmpty ? nil : DomainGroup(name: name, themes: ts)
        }
    }
}

/// Text where verse references like 2:255 become tappable.
func verseLinked(_ text: String) -> AttributedString {
    var a = AttributedString(text)
    guard let rx = try? NSRegularExpression(pattern: #"\b(\d{1,3}):(\d{1,3})(?:-(\d{1,3}))?\b"#) else { return a }
    let ns = text as NSString
    for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
        guard let r = Range(m.range, in: text),
              let lo = AttributedString.Index(r.lowerBound, within: a),
              let hi = AttributedString.Index(r.upperBound, within: a) else { continue }
        a[lo..<hi].link = URL(string: "verse://ref/" + ns.substring(with: m.range).replacingOccurrences(of: ":", with: "_"))
    }
    return a
}

struct VerseSheet: Identifiable {
    let ref: String
    var id: String { ref }
}

struct TopicView: View {
    let slug: String
    @Environment(Library.self) private var lib
    @State private var file: ThemesFile?
    @State private var verse: VerseSheet?

    var body: some View {
        Group {
            if let f = file {
                if let t = f.themes.first(where: { $0.slug == slug }) {
                    content(t, f)
                } else {
                    ContentUnavailableView("No such theme yet", systemImage: "square.grid.2x2")
                }
            } else {
                LoadingView()
            }
        }
        .task { file = await lib.loadThemes() }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "verse" {
                verse = VerseSheet(ref: url.lastPathComponent.replacingOccurrences(of: "_", with: ":"))
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $verse) { v in
            let r = VerseRange.parse(v.ref).first
            ScrollView {
                VerseBlock(label: r.map { $0.arabicLabel + "  ·  " + $0.label } ?? v.ref,
                           arabic: (r?.keys ?? []).compactMap { file?.verses[$0]?.ar }.joined(separator: " "),
                           english: (r?.keys ?? []).compactMap { file?.verses[$0]?.en }.joined(separator: " "))
                    .padding(20)
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func content(_ t: Theme, _ f: ThemesFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(t.label).font(.title2.weight(.bold))

                if let s = t.synth {
                    if let sum = s.summary {
                        SectionTitle(text: "What he teaches")
                        ForEach(Array(sum.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, p in
                            Text(verseLinked(p))
                        }
                    }
                    ForEach(Array((s.sections ?? []).enumerated()), id: \.offset) { _, sec in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(sec.heading).font(.title3.weight(.bold)).padding(.top, 10)
                            if let i = sec.intro, !i.isEmpty { Text(i).font(.callout).foregroundStyle(.secondary) }
                            if let b = sec.body, !b.isEmpty { Text(b) }
                            ForEach(Array((sec.subs ?? []).enumerated()), id: \.offset) { _, sub in
                                Text(sub.heading).font(.headline).padding(.top, 4)
                                ForEach(Array(sub.points.enumerated()), id: \.offset) { _, pt in
                                    pointView(pt)
                                }
                            }
                        }
                    }
                    if let seeds = s.khutbah_seeds, !seeds.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(seeds.enumerated()), id: \.offset) { _, pt in pointView(pt) }
                            }.padding(.top, 8)
                        } label: {
                            Text("Khutbah angles from his material").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        }
                        .tint(Palette.accent)
                    }
                }

                SectionTitle(text: "Lectures", count: t.lectures.count)
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(t.lectures) { l in lectureBlock(l) }
                }

                if !t.quran.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(t.quran.enumerated()), id: \.offset) { _, q in
                                VStack(alignment: .leading, spacing: 6) {
                                    VerseBlock(label: "\(q.surah ?? "") \(q.ref)",
                                               arabic: (q.keys ?? []).compactMap { f.verses[$0]?.ar }.joined(separator: " "),
                                               english: (q.keys ?? []).compactMap { f.verses[$0]?.en }.joined(separator: " "))
                                    ForEach(Array((q.cites ?? []).enumerated()), id: \.offset) { _, c in
                                        refLink(id: c.id, t: c.start, note: c.point)
                                    }
                                }
                            }
                        }.padding(.top, 8)
                    } label: {
                        Text("Verses").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    }
                    .tint(Palette.accent)
                }

                if !t.hadith.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(t.hadith.enumerated()), id: \.offset) { _, h in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(h.gist)
                                    if let s = h.source, !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary) }
                                    refLink(id: h.id, t: h.start, note: nil)
                                }
                            }
                        }.padding(.top, 8)
                    } label: {
                        Text("Narrations").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    }
                    .tint(Palette.accent)
                }
            }
            .padding(16)
        }
        .navigationTitle(t.shortLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pointView(_ pt: SynthPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Palette.accent)
                Text(verseLinked(pt.text))
            }
            if let refs = pt.refs, !refs.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(refs.enumerated()), id: \.offset) { _, r in
                        NavigationLink(value: Route.lecture(r.id, r.t)) {
                            HStack(spacing: 4) {
                                TimeChip(t: r.t)
                                Text(shortName(r.id)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    private func shortName(_ id: String) -> String {
        guard let l = lib.byId[id] else { return id }
        let n = l.s.map { $0 + (l.ep.map { " \($0)" } ?? "") } ?? l.t
        return n.count > 40 ? String(n.prefix(38)) + "…" : n
    }

    private func refLink(id: String, t: Double, note: String?) -> some View {
        NavigationLink(value: Route.lecture(id, t)) {
            HStack(alignment: .top, spacing: 8) {
                TimeChip(t: t)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lib.title(for: id)).font(.footnote.weight(.medium)).multilineTextAlignment(.leading)
                    if let note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func lectureBlock(_ l: ThemeLecture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: Route.lecture(l.id, 0)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.title).font(Fmt.isArabic(l.title) ? .arabic(18) : .subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(l.w == 3 ? Palette.accent : .primary)
                    Text([l.series, Fmt.looseDate(l.date)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            ForEach(Array(l.spans.enumerated()), id: \.offset) { _, s in
                NavigationLink(value: Route.lecture(l.id, s.start)) {
                    HStack(alignment: .top, spacing: 8) {
                        TimeChip(t: s.start, end: s.end)
                        Text(s.note ?? "").font(.footnote).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
