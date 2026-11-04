import Foundation

/// A Wine installation found on this Mac.
struct WineRuntime: Equatable {
    let wineURL: URL
    let source: String

    var binDir: URL { wineURL.deletingLastPathComponent() }

    var wineserverURL: URL? {
        let url = binDir.appendingPathComponent("wineserver")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Places Wine is commonly installed on macOS, in order of preference.
    private static var searchLocations: [(dir: String, source: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var locations: [(String, String)] = []
        for base in ["/Applications", "\(home)/Applications"] {
            locations.append(("\(base)/Wine Stable.app/Contents/Resources/wine/bin", "Wine Stable"))
            locations.append(("\(base)/Wine Staging.app/Contents/Resources/wine/bin", "Wine Staging"))
            locations.append(("\(base)/Wine Devel.app/Contents/Resources/wine/bin", "Wine Devel"))
        }
        locations.append(("/opt/homebrew/bin", "Homebrew"))
        locations.append(("/usr/local/bin", "Homebrew (Intel)"))
        locations.append(("/opt/local/bin", "MacPorts"))
        return locations
    }

    /// Finds Wine, honouring a user-chosen binary first.
    static func locate(customPath: String?) -> WineRuntime? {
        let fm = FileManager.default
        if let customPath, !customPath.isEmpty, fm.isExecutableFile(atPath: customPath) {
            return WineRuntime(wineURL: URL(fileURLWithPath: customPath), source: "Custom")
        }
        for location in searchLocations {
            // Wine 9+ ships a single `wine` binary; older macOS builds named it `wine64`.
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
        env["WINEDEBUG"] = bottle.config.verboseLogging ? "fixme-all" : "-all"
        // Stop Wine from creating .desktop/.app shortcuts all over the Mac.
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"
        if bottle.config.msync {
            env["WINEMSYNC"] = "1"
            env["WINEESYNC"] = "1"
        }
        // Make sure Wine can find its helper binaries (wineserver, etc.).
        let path = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(binDir.path):\(path)"
        return env
    }

    /// True on Apple Silicon Macs that still need Rosetta 2 (Wine's macOS builds are x86_64).
    static var needsRosetta: Bool {
        #if arch(arm64)
        return !FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
        #else
        return false
        #endif
    }
}
