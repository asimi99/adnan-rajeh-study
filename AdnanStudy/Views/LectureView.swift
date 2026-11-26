import SwiftUI

struct LectureView: View {
    let id: String
    let startAt: Double

    @Environment(Library.self) private var lib
    @Environment(UserStore.self) private var store
    @Environment(Reminders.self) private var reminders
    @Environment(\.openURL) private var openURL

    @State private var player = YouTubeController()
    @State private var record: ShardRecord?
    @State private var notes: LectureNotes?
    @State private var verses: [String: Verse] = [:]
    @State private var loaded = false
    @State private var reflection = ""
    @State private var reflectionStatus = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var findText = ""
    @State private var found: [Moment]? = nil
    @State private var lastSave = Date.distantPast
    @State private var showRemind = false
    @State private var remindAt = Date().addingTimeInterval(60 * 60 * 3)
    @State private var remindStatus: String?
    @State private var activeT: Double?

    private var lecture: Lecture? { lib.byId[id] }

    private var start: Double {
        if startAt > 0 { return startAt }
        if let p = store.progress(id), p.isInProgress { return Double(p.t) }
        return 0
    }

    var body: some View {
        if let l = lecture {
            content(l)
        } else {
            ContentUnavailableView("Not in the catalog", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func content(_ l: Lecture) -> some View {
        VStack(spacing: 0) {
            YouTubePlayerView(videoId: l.id, start: start, controller: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(l)
                    actions(l)
                    mainContent(for: l)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(l) }
        .onAppear {
            reflection = store.reflection(id)
            player.onTime = { t, d in
                if Date().timeIntervalSince(lastSave) > 5, t > 5 {
                    lastSave = Date()
                    store.setProgress(id, t: t, d: d > 0 ? d : Double(l.d ?? 0))
                }
            }
        }
        .onDisappear {
            if player.current > 5 { store.setProgress(id, t: player.current, d: player.duration > 0 ? player.duration : Double(l.d ?? 0)) }
            player.pause()
        }
        .sheet(isPresented: $showRemind) { remindSheet(l) }
    }

    private func load(_ l: Lecture) async {
        guard !loaded else { return }
        let (r, n) = await lib.detail(for: id)
        let themes = await lib.loadThemes()
        record = r
        notes = n
        var v = themes?.verses ?? [:]
        for (k, x) in n?.vt ?? [:] { v[k] = x }
        verses = v
        loaded = true
    }

    private var displayTitle: (String, String?) {
        guard let l = lecture else { return ("", nil) }
        let base = l.title
        if let nt = notes?.title, base.range(of: #"^(verses?|ayat|part|episode|session|ep\.?)\s*\d"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let clean = nt.replacingOccurrences(of: #"\s*\(\d{1,3}\)"#, with: "", options: .regularExpression)
            return (clean, base)
        }
        return (base, nil)
    }

    // MARK: header

    @ViewBuilder
    private func header(_ l: Lecture) -> some View {
        let ranges = VerseRange.parse(notes?.vc)
        if !ranges.isEmpty {
            SurahHeader(ranges: ranges)
        } else if let sn = l.sn {
            VStack(spacing: 2) {
                Text("سورة \(Quran.arabic(sn))").font(.arabic(26))
                Text("\(Quran.name(sn)) · \(sn)").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        }
        VStack(alignment: .leading, spacing: 6) {
            if let g = lib.series(for: l) {
                NavigationLink(value: Route.series(g.slug)) {
                    Text(g.name + (l.ep.map { " · episode \($0)" } ?? ""))
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.leading)
                }
            } else if let c = Category.named(l.category) {
                Text(c.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
            }
            let t = displayTitle
            Text(t.0)
                .font(Fmt.isArabic(t.0) ? .arabic(24) : .title2.weight(.bold))
                .frame(maxWidth: .infinity, alignment: Fmt.isArabic(t.0) ? .trailing : .leading)
            HStack(spacing: 10) {
                if let sub = t.1 { Text(sub) }
                if !l.dateText.isEmpty { Text(l.dateText) }
                if !l.durationText.isEmpty { Text(l.durationText) }
                if l.lang == "ar" { Text("Arabic") }
            }
            .font(.footnote).foregroundStyle(.secondary)
            if l.sp == "unsure" {
                Text("Speaker not confirmed as Sh. Adnan").font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func actions(_ l: Lecture) -> some View {
        HStack(spacing: 10) {
            Button { openURL(Fmt.youTubeURL(l.id, player.current)) } label: {
                Label("YouTube", systemImage: "play.rectangle")
            }
            Button { showRemind = true } label: {
                Label("Remind me", systemImage: "bell")
            }
            ShareLink(item: Fmt.youTubeURL(l.id, player.current)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(Palette.accent)
        if let s = remindStatus {
            Text(s).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: body

    @ViewBuilder
    private func mainContent(for l: Lecture) -> some View {
        if let dup = l.dup {
            Card {
                Text("This upload is the same recording as another one. Notes and search live there.")
                NavigationLink("Open \(lib.title(for: dup))", value: Route.lecture(dup, 0))
            }
        } else if !(l.tx ?? false) {
            Card { Text("Not transcribed yet. Timestamps and search arrive when this recording is processed.").foregroundStyle(.secondary) }
            reflectionSection
        } else if !loaded {
            LoadingView()
        } else {
            if let n = notes { notesSections(n, l) }
            reflectionSection
            if let ch = record?.ch?.filter({ $0.t >= 0 }), !ch.isEmpty { chaptersSection(ch) }
            findSection
        }
    }

    private func jump(_ t: Double) -> some View {
        Button { activeT = t; player.seek(t) } label: { TimeChip(t: t) }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func notesSections(_ n: LectureNotes, _ l: Lecture) -> some View {
        if n.speaker == "guest" {
            Card { Text("Speaker appears to be a guest, not Sh. Adnan. \(n.speaker_note ?? "")").font(.callout) }
        }
        if let h = n.hadith, !h.isEmpty { narrations(h, full: l.cat == "khaterah" && h.contains { $0.full != nil }) }

        if let one = n.one_line, !one.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("IN ONE LINE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(one).font(.headline)
                if let s = n.summary, !s.isEmpty {
                    Text("SUMMARY").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                    ForEach(Array(s.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, p in
                        Text(p)
                    }
                }
            }
        }

        if let th = n.themes, !th.isEmpty { themeLinks(th) }

        if let o = n.outline, !o.isEmpty {
            SectionTitle(text: "Outline")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(o.enumerated()), id: \.offset) { _, item in
                    Button { if !item.isAside { activeT = item.start; player.seek(item.start) } } label: {
                        HStack(alignment: .top, spacing: 10) {
                            TimeChip(t: item.start, end: item.end)
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(VerseRange.parse(item.verses), id: \.self) { r in
                                    Text(r.arabicLabel + "  ·  " + r.label).font(.caption).foregroundStyle(Palette.accent)
                                }
                                Text(item.heading).font(.subheadline.weight(.semibold))
                                if let g = item.gist, !g.isEmpty { Text(g).font(.subheadline).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 6)
                        .background(activeT == item.start ? Palette.soft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .opacity(item.isAside ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .multilineTextAlignment(.leading)
                }
            }
        }

        if let keys = n.vck?.filter({ verses[$0] != nil }), !keys.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(keys, id: \.self) { k in
                        let seg = segment(for: k, in: n.outline ?? [])
                        VStack(alignment: .leading, spacing: 6) {
                            if let seg {
                                HStack { jump(seg.start); Text(seg.heading).font(.caption).foregroundStyle(.secondary) }
                            }
                            VerseBlock(label: VerseRange.parse(k).first.map { $0.arabicLabel + "  ·  " + $0.label } ?? k,
                                       arabic: verses[k]?.ar ?? "", english: verses[k]?.en ?? "")
                        }
                    }
                }.padding(.top, 8)
            } label: {
                Text("Verses he explains").font(.title3.weight(.semibold)).foregroundStyle(.primary)
            }
            .tint(Palette.accent)
        }

        if let q = n.quran, !q.isEmpty {
            SectionTitle(text: "Verses he cites")
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(q.enumerated()), id: \.offset) { _, v in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if let s = v.start { jump(s) }
                            Text("\(v.surah ?? "") \(v.ref)").font(.caption.weight(.semibold))
                            if let c = v.conf, c != "high" { Text("\(c) confidence").font(.caption2).foregroundStyle(.secondary) }
                        }
                        VerseBlock(label: "",
                                   arabic: (v.keys ?? []).compactMap { verses[$0]?.ar }.joined(separator: " "),
                                   english: (v.keys ?? []).compactMap { verses[$0]?.en }.joined(separator: " "))
                        if let p = v.point, !p.isEmpty { Text(p).font(.footnote).italic() }
                    }
                }
            }
        }

        if let t = n.takeaways, !t.isEmpty {
            SectionTitle(text: "What he asks of the listener")
            BulletList(items: t)
        }
    }

    private func segment(for key: String, in outline: [OutlineItem]) -> OutlineItem? {
        let p = key.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return outline.first { o in
            VerseRange.parse(o.verses).contains { $0.surah == p[0] && p[1] >= $0.from && p[1] <= $0.to }
        }
    }

    @ViewBuilder
    private func narrations(_ h: [NoteHadith], full: Bool) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(h.enumerated()), id: \.offset) { _, x in
                    VStack(alignment: .leading, spacing: 6) {
                        if let s = x.start { jump(s) }
                        if let f = x.full, full, let ar = f.full_ar ?? f.ar_block {
                            Text(ar).font(.arabic(19)).multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(f.full_en ?? f.en_block ?? "").font(.callout)
                            HStack {
                                if let g = f.grade, !g.isEmpty { Text(g) }
                                if f.status == "partial" { Text("chain partly found") }
                                if let u = f.sources?.first, let url = URL(string: u) { Link("Source", destination: url) }
                            }.font(.caption).foregroundStyle(.secondary)
                        } else {
                            if let ar = x.full?.ar_block { Text(ar).font(.arabic(17)).frame(maxWidth: .infinity, alignment: .trailing) }
                            Text(x.full?.en_block ?? x.gist ?? "").font(.callout)
                            if let s = x.source, !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.padding(.top, 8)
        } label: {
            Text("Narrations").font(.title3.weight(.semibold)).foregroundStyle(.primary)
        }
        .tint(Palette.accent)
    }

    @ViewBuilder
    private func themeLinks(_ th: [NoteTheme]) -> some View {
        let unique = uniqueThemes(th)
        if !unique.isEmpty {
            SectionTitle(text: "Themes")
            FlowLayout {
                ForEach(unique, id: \.theme) { t in
                    NavigationLink(value: Route.theme(t.theme)) {
                        Pill(text: lib.themes?.themes.first { $0.slug == t.theme }?.label ?? t.label ?? t.theme, strong: t.weight == 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func uniqueThemes(_ th: [NoteTheme]) -> [NoteTheme] {
        let known = Set(lib.themes?.themes.map(\.slug) ?? [])
        var seen = Set<String>()
        var out: [NoteTheme] = []
        for t in th where (known.isEmpty || known.contains(t.theme)) && !seen.contains(t.theme) {
            seen.insert(t.theme)
            out.append(t)
        }
        return out
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "My reflection")
            TextEditor(text: $reflection)
                .frame(minHeight: 110)
                .padding(6)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: reflection) { _, v in
                    reflectionStatus = ""
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard !Task.isCancelled else { return }
                        store.setReflection(id, v)
                        reflectionStatus = "Saved"
                    }
                }
            Text(reflection.isEmpty ? "What stayed with you, what you want to act on." : reflectionStatus)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chaptersSection(_ ch: [TimedText]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "YouTube chapters")
            ForEach(Array(ch.enumerated()), id: \.offset) { _, c in
                Button { activeT = c.t; player.seek(c.t) } label: {
                    HStack(spacing: 10) { TimeChip(t: c.t); Text(c.text).multilineTextAlignment(.leading); Spacer() }
                        .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }
    }

    private var findSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Find a moment in this lecture")
            HStack {
                TextField("Word or phrase", text: $findText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(runFind)
                Button("Find", action: runFind).buttonStyle(.borderedProminent).tint(Palette.accent)
            }
            if let found {
                if found.isEmpty {
                    Text("No match in this lecture.").foregroundStyle(.secondary)
                } else {
                    ForEach(found) { m in
                        Button { activeT = m.t; player.seek(m.t) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                TimeChip(t: m.t)
                                HighlightedText(text: m.snippet, terms: m.highlights).font(.callout)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }

    private func runFind() {
        let q = findText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let r = record else { return }
        found = SearchEngine.moments(in: r.p, terms: SearchEngine.tokens(q), raw: q.lowercased(), max: 40)
    }

    @ViewBuilder
    private func remindSheet(_ l: Lecture) -> some View {
        NavigationStack {
            Form {
                DatePicker("When", selection: $remindAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Section {
                    Button("Tonight at 9 pm") { remindAt = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? remindAt }
                    Button("Tomorrow morning") {
                        let tmr = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                        remindAt = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: tmr) ?? remindAt
                    }
                }
            }
            .navigationTitle("Remind me to finish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showRemind = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        let at = remindAt, t = player.current
                        Task {
                            let ok = await reminders.remind(lecture: l, at: at, from: t)
                            remindStatus = ok ? "Reminder set for \(at.formatted(date: .abbreviated, time: .shortened))." : "Turn on notifications in Settings to get reminders."
                            showRemind = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Bolds every search term inside a snippet.
struct HighlightedText: View {
    let text: String
    let terms: [String]

    var body: some View { Text(attributed) }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        let lower = text.lowercased()
        for term in terms where !term.isEmpty {
            var from = lower.startIndex
            while let r = lower.range(of: term, range: from..<lower.endIndex) {
                let start = lower.distance(from: lower.startIndex, to: r.lowerBound)
                let len = lower.distance(from: r.lowerBound, to: r.upperBound)
                let chars = a.characters
                if start + len <= chars.count {
                    let s = chars.index(chars.startIndex, offsetBy: start)
                    let e = chars.index(s, offsetBy: len)
                    a[s..<e].font = .body.weight(.bold)
                    a[s..<e].backgroundColor = Palette.soft
                }
                from = r.upperBound
            }
        }
        return a
    }
}
