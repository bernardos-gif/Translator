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

    private static func sorted(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
