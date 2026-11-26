import SwiftUI

/// The halaqah is private to the group, behind the same code as the website.
struct HalaqahGate<Content: View>: View {
    @ViewBuilder var content: Content
    @AppStorage("tzok") private var unlocked = false
    @State private var code = ""
    @State private var wrong = false

    var body: some View {
        if unlocked {
            content
        } else {
            Form {
                Section {
                    Text("Enter the code to open.")
                    SecureField("Code", text: $code)
                        .keyboardType(.numberPad)
                        .onSubmit(check)
                    Button("Open", action: check)
                    if wrong { Text("Wrong code.").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Tazkiyah Halaqah")
        }
    }

    private func check() {
        if code == "0000" { unlocked = true } else { wrong = true; code = "" }
    }
}

struct HalaqahHomeView: View {
    @Environment(Library.self) private var lib
    @State private var data: TZFile?

    var body: some View {
        HalaqahGate {
            Group {
                if let d = data {
                    List {
                        Section {
                            Text("Weekly halaqah, \(d.L.first?.date ?? "") to \(d.L.last?.date ?? "").")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        NavigationLink(value: Route.halaqahLessons) {
                            HStack { Label("Lessons", systemImage: "headphones"); Spacer(); Text("\(d.L.count)").foregroundStyle(.secondary) }
                        }
                        NavigationLink(value: Route.halaqahExercises) {
                            HStack { Label("Exercises", systemImage: "figure.mind.and.body"); Spacer(); Text("\(d.EX.count)").foregroundStyle(.secondary) }
                        }
                    }
                } else { LoadingView() }
            }
            .navigationTitle("Tazkiyah Halaqah")
            .task { data = await lib.loadHalaqah() }
        }
    }
}

struct HalaqahLessonsView: View {
    @Environment(Library.self) private var lib
    @Environment(UserStore.self) private var store
    @Environment(HalaqahPlayer.self) private var player
    @State private var data: TZFile?

    var body: some View {
        HalaqahGate {
            Group {
                if let d = data {
                    List {
                        ForEach(d.PH, id: \.title) { ph in
                            Section {
                                Text(ph.blurb).font(.footnote).foregroundStyle(.secondary)
                                ForEach(d.L.filter { ph.r.count == 2 && $0.n >= ph.r[0] && $0.n <= ph.r[1] }) { l in
                                    NavigationLink(value: Route.halaqahLesson(l.n)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("\(l.n). \(l.title)").font(.subheadline.weight(.medium))
                                                Spacer()
                                                if player.downloaded.contains(l.n) {
                                                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.accent).font(.caption)
                                                }
                                            }
                                            Text("\(l.min) min · \(l.date)").font(.caption).foregroundStyle(.secondary)
                                            if let p = store.halaqahProgress(l.n), p.d > 0 {
                                                ProgressView(value: p.percent).tint(Palette.accent)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                Text("\(ph.title)  \(ph.r.first ?? 0)–\(ph.r.last ?? 0)")
                            }
                        }
                    }
                } else { LoadingView() }
            }
            .navigationTitle("Lessons")
            .task { data = await lib.loadHalaqah() }
        }
    }
}

struct HalaqahLessonView: View {
    let n: Int
    @Environment(Library.self) private var lib
    @Environment(HalaqahPlayer.self) private var player
    @State private var data: TZFile?
    @State private var downloading = false

    var body: some View {
        HalaqahGate {
            Group {
                if let d = data, let l = d.L.first(where: { $0.n == n }) {
                    content(l, d)
                } else if data != nil {
                    ContentUnavailableView("No such lesson", systemImage: "headphones")
                } else { LoadingView() }
            }
            .task { data = await lib.loadHalaqah() }
        }
    }

    private func content(_ l: TZLesson, _ d: TZFile) -> some View {
        let isThis = player.lesson?.n == l.n
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tazkiyah Halaqah · lesson \(l.n)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                Text(l.title).font(.title2.weight(.bold))
                Text("\(l.date) · \(l.min) min").font(.footnote).foregroundStyle(.secondary)

                Card {
                    HStack(spacing: 14) {
                        Button { isThis ? player.toggle() : player.play(l) } label: {
                            Image(systemName: isThis && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44)).foregroundStyle(Palette.accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if isThis && player.isLoading { Text("Loading…").font(.footnote) }
                            else if isThis { Text("\(Fmt.time(player.current)) / \(Fmt.time(player.duration))").font(.footnote.monospacedDigit()) }
                            else { Text("Plays in the background and on the lock screen").font(.footnote).foregroundStyle(.secondary) }
                            if let e = player.errorText, isThis { Text(e).font(.caption).foregroundStyle(.red) }
                        }
                        Spacer()
                        if player.downloaded.contains(l.n) {
                            Menu {
                                Button("Remove download", role: .destructive) { player.removeDownload(l.n) }
                            } label: { Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.accent) }
                        } else {
                            Button {
                                downloading = true
                                Task { try? await player.download(l.n); downloading = false }
                            } label: {
                                if downloading { ProgressView() } else { Image(systemName: "arrow.down.circle") }
                            }
                            .tint(Palette.accent)
                        }
                    }
                    if isThis, player.duration > 0 {
                        Slider(value: Binding(get: { player.current }, set: { player.seek($0) }), in: 0...player.duration)
                            .tint(Palette.accent)
                    }
                }

                if let o = l.obj, !o.isEmpty {
                    Text("WHAT THIS LESSON SETS OUT TO DO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    BulletList(items: o)
                }

                if let t = l.topics, !t.isEmpty {
                    SectionTitle(text: "Outline")
                    ForEach(Array(t.enumerated()), id: \.offset) { _, x in
                        Button { player.play(l, at: x.t) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                TimeChip(t: x.t)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(x.title).font(.subheadline.weight(.semibold))
                                    if !x.gist.isEmpty { Text(x.gist).font(.subheadline).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .multilineTextAlignment(.leading)
                    }
                }

                if let q = l.q, !q.isEmpty {
                    SectionTitle(text: "Quran recited")
                    FlowLayout {
                        ForEach(Array(q.enumerated()), id: \.offset) { _, r in
                            Button { player.play(l, at: r.t) } label: { Pill(text: r.label) }.buttonStyle(.plain)
                        }
                    }
                }

                let exs = (l.ex ?? []).compactMap { id in d.EX.first { $0.id == id } }
                if !exs.isEmpty {
                    SectionTitle(text: "Exercises in this lesson")
                    ForEach(exs) { e in
                        NavigationLink(value: Route.halaqahExercise(e.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.title).font(.subheadline.weight(.semibold))
                                if let i = e.instr { Text(i).font(.footnote).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    if let prev = d.L.first(where: { $0.n == l.n - 1 }) {
                        NavigationLink(value: Route.halaqahLesson(prev.n)) { Label("Lesson \(prev.n)", systemImage: "chevron.left") }
                    }
                    Spacer()
                    if let next = d.L.first(where: { $0.n == l.n + 1 }) {
                        NavigationLink(value: Route.halaqahLesson(next.n)) {
                            HStack { Text("Lesson \(next.n)"); Image(systemName: "chevron.right") }
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HalaqahExercisesView: View {
    @Environment(Library.self) private var lib
    @State private var data: TZFile?

    var body: some View {
        HalaqahGate {
            Group {
                if let d = data {
                    List(d.EX) { e in
                        NavigationLink(value: Route.halaqahExercise(e.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.title).font(.subheadline.weight(.semibold))
                                let ns = Array(Set(e.uses.map(\.n))).sorted()
                                Text(ns.count > 1 ? "Lessons " + ns.map(String.init).joined(separator: ", ") : "Lesson \(ns.first ?? 0)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let i = e.instr { Text(i).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
                            }
                        }
                    }
                } else { LoadingView() }
            }
            .navigationTitle("Exercises")
            .task { data = await lib.loadHalaqah() }
        }
    }
}

struct HalaqahExerciseView: View {
    let exerciseId: String
    @Environment(Library.self) private var lib
    @Environment(HalaqahPlayer.self) private var player
    @State private var data: TZFile?

    var body: some View {
        HalaqahGate {
            Group {
                if let d = data, let e = d.EX.first(where: { $0.id == exerciseId }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Tazkiyah Halaqah · Exercises").font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                            Text(e.title).font(.title2.weight(.bold))
                            if let i = e.instr {
                                Text("THE EXERCISE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(i).font(.headline)
                            }
                            ForEach(Array(e.uses.enumerated()), id: \.offset) { _, u in
                                let l = d.L.first { $0.n == u.n }
                                Card {
                                    Text("Lesson \(u.n): \(l?.title ?? "")").font(.headline)
                                    if let l {
                                        Button { player.play(l, at: u.t) } label: {
                                            Label("Play from where he set it (\(Fmt.time(u.t)))", systemImage: "play.circle")
                                        }
                                        .tint(Palette.accent)
                                    }
                                    if let i = u.instr, !i.isEmpty { Text(i) }
                                    labeled("What you might feel", u.feel)
                                    labeled("What people usually feel", u.usual)
                                    labeled("What to aim to feel", u.should)
                                    labeled("What the group said", u.answers)
                                    NavigationLink("Open lesson \(u.n)", value: Route.halaqahLesson(u.n))
                                }
                            }
                        }
                        .padding(16)
                    }
                    .navigationBarTitleDisplayMode(.inline)
                } else if data != nil {
                    ContentUnavailableView("No such exercise", systemImage: "figure.mind.and.body")
                } else { LoadingView() }
            }
            .task { data = await lib.loadHalaqah() }
        }
    }

    @ViewBuilder
    private func labeled(_ title: String, _ items: [String]?) -> some View {
        if let items, !items.isEmpty {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            BulletList(items: items)
        }
    }
}

/// Small bar above the tabs while a halaqah lesson is playing.
struct MiniPlayer: View {
    @Environment(HalaqahPlayer.self) private var player
    var openLesson: (Int) -> Void

    var body: some View {
        if let l = player.lesson {
            HStack(spacing: 12) {
                Button { openLesson(l.n) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(l.n). \(l.title)").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(player.isLoading ? "Loading…" : "\(Fmt.time(player.current)) / \(Fmt.time(player.duration))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3) }
                Button { player.stop() } label: { Image(systemName: "xmark") }
            }
            .tint(Palette.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
    }
}
