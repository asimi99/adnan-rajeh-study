import SwiftUI

struct SearchView: View {
    @Environment(Library.self) private var lib
    @State private var query = ""
    @State private var result: SearchResult?
    @State private var searching = false
    @State private var filter = "all"
    @State private var lastQuery = ""

    var body: some View {
        List {
            if searching {
                LoadingView(text: "Searching…")
            } else if let r = result {
                summary(r)
                filters(r)
                if filter == "all", !r.titles.isEmpty {
                    Section("Matching titles") {
                        ForEach(r.titles) { l in
                            NavigationLink(value: Route.lecture(l.id, 0)) { LectureRow(lecture: l) }
                        }
                    }
                }
                ForEach(r.hits.filter { filter == "all" || $0.lecture.category == filter }) { h in
                    Section {
                        NavigationLink(value: Route.lecture(h.lecture.id, 0)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(h.lecture.title).font(.headline)
                                Text([h.lecture.s.map { $0 + (h.lecture.ep.map { " · \($0)" } ?? "") }, h.lecture.dateText, h.lecture.durationText]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(h.moments) { m in
                            NavigationLink(value: Route.lecture(h.lecture.id, m.t)) {
                                HStack(alignment: .top, spacing: 10) {
                                    TimeChip(t: m.t)
                                    HighlightedText(text: m.snippet, terms: m.highlights).font(.callout)
                                }
                            }
                        }
                    }
                }
                if r.hits.isEmpty && r.titles.isEmpty {
                    Text("Nothing found in the transcribed lectures.").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Search every word he has said across the transcribed lectures, in English or Arabic. Each result opens the lecture at that moment.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Patience, tawakkul, صبر…")
        .onSubmit(of: .search) { run() }
        #if DEBUG
        .onAppear {
            if let q = Tour.pendingSearch { Tour.pendingSearch = nil; query = q; run() }
        }
        #endif
    }

    @ViewBuilder
    private func summary(_ r: SearchResult) -> some View {
        let tokens = SearchEngine.tokens(lastQuery)
        if tokens.isEmpty {
            Text("Type at least one word of three letters.").foregroundStyle(.secondary)
        } else {
            Text("\(r.hits.count) lectures with matching moments\(r.partial ? " (no lecture has every word, showing the closest)" : "")\(r.titles.isEmpty ? "" : " · \(r.titles.count) titles match")")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func filters(_ r: SearchResult) -> some View {
        let cats = Array(Set(r.hits.map(\.lecture.category)))
        if cats.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("all", "All")
                    ForEach(Category.all.filter { cats.contains($0.id) }) { c in chip(c.id, c.name) }
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
    }

    private func chip(_ id: String, _ name: String) -> some View {
        Button { filter = id } label: { Pill(text: name, strong: filter == id) }.buttonStyle(.plain)
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        lastQuery = q
        filter = "all"
        searching = true
        Task {
            result = await SearchEngine.run(q, in: lib)
            searching = false
        }
    }
}
