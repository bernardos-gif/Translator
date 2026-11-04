import Foundation
import UniformTypeIdentifiers

/// Windows utilities bundled with Wine.
enum WineTool: String, CaseIterable, Identifiable {
    case winecfg, controlPanel, uninstaller, registry, taskManager, commandPrompt, explorer

    var id: String { rawValue }

    var command: String {
        switch self {
        case .winecfg: return "winecfg"
        case .controlPanel: return "control"
        case .uninstaller: return "uninstaller"
        case .registry: return "regedit"
        case .taskManager: return "taskmgr"
        case .commandPrompt: return "cmd"
        case .explorer: return "explorer"
        }
    }

    var title: String {
        switch self {
        case .winecfg: return "Wine Configuration"
        case .controlPanel: return "Control Panel"
        case .uninstaller: return "Uninstall Programs"
        case .registry: return "Registry Editor"
        case .taskManager: return "Task Manager"
        case .commandPrompt: return "Command Prompt"
        case .explorer: return "File Explorer"
        }
    }

    var subtitle: String {
        switch self {
        case .winecfg: return "Audio, graphics, drives, DLL overrides"
        case .controlPanel: return "Game controllers, internet settings"
        case .uninstaller: return "Remove installed programs"
        case .registry: return "Edit Windows settings directly"
        case .taskManager: return "See and end running processes"
        case .commandPrompt: return "A Windows command line"
        case .explorer: return "Browse this bottle's files"
        }
    }

    var symbol: String {
        switch self {
        case .winecfg: return "gearshape"
        case .controlPanel: return "slider.horizontal.3"
        case .uninstaller: return "trash"
        case .registry: return "list.bullet.indent"
        case .taskManager: return "chart.bar"
        case .commandPrompt: return "terminal"
        case .explorer: return "folder"
        }
    }
}

enum WindowsFileTypes {
    static let extensions = ["exe", "msi", "bat", "cmd", "lnk"]

    static var all: [UTType] {
        extensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func isWindowsFile(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// Looks for installed programs inside a bottle's C: drive.
enum ProgramScanner {
    private static let roots = ["Program Files", "Program Files (x86)"]

    /// Folders that only contain Windows/Wine plumbing.
    private static let skippedFolders: Set<String> = [
        "common files", "internet explorer", "windows nt", "windows media player",
        "windowspowershell", "microsoft.net", "reference assemblies", "msbuild",
    ]

    /// Executables that are almost never what the user wants to launch.
    private static let skippedNameFragments = [
        "unins", "uninst", "setup", "install", "update", "crash", "report", "helper",
        "redist", "vcredist", "vc_redist", "dxsetup", "dotnet", "service", "elevate",
    ]

    static func scan(driveC: URL, maxDepth: Int = 4, limit: Int = 300) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        for root in roots {
            let rootURL = driveC.appendingPathComponent(root, isDirectory: true)
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    if enumerator.level >= maxDepth || skippedFolders.contains(name) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard url.pathExtension.lowercased() == "exe" else { continue }
                if skippedNameFragments.contains(where: { name.contains($0) }) { continue }
                results.append(url)
                if results.count >= limit { return sorted(results) }
            }
        }
        return sorted(results)
    }

    private static let genericNames: Set<String> = [
        "launcher", "launch", "game", "start", "client", "app", "main", "run", "play", "bin",
        "win32", "win64", "x64", "x86", "shipping", "release",
    ]

    /// A friendly name: the file name, or its folder's name when the file name is generic.
    static func displayName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let normalized = base.lowercased()
            .replacingOccurrences(of: "-win64-shipping", with: "")
            .replacingOccurrences(of: "_", with: "")
        if genericNames.contains(normalized) || normalized.count <= 2 {
            var folder = url.deletingLastPathComponent()
            while genericNames.contains(folder.lastPathComponent.lowercased()) || folder.lastPathComponent.lowercased() == "binaries" {
                folder = folder.deletingLastPathComponent()
            }
            let name = folder.lastPathComponent
            if !name.isEmpty, !name.lowercased().hasPrefix("program files") { return name }
        }
        if base.hasSuffix("-Win64-Shipping") { return String(base.dropLast("-Win64-Shipping".count)) }
        return base
    }

    private static func sorted(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
