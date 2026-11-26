import Foundation

enum Remote {
    static let site = URL(string: "https://asimi99.github.io/adnan-rajeh-study/")!
    static let supabase = URL(string: "https://rxkitwtfgbhgyneapgfx.supabase.co")!
    /// Public publishable key, the same one the website ships. Row level security protects the data.
    static let anonKey = "sb_publishable_a_sszD017JtDTmQ5e_ERLQ_lW9z-e96"
    static let privacy = URL(string: "https://asimi99.github.io/adnan-rajeh-study/privacy.html")!
    static let terms = URL(string: "https://asimi99.github.io/adnan-rajeh-study/terms.html")!
    static let dataDeletion = URL(string: "https://asimi99.github.io/adnan-rajeh-study/data-deletion.html")!

    static func halaqahAudio(_ n: Int) -> URL {
        site.appendingPathComponent(String(format: "tz/c/L%02d.caf", n))
    }
}

/// Everything fetched from the site is kept on disk, so the app keeps working offline.
actor DataCache {
    static let shared = DataCache()

    let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("site-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var d = dir
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? d.setResourceValues(rv)
    }

    private func file(_ path: String) -> URL {
        dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "__"))
    }

    func isCached(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: file(path).path)
    }

    /// Fresh copies are used as is. Stale ones are refreshed, and kept if the network is down.
    func data(_ path: String, maxAge: TimeInterval = 60 * 60 * 6) async throws -> Data {
        let f = file(path)
        let mod = (try? FileManager.default.attributesOfItem(atPath: f.path))?[.modificationDate] as? Date
        if let mod, Date().timeIntervalSince(mod) < maxAge, let d = try? Data(contentsOf: f) {
            return d
        }
        do {
            var req = URLRequest(url: Remote.site.appendingPathComponent(path))
            req.timeoutInterval = 30
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (d, resp) = try await URLSession.shared.data(for: req)
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            try? d.write(to: f, options: .atomic)
            return d
        } catch {
            if let d = try? Data(contentsOf: f) { return d }
            throw error
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ path: String, maxAge: TimeInterval = 60 * 60 * 6) async throws -> T {
        let d = try await data(path, maxAge: maxAge)
        return try JSONDecoder().decode(T.self, from: d)
    }

    func sizeOnDisk() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(Int64(0)) { sum, u in
            sum + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }
}
