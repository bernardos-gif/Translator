import Foundation

/// The Windows version a bottle reports to programs (set through `winecfg -v`).
enum WindowsVersion: String, Codable, CaseIterable, Identifiable, Hashable {
    case win11, win10, win81, win8, win7, winxp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .win11: return "Windows 11"
        case .win10: return "Windows 10"
        case .win81: return "Windows 8.1"
        case .win8: return "Windows 8"
        case .win7: return "Windows 7"
        case .winxp: return "Windows XP"
        }
    }
}

/// A program the user pinned to a bottle's launcher grid.
struct PinnedProgram: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Absolute macOS path to the .exe inside (or outside) the bottle.
    var path: String

    var url: URL { URL(fileURLWithPath: path) }
}

/// Settings stored next to each bottle as `bottle.json`.
struct BottleConfig: Codable, Hashable {
    var name: String
    var windowsVersion: WindowsVersion = .win10
    /// Faster thread synchronisation on macOS (WINEMSYNC / WINEESYNC).
    var msync: Bool = true
    /// Render at native Retina resolution instead of scaled.
    var retina: Bool = false
    /// Show Wine's own debug output in the log instead of silencing it.
    var verboseLogging: Bool = false
    var pinned: [PinnedProgram] = []
    var created: Date = Date()
}

/// A bottle is one isolated Windows environment (a WINEPREFIX) with its own C: drive and registry.
struct Bottle: Identifiable, Hashable {
    let url: URL
    var config: BottleConfig

    var id: URL { url }
    var configURL: URL { url.appendingPathComponent("bottle.json") }
    var driveC: URL { url.appendingPathComponent("drive_c") }

    /// Wine writes system.reg once `wineboot --init` has finished.
    var isInitialized: Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("system.reg").path)
    }
}

/// A Windows program currently running from this app.
struct RunningProgram: Identifiable {
    let id: UUID
    let name: String
    let bottleURL: URL
    let process: Process
}
