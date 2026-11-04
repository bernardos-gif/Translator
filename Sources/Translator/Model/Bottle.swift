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
    /// Translate DirectX 9–11 through Vulkan → Metal (DXVK) for better game performance.
    var dxvk: Bool = false
    /// Show Wine's own debug output in the log instead of silencing it.
    var verboseLogging: Bool = false
    var pinned: [PinnedProgram] = []
    var hidden: [String] = []
    var installedComponents: [String] = []
    var created: Date = Date()

    init(name: String, windowsVersion: WindowsVersion = .win10) {
        self.name = name
        self.windowsVersion = windowsVersion
    }

    // Decode leniently so bottles made by older versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        windowsVersion = try c.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion) ?? .win10
        msync = try c.decodeIfPresent(Bool.self, forKey: .msync) ?? true
        retina = try c.decodeIfPresent(Bool.self, forKey: .retina) ?? false
        dxvk = try c.decodeIfPresent(Bool.self, forKey: .dxvk) ?? false
        verboseLogging = try c.decodeIfPresent(Bool.self, forKey: .verboseLogging) ?? false
        pinned = try c.decodeIfPresent([PinnedProgram].self, forKey: .pinned) ?? []
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
        installedComponents = try c.decodeIfPresent([String].self, forKey: .installedComponents) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
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
    let path: String
    let bottleURL: URL
    let process: Process
}

/// An entry in the library: an installed or pinned program in some bottle.
struct LibraryItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let bottleURL: URL
    let bottleName: String
    let isPinned: Bool

    var id: String { bottleURL.path + "|" + url.path }
}
