import Foundation
import Observation

/// Same shape the website stores, so progress and reflections sync both ways.
struct StudyProgress: Codable, Hashable {
    var t: Int
    var d: Int
    var at: Double

    var percent: Double { d > 0 ? min(1, Double(t) / Double(d)) : 0 }
    var isInProgress: Bool { t > 30 && (d == 0 || t < d - 60) }
}

struct ProgressEntry: Identifiable {
    let lecture: Lecture
    let progress: StudyProgress
    var id: String { lecture.id }
}

struct ReflectionEntry: Identifiable {
    let id: String
    let note: Reflection
}

struct Reflection: Codable, Hashable {
    var text: String
    var at: Double
}

struct UserData: Codable {
    var prog: [String: StudyProgress] = [:]
    var notes: [String: Reflection] = [:]
    var tz: [String: StudyProgress] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prog = (try? c.decodeIfPresent([String: StudyProgress].self, forKey: .prog)) ?? [:]
        notes = (try? c.decodeIfPresent([String: Reflection].self, forKey: .notes)) ?? [:]
        tz = (try? c.decodeIfPresent([String: StudyProgress].self, forKey: .tz)) ?? [:]
    }

    static func merge<V: Codable>(_ a: [String: V], _ b: [String: V], at: (V) -> Double) -> [String: V] {
        var o = a
        for (k, v) in b where o[k] == nil || at(v) > at(o[k]!) { o[k] = v }
        return o
    }

    func merged(with other: UserData) -> UserData {
        var m = UserData()
        m.prog = UserData.merge(prog, other.prog) { $0.at }
        m.notes = UserData.merge(notes, other.notes) { $0.at }
        m.tz = UserData.merge(tz, other.tz) { $0.at }
        return m
    }
}

private var nowMs: Double { Date().timeIntervalSince1970 * 1000 }

@MainActor
@Observable
final class UserStore {
    private(set) var data = UserData()
    @ObservationIgnored weak var account: Account?

    @ObservationIgnored private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("my-study.json")
    }()

    @ObservationIgnored private var pushTask: Task<Void, Never>?

    init() {
        if let d = try? Data(contentsOf: file), let u = try? JSONDecoder().decode(UserData.self, from: d) {
            data = u
        }
    }

    private func persist(sync: Bool = true) {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        guard sync, account?.session != nil else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    // MARK: progress

    func progress(_ id: String) -> StudyProgress? { data.prog[id] }

    func setProgress(_ id: String, t: Double, d: Double) {
        guard t > 5 else { return }
        data.prog[id] = StudyProgress(t: Int(t), d: Int(d), at: nowMs)
        persist()
    }

    func halaqahProgress(_ n: Int) -> StudyProgress? { data.tz["L\(n)"] }

    func setHalaqahProgress(_ n: Int, t: Double, d: Double) {
        guard t > 5 else { return }
        data.tz["L\(n)"] = StudyProgress(t: Int(t), d: Int(d), at: nowMs)
        persist()
    }

    /// Lectures started but not finished, most recent first.
    func continueWatching(_ lib: Library) -> [ProgressEntry] {
        recent(lib).filter { $0.progress.isInProgress }
    }

    func recent(_ lib: Library) -> [ProgressEntry] {
        var out: [ProgressEntry] = []
        for (id, p) in data.prog {
            if let l = lib.byId[id], !(l.g ?? false) { out.append(ProgressEntry(lecture: l, progress: p)) }
        }
        return out.sorted { $0.progress.at > $1.progress.at }
    }

    // MARK: saved lectures (kept on this phone)

    private(set) var saved: [String] = UserDefaults.standard.stringArray(forKey: "saved") ?? []

    func isSaved(_ id: String) -> Bool { saved.contains(id) }

    func toggleSaved(_ id: String) {
        if let i = saved.firstIndex(of: id) { saved.remove(at: i) } else { saved.insert(id, at: 0) }
        UserDefaults.standard.set(saved, forKey: "saved")
    }

    // MARK: reflections

    func reflection(_ id: String) -> String { data.notes[id]?.text ?? "" }

    func setReflection(_ id: String, _ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data.notes.removeValue(forKey: id)
        } else {
            data.notes[id] = Reflection(text: text, at: nowMs)
        }
        persist()
    }

    var reflections: [ReflectionEntry] {
        data.notes.map { ReflectionEntry(id: $0.key, note: $0.value) }.sorted { $0.note.at > $1.note.at }
    }

    // MARK: sync

    func pull() async {
        guard let account, let remote = await account.fetchUserData() else { return }
        data = data.merged(with: remote)
        persist(sync: false)
        await push()
    }

    func push() async {
        await account?.saveUserData(data)
    }

    /// Erases progress and reflections here and in the account.
    func eraseAll() async {
        data = UserData()
        persist(sync: false)
        await push()
    }

    /// Called on sign out so the next person on this phone starts clean.
    func clearLocal() {
        data = UserData()
        persist(sync: false)
    }
}
