import Foundation
import AVFoundation
import MediaPlayer
import Observation

/// Plays the Tazkiyah halaqah recordings, including from the lock screen and in the background.
/// Each lesson is saved on the phone the first time it plays, so it works offline after that.
@MainActor
@Observable
final class HalaqahPlayer {
    private(set) var lesson: TZLesson?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var current: Double = 0
    private(set) var duration: Double = 0
    var errorText: String?
    private(set) var downloaded: Set<Int> = []

    @ObservationIgnored weak var store: UserStore?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var lastSave = Date.distantPast

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("halaqah", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func localFile(_ n: Int) -> URL { dir.appendingPathComponent(String(format: "L%02d.caf", n)) }

    init() {
        refreshDownloads()
        setupRemoteCommands()
    }

    func refreshDownloads() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.dir.path)) ?? []
        downloaded = Set(files.compactMap { f in
            guard f.hasPrefix("L"), f.hasSuffix(".caf") else { return nil }
            return Int(f.dropFirst().dropLast(4))
        })
    }

    func download(_ n: Int) async throws {
        let dest = Self.localFile(n)
        if FileManager.default.fileExists(atPath: dest.path) { return }
        let (tmp, resp) = try await URLSession.shared.download(from: Remote.halaqahAudio(n))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        refreshDownloads()
    }

    func removeDownload(_ n: Int) {
        if lesson?.n == n { stop() }
        try? FileManager.default.removeItem(at: Self.localFile(n))
        refreshDownloads()
    }

    /// Plays a lesson from a given second. Without a time it resumes where you left off.
    func play(_ l: TZLesson, at t: Double? = nil) {
        if lesson?.n == l.n, player != nil {
            if let t { seek(t) }
            player?.play()
            return
        }
        stop()
        lesson = l
        errorText = nil
        isLoading = true
        var start = t
        if start == nil, let p = store?.halaqahProgress(l.n), p.t > 20, p.d == 0 || p.t < p.d - 30 { start = Double(p.t) }
        Task {
            do {
                try await download(l.n)
                guard lesson?.n == l.n else { return }
                startPlayer(url: Self.localFile(l.n), at: start ?? 0)
            } catch {
                isLoading = false
                errorText = "Couldn't load this recording. Check your connection."
            }
        }
    }

    private func startPlayer(url: URL, at t: Double) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        if t > 0 { p.seek(to: CMTime(seconds: t, preferredTimescale: 1)) }
        p.play()
        isPlaying = true
        isLoading = false
        updateNowPlaying()
    }

    private func tick(_ seconds: Double) {
        guard let p = player else { return }
        current = seconds
        let d = p.currentItem?.duration.seconds ?? 0
        if d.isFinite, d > 0 { duration = d }
        isPlaying = p.rate > 0
        if Date().timeIntervalSince(lastSave) > 5, seconds > 5, let l = lesson {
            lastSave = Date()
            store?.setHalaqahProgress(l.n, t: seconds, d: duration)
        }
        updateNowPlaying()
    }

    func toggle() {
        guard let p = player else { if let l = lesson { play(l) }; return }
        if p.rate > 0 { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
        updateNowPlaying()
    }

    func seek(_ t: Double) {
        player?.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 1))
        current = t
        updateNowPlaying()
    }

    func skip(_ by: Double) { seek(current + by) }

    func stop() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        if let l = lesson, current > 5 { store?.setHalaqahProgress(l.n, t: current, d: duration) }
        timeObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        current = 0
        duration = 0
        lesson = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlaying() {
        guard let l = lesson else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "\(l.n). \(l.title)",
            MPMediaItemPropertyArtist: "Sh. Adnan Rajeh",
            MPMediaItemPropertyAlbumTitle: "Tazkiyah Halaqah",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: current,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [30]
        c.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(30) }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(-15) }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent {
                MainActor.assumeIsolated { self?.seek(e.positionTime) }
            }
            return .success
        }
    }
}
