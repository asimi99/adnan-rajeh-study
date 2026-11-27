#if DEBUG
import UIKit

/// Development aid: when Documents/tour.request exists at launch, the app walks through
/// its main screens and saves a screenshot of each into Documents/tour. Not in release builds.
enum Tour {
    static var pendingSearch: String?

    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var requestFile: URL { docs.appendingPathComponent("tour.request") }
    static var outDir: URL { docs.appendingPathComponent("tour", isDirectory: true) }
    static var requested: Bool { FileManager.default.fileExists(atPath: requestFile.path) }

    @MainActor
    static func snap(_ name: String) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? img.pngData()?.write(to: outDir.appendingPathComponent(name + ".png"))
    }

    static func log(_ s: String) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let f = outDir.appendingPathComponent("log.txt")
        let line = "\(Date()) \(s)\n"
        if let h = try? FileHandle(forWritingTo: f) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: f, atomically: true, encoding: .utf8)
        }
    }
}
#endif
