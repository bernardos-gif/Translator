import Foundation

/// Where Translator keeps everything it manages.
enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Translator", isDirectory: true)
    }()

    static var bottles: URL { support.appendingPathComponent("Bottles", isDirectory: true) }
    /// The Wine build Translator downloads and manages itself.
    static var runtime: URL { support.appendingPathComponent("Runtime", isDirectory: true) }
    /// Helper tools (winetricks, cabextract, DXVK).
    static var tools: URL { support.appendingPathComponent("Tools", isDirectory: true) }
    static var downloads: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Translator/Downloads", isDirectory: true)
    }

    /// Tools that ship inside the .app bundle (built by CI).
    static var bundledTools: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Tools", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// DXVK's DLL folders (x32/, x64/): bundled with the app or downloaded during setup.
    static var dxvkRoot: URL? {
        let fm = FileManager.default
        for dir in [bundledTools, tools].compactMap({ $0 }) {
            let root = dir.appendingPathComponent("dxvk", isDirectory: true)
            if fm.fileExists(atPath: root.appendingPathComponent("x64").path) { return root }
        }
        return nil
    }

    /// First match for a helper tool: inside the app, then in Application Support.
    static func tool(_ name: String) -> URL? {
        let fm = FileManager.default
        for dir in [bundledTools, tools].compactMap({ $0 }) {
            let url = dir.appendingPathComponent(name)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}

/// A Wine installation found on this Mac.
struct WineRuntime: Equatable {
    let wineURL: URL
    let source: String
    var isManaged: Bool { source == WineRuntime.managedSource }

    static let managedSource = "Built-in"

    var binDir: URL { wineURL.deletingLastPathComponent() }
    /// The `wine` folder that contains bin/, lib/ and share/.
    var rootDir: URL { binDir.deletingLastPathComponent() }

    var wineserverURL: URL? {
        let url = binDir.appendingPathComponent("wineserver")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Whether this Wine build can run Vulkan (needed for DXVK).
    var supportsVulkan: Bool {
        let fm = FileManager.default
        let candidates = ["lib/libMoltenVK.dylib", "lib64/libMoltenVK.dylib", "lib/wine/x86_64-unix/winevulkan.so"]
        let hasMoltenVK = candidates.prefix(2).contains { fm.fileExists(atPath: rootDir.appendingPathComponent($0).path) }
        return hasMoltenVK
    }

    /// Places Wine is commonly installed on macOS, in order of preference.
    private static var searchLocations: [(dir: String, source: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var locations: [(String, String)] = []
        for base in ["/Applications", "\(home)/Applications"] {
            locations.append(("\(base)/Wine Staging.app/Contents/Resources/wine/bin", "Wine Staging"))
            locations.append(("\(base)/Wine Stable.app/Contents/Resources/wine/bin", "Wine Stable"))
            locations.append(("\(base)/Wine Devel.app/Contents/Resources/wine/bin", "Wine Devel"))
        }
        locations.append(("/opt/homebrew/bin", "Homebrew"))
        locations.append(("/usr/local/bin", "Homebrew (Intel)"))
        return locations
    }

    /// Finds the wine binary inside an extracted Wine build (any folder layout).
    static func findWineBinary(in root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else { return nil }
        var fallback: URL?
        for case let url as URL in enumerator {
            if enumerator.level > 6 { enumerator.skipDescendants(); continue }
            guard url.deletingLastPathComponent().lastPathComponent == "bin" else { continue }
            let name = url.lastPathComponent
            if name == "wine", fm.isExecutableFile(atPath: url.path) { return url }
            if name == "wine64", fm.isExecutableFile(atPath: url.path) { fallback = url }
        }
        return fallback
    }

    /// Finds Wine: a user-chosen binary first, then Translator's own copy, then system installs.
    static func locate(customPath: String?) -> WineRuntime? {
        let fm = FileManager.default
        if let customPath, !customPath.isEmpty, fm.isExecutableFile(atPath: customPath) {
            return WineRuntime(wineURL: URL(fileURLWithPath: customPath), source: "Custom")
        }
        if fm.fileExists(atPath: AppPaths.runtime.path), let wine = findWineBinary(in: AppPaths.runtime) {
            return WineRuntime(wineURL: wine, source: managedSource)
        }
        for location in searchLocations {
            for name in ["wine", "wine64"] {
                let path = (location.dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: path) {
                    return WineRuntime(wineURL: URL(fileURLWithPath: path), source: location.source)
                }
            }
        }
        return nil
    }

    /// Environment for every Wine process started in a bottle.
    func environment(for bottle: Bottle) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.url.path
        env["WINEDEBUG"] = bottle.config.verboseLogging ? "fixme-all,err+all" : "-all"
        // Don't litter the Mac with Linux-style menu shortcuts.
        var overrides = ["winemenubuilder.exe=d"]
        if bottle.config.dxvk {
            overrides.append("d3d9,d3d10core,d3d11,dxgi=n,b")
            env["DXVK_ASYNC"] = "1"
            env["DXVK_HUD"] = env["DXVK_HUD"] ?? "0"
        }
        env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        if bottle.config.msync {
            env["WINEMSYNC"] = "1"
            env["WINEESYNC"] = "1"
        }
        // Lets 32-bit games use up to 4 GB of memory, which prevents many out-of-memory crashes.
        env["WINE_LARGE_ADDRESS_AWARE"] = "1"
        // Keep Metal/Vulkan devices alive through window changes instead of crashing.
        env["MVK_CONFIG_RESUME_LOST_DEVICE"] = "1"
        env["MVK_ALLOW_METAL_FENCES"] = "1"
        env["WINE"] = wineURL.path
        if let wineserverURL { env["WINESERVER"] = wineserverURL.path }

        var path = [binDir.path]
        if let bundled = AppPaths.bundledTools { path.append(bundled.path) }
        path.append(AppPaths.tools.path)
        path.append(env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["PATH"] = path.joined(separator: ":")
        return env
    }

    /// True on Apple Silicon Macs that still need Rosetta 2 (Wine's macOS builds are Intel code).
    static var needsRosetta: Bool {
        #if arch(arm64)
        return !FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
        #else
        return false
        #endif
    }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
