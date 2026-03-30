import Foundation

enum DebugLog {
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["AUTOTILE_DEBUG"] == "1"
    }

    private static var logURL: URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoTile", isDirectory: true)
        return base.appendingPathComponent("debug.log")
    }

    static func clear() {
        guard enabled else { return }
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }

    static func write(_ message: String) {
        guard enabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
            try? handle.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
