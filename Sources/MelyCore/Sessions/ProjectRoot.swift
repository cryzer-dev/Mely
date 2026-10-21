import Foundation

/// The project folder an IDE knows, from the folder `claude` runs in (often a subfolder).
public enum ProjectRoot {
    /// Nearest ancestor of `cwd` (itself included) holding one of `markers`, tried in order:
    /// all of the first marker's levels before the next marker. Stops at `stop` (the home
    /// folder): no project root there. Falls back to `cwd`.
    public static func find(from cwd: String, markers: [String], stop: String = NSHomeDirectory(),
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        for marker in markers {
            var dir = (cwd as NSString).standardizingPath
            while dir != "/" && dir != stop && !dir.isEmpty {
                if exists((dir as NSString).appendingPathComponent(marker)) { return dir }
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        return cwd
    }
}
