import SwiftUI

struct WhoView: View {
    @Environment(Library.self) private var lib
    @State private var who: WhoFile?
    @State private var themes: ThemesFile?

    private let causes = ["palestine", "syria", "activism", "muslims-in-the-west", "youth", "community", "justice"]
    private let factGroups = ["Teachers and influences", "Teaching method and aims", "Formative experiences", "Practices"]
    private let formatRoutes: [String: String] = [
        "Friday khutbahs": "khutbah", "Khaterahs": "khaterah", "Tafseer": "tafseer", "Arabic tafsir": "tafseer",
        "Seerah": "seerah", "Lecture series": "series", "Tazkiyah": "tazkiyah", "Ramadan talks": "ramadan",
    ]

    var body: some View {
        Group {
            if let w = who { content(w) } else { LoadingView() }
        }
        .navigationTitle("About the Shaykh")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            who = await lib.loadWho()
            themes = await lib.loadThemes()
        }
    }

    private func meta(_ f: WhoFormat) -> String {
        var s = "\(f.n) · \(f.hours) h"
        if let from = f.from {
            s += " · " + String(from)
            if let to = f.to, to != from { s += "–" + String(to) }
        }
        return s
    }

    private func content(_ w: WhoFile) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("IMAM · LONDON, ONTARIO").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                    Text("Sh. Adnan Rajeh").font(.title.weight(.bold))
                    Text("\(w.total.formatted()) recordings · \(w.hours.formatted()) hours")
                    if let s = w.span, s.count == 2 { Text("\(String(s[0])) to \(String(s[1]))") }
                    Text("\(w.noted) lectures annotated so far").foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Text("Built from his own words across the lectures. Every line opens the moment where he says it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("How he teaches") {
                ForEach(w.formats, id: \.name) { f in
                    NavigationLink(value: Route.category(formatRoutes[f.name] ?? "series")) {
                        HStack {
                            Text(f.name)
                            Spacer()
                            Text(meta(f)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("What he returns to") {
                ForEach(w.domains.compactMap { $0.themes.first }, id: \.slug) { t in
                    NavigationLink(value: Route.theme(t.slug)) {
                        HStack { Text(t.label); Spacer(); Text("\(t.n)").foregroundStyle(.secondary) }
                    }
                }
            }

            if let th = themes {
                let byS = Dictionary(th.themes.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
                Section("Causes he carries") {
                    ForEach(causes.compactMap { byS[$0] }) { t in
                        NavigationLink(value: Route.theme(t.slug)) {
                            HStack { Text(t.label); Spacer(); Text("\(t.n)").foregroundStyle(.secondary) }
                        }
                    }
                }
            }

            let facts = w.profile?.facts ?? []
            ForEach(factGroups, id: \.self) { g in
                let xs = facts.filter { $0.category == g }
                if !xs.isEmpty {
                    Section(g) {
                        ForEach(Array(xs.enumerated()), id: \.offset) { _, f in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(f.claim)
                                if let c = f.confidence, c != "high" { Text("\(c) confidence").font(.caption).foregroundStyle(.secondary) }
                                if let refs = f.refs, !refs.isEmpty {
                                    FlowLayout(spacing: 6) {
                                        ForEach(Array(refs.enumerated()), id: \.offset) { _, r in
                                            NavigationLink(value: Route.lecture(r.id, r.t)) { TimeChip(t: r.t) }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            Section {
                ForEach(w.verses, id: \.ref) { v in
                    VStack(alignment: .leading, spacing: 8) {
                        VerseBlock(label: (VerseRange.parse(v.ref).first.map { $0.arabicLabel + "  ·  " + $0.label } ?? v.ref) + "  ·  \(v.n) lectures",
                                   arabic: v.ar, english: v.en)
                        ForEach(Array(v.cites.enumerated()), id: \.offset) { _, c in
                            NavigationLink(value: Route.lecture(c.id, c.t)) {
                                HStack(alignment: .top, spacing: 8) {
                                    TimeChip(t: c.t)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lib.title(for: c.id)).font(.footnote.weight(.medium))
                                        if let p = c.point, !p.isEmpty { Text(p).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("The verses he returns to most")
            } footer: {
                Text("Counted across annotated lectures, leaving out the standard opening and closing verses of the khutbah.")
            }
        }
    }
}
