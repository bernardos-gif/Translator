import AppKit
import Foundation
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case library
    case bottle(URL)
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var runtime: WineRuntime?
    @Published private(set) var bottles: [Bottle] = []
    @Published var sidebar: SidebarItem? = .library
    @Published private(set) var running: [RunningProgram] = []
    @Published private(set) var programs: [URL: [URL]] = [:]
    @Published private(set) var scanning: Set<URL> = []
    @Published private(set) var busyBottles: Set<URL> = []
    @Published private(set) var busyMessage: [URL: String] = [:]
    @Published private(set) var logText = ""
    @Published var showLog = false
    @Published var showNewBottle = false
    @Published var errorMessage: String?
    @Published var toast: String?

    /// Files opened from Finder before Wine or a bottle was ready.
    private var pendingOpens: [URL] = []
    private let defaults = UserDefaults.standard
    private let maxLogCharacters = 200_000

    var setupCompleted: Bool {
        get { defaults.bool(forKey: "setupCompleted") }
        set {
            defaults.set(newValue, forKey: "setupCompleted")
            objectWillChange.send()
        }
    }

    var customWinePath: String {
        get { defaults.string(forKey: "customWinePath") ?? "" }
        set {
            defaults.set(newValue, forKey: "customWinePath")
            refreshRuntime()
        }
    }

    /// Bottle used for .exe files opened from Finder.
    var defaultBottleURL: URL? {
        get { defaults.url(forKey: "defaultBottle") }
        set {
            defaults.set(newValue, forKey: "defaultBottle")
            objectWillChange.send()
        }
    }

    var rootURL: URL { AppPaths.bottles }

    /// Show the setup wizard until Wine is available and first-run setup has finished.
    var needsSetup: Bool { runtime == nil || !setupCompleted }

    private init() {
        refreshRuntime()
        loadBottles()
    }

    var selectedBottle: Bottle? {
        if case .bottle(let url) = sidebar { return bottle(for: url) }
        return nil
    }

    func bottle(for url: URL) -> Bottle? {
        bottles.first { $0.url == url }
    }

    // MARK: - Wine

    func refreshRuntime() {
        runtime = WineRuntime.locate(customPath: defaults.string(forKey: "customWinePath"))
        if runtime != nil { flushPendingOpens() }
    }

    func chooseWineBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose the wine (or wine64) binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            customWinePath = url.path
            if runtime?.source != "Custom" {
                errorMessage = "That file isn't an executable Wine binary."
            }
        }
    }

    // MARK: - Bottles

    func loadBottles() {
        let fm = FileManager.default
        try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let dirs = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        bottles = dirs.compactMap { dir in
            let configURL = dir.appendingPathComponent("bottle.json")
            guard let data = try? Data(contentsOf: configURL),
                  let config = try? JSONDecoder().decode(BottleConfig.self, from: data) else { return nil }
            return Bottle(url: dir, config: config)
        }
        .sorted { $0.config.created < $1.config.created }

        if case .bottle(let url) = sidebar, bottle(for: url) == nil {
            sidebar = .library
        }
        for bottle in bottles where programs[bottle.url] == nil {
            Task { await refreshPrograms(bottle.url) }
        }
    }

    private func save(_ bottle: Bottle) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(bottle.config).write(to: bottle.configURL, options: .atomic)
        } catch {
            errorMessage = "Couldn't save bottle settings: \(error.localizedDescription)"
        }
    }

    /// Changes a bottle's settings, saves them, and applies Wine-side changes when needed.
    func updateConfig(_ url: URL, _ change: (inout BottleConfig) -> Void) {
        guard let index = bottles.firstIndex(where: { $0.url == url }) else { return }
        let old = bottles[index].config
        change(&bottles[index].config)
        let bottle = bottles[index]
        save(bottle)

        if old.windowsVersion != bottle.config.windowsVersion {
            Task { await applyWindowsVersion(bottle) }
        }
        if old.retina != bottle.config.retina {
            Task { await applyRetina(bottle) }
        }
        if !old.dxvk && bottle.config.dxvk {
            Task { await installDXVK(in: bottle.url) }
        }
    }

    /// Creates a bottle and initialises Windows inside it. Returns once it's ready.
    @discardableResult
    func createBottle(name: String, version: WindowsVersion, select: Bool = true) async -> Bottle? {
        guard runtime != nil else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? "New Bottle" : trimmed
        let folderName = displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        var url = rootURL.appendingPathComponent(folderName, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = rootURL.appendingPathComponent("\(folderName) \(counter)", isDirectory: true)
            counter += 1
        }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Couldn't create the bottle folder: \(error.localizedDescription)"
            return nil
        }

        let bottle = Bottle(url: url, config: BottleConfig(name: displayName, windowsVersion: version))
        save(bottle)
        bottles.append(bottle)
        if select { sidebar = .bottle(url) }
        if defaultBottleURL == nil { defaultBottleURL = url }

        setBusy(url, "Setting up Windows… this takes about a minute the first time")
        let status = await runAndWait(["wineboot", "--init"], in: bottle, label: "wineboot")
        if status != 0 {
            log("⚠️ wineboot finished with code \(status). The bottle may still work; check the log.\n")
        }
        // wineboot returns before the prefix is fully written; wait for wineserver to settle.
        await waitForWineserver(bottle)
        await applyWindowsVersion(bottle)
        if bottle.config.retina { await applyRetina(bottle) }
        setBusy(url, nil)
        await refreshPrograms(url)
        flushPendingOpens()
        return self.bottle(for: url)
    }

    func createBottleFromSheet(name: String, version: WindowsVersion, components: [String]) {
        Task {
            guard let bottle = await createBottle(name: name, version: version) else { return }
            if !components.isEmpty {
                await installComponents(components, in: bottle.url)
            }
        }
    }

    func renameBottle(_ url: URL, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateConfig(url) { $0.name = trimmed }
    }

    func deleteBottle(_ url: URL) {
        Task {
            await killAll(in: url)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                errorMessage = "Couldn't move the bottle to the Trash: \(error.localizedDescription)"
                return
            }
            if defaultBottleURL == url { defaultBottleURL = nil }
            programs[url] = nil
            loadBottles()
        }
    }

    func setBusy(_ url: URL, _ message: String?) {
        if let message {
            busyBottles.insert(url)
            busyMessage[url] = message
        } else {
            busyBottles.remove(url)
            busyMessage[url] = nil
        }
    }

    private func applyWindowsVersion(_ bottle: Bottle) async {
        await runAndWait(["winecfg", "-v", bottle.config.windowsVersion.rawValue], in: bottle, label: "winecfg")
    }

    private func applyRetina(_ bottle: Bottle) async {
        await runAndWait([
            "reg", "add", "HKCU\\Software\\Wine\\Mac Driver",
            "/v", "RetinaMode", "/t", "REG_SZ", "/d", bottle.config.retina ? "y" : "n", "/f",
        ], in: bottle, label: "reg")
    }

    private func waitForWineserver(_ bottle: Bottle) async {
        guard let wineserver = runtime?.wineserverURL else { return }
        await runAndWait(executable: wineserver, ["-w"], in: bottle, label: "wineserver")
    }

    // MARK: - Components (winetricks)

    var winetricksURL: URL? { AppPaths.tool("winetricks") }

    /// Installs Windows runtimes/libraries into a bottle using winetricks.
    @discardableResult
    func installComponents(_ verbs: [String], in url: URL, reportErrors: Bool = true) async -> Bool {
        guard let bottle = bottle(for: url), runtime != nil else { return false }
        guard let winetricks = winetricksURL else {
            errorMessage = "The component installer is missing. Open Settings → Repair to reinstall it."
            return false
        }
        let names = verbs.map { verb in ComponentCatalog.all.first { $0.verb == verb }?.name ?? verb }
        var allOK = true
        for (index, verb) in verbs.enumerated() {
            let progress = verbs.count > 1 ? " (\(index + 1) of \(verbs.count))" : ""
            setBusy(url, "Installing \(names[index])\(progress)…")
            let status = await runAndWait(executable: URL(fileURLWithPath: "/bin/bash"),
                                          [winetricks.path, "-q", "--force", verb],
                                          in: bottle, label: "winetricks \(verb)",
                                          extraEnv: [
                                              "WINETRICKS_LATEST_VERSION_CHECK": "disabled",
                                              "WINETRICKS_GUI": "none",
                                              "W_OPT_UNATTENDED": "1",
                                          ])
            if status == 0 {
                updateConfig(url) { config in
                    if !config.installedComponents.contains(verb) { config.installedComponents.append(verb) }
                }
            } else {
                allOK = false
                log("⚠️ \(names[index]) didn't install cleanly (code \(status)).\n")
            }
        }
        await waitForWineserver(bottle)
        setBusy(url, nil)
        if !reportErrors { return allOK }
        if allOK {
            toast = verbs.count == 1 ? "\(names[0]) installed" : "\(verbs.count) components installed"
        } else {
            errorMessage = "Some components didn't install. Open the log (⇧⌘L) for details; most programs still work without them."
        }
        return allOK
    }

    // MARK: - DXVK

    var dxvkAvailable: Bool { AppPaths.dxvkRoot != nil }

    /// Copies DXVK's DirectX → Vulkan DLLs into the bottle.
    func installDXVK(in url: URL) async {
        guard let bottle = bottle(for: url) else { return }
        let fm = FileManager.default
        guard let dxvkRoot = AppPaths.dxvkRoot else {
            errorMessage = "DXVK isn't installed yet. Open Settings → Repair to download it."
            updateConfig(url) { $0.dxvk = false }
            return
        }
        setBusy(url, "Installing DXVK…")
        let windows = bottle.driveC.appendingPathComponent("windows")
        for (arch, target) in [("x64", "system32"), ("x32", "syswow64")] {
            let source = dxvkRoot.appendingPathComponent(arch)
            let dest = windows.appendingPathComponent(target)
            guard fm.fileExists(atPath: dest.path),
                  let dlls = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { continue }
            for dll in dlls where dll.pathExtension.lowercased() == "dll" {
                let target = dest.appendingPathComponent(dll.lastPathComponent)
                try? fm.removeItem(at: target)
                try? fm.copyItem(at: dll, to: target)
            }
        }
        setBusy(url, nil)
        toast = "DXVK enabled"
    }

    // MARK: - Running programs

    /// Opens a picker and runs the chosen Windows program.
    func chooseAndRun(in url: URL? = nil) {
        let target = url ?? selectedBottle?.url ?? defaultBottleURL ?? bottles.first?.url
        guard let target, let bottle = self.bottle(for: target) else {
            showNewBottle = true
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows program or installer"
        panel.message = "It will run in “\(bottle.config.name)”."
        panel.allowedContentTypes = WindowsFileTypes.all
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let file = panel.url {
            run(file, in: bottle)
        }
    }

    func run(_ file: URL, in bottle: Bottle) {
        guard let runtime else { return }
        let ext = file.pathExtension.lowercased()
        let args: [String]
        switch ext {
        case "msi": args = ["msiexec", "/i", file.path]
        case "bat", "cmd": args = ["cmd", "/c", file.path]
        case "lnk": args = ["start", "/unix", file.path]
        default: args = [file.path]
        }
        let bottleURL = bottle.url
        launch(runtime.wineURL, args, in: bottle,
               cwd: file.deletingLastPathComponent(),
               label: ProgramScanner.displayName(for: file),
               path: file.path,
               track: true) { _ in
            // Installers usually just finished; pick up whatever they added.
            Task { @MainActor in await AppModel.shared.refreshPrograms(bottleURL) }
        }
        toast = "Starting \(ProgramScanner.displayName(for: file))…"
    }

    /// Built-in Windows tools that ship with Wine.
    func runTool(_ tool: WineTool, in bottle: Bottle) {
        guard let runtime else { return }
        let args = tool == .commandPrompt ? ["start", "cmd"] : [tool.command]
        launch(runtime.wineURL, args, in: bottle, cwd: bottle.driveC, label: tool.title, path: nil, track: true)
    }

    func isRunning(_ url: URL) -> Bool {
        running.contains { $0.path == url.path }
    }

    /// Ends every Windows process running in a bottle.
    func killAll(in url: URL) async {
        guard let runtime, let bottle = bottle(for: url) else { return }
        if let wineserver = runtime.wineserverURL {
            await runAndWait(executable: wineserver, ["-k"], in: bottle, label: "wineserver")
        } else {
            await runAndWait(["wineboot", "--kill"], in: bottle, label: "wineboot")
        }
        for program in running where program.bottleURL == url && program.process.isRunning {
            program.process.terminate()
        }
    }

    func openDriveC(_ bottle: Bottle) {
        NSWorkspace.shared.open(bottle.driveC)
    }

    // MARK: - Library

    /// Every program across all bottles: pinned first, then installed, alphabetically.
    var library: [LibraryItem] {
        var items: [LibraryItem] = []
        for bottle in bottles {
            var seen = Set<String>()
            for pin in bottle.config.pinned {
                seen.insert(pin.path)
                items.append(LibraryItem(url: pin.url, name: pin.name, bottleURL: bottle.url,
                                         bottleName: bottle.config.name, isPinned: true))
            }
            for exe in programs[bottle.url] ?? []
            where !seen.contains(exe.path) && !bottle.config.hidden.contains(exe.path) {
                items.append(LibraryItem(url: exe, name: ProgramScanner.displayName(for: exe), bottleURL: bottle.url,
                                         bottleName: bottle.config.name, isPinned: false))
            }
        }
        return items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func refreshPrograms(_ url: URL) async {
        guard let bottle = bottle(for: url) else { return }
        scanning.insert(url)
        let driveC = bottle.driveC
        let found = await Task.detached(priority: .utility) {
            ProgramScanner.scan(driveC: driveC)
        }.value
        programs[url] = found
        scanning.remove(url)
    }

    func refreshAllPrograms() {
        for bottle in bottles {
            Task { await refreshPrograms(bottle.url) }
        }
    }

    func pin(_ file: URL, in url: URL) {
        updateConfig(url) { config in
            guard !config.pinned.contains(where: { $0.path == file.path }) else { return }
            config.pinned.append(PinnedProgram(name: ProgramScanner.displayName(for: file), path: file.path))
        }
    }

    func unpin(path: String, in url: URL) {
        updateConfig(url) { $0.pinned.removeAll { $0.path == path } }
    }

    func hide(path: String, in url: URL) {
        updateConfig(url) { config in
            config.pinned.removeAll { $0.path == path }
            if !config.hidden.contains(path) { config.hidden.append(path) }
        }
    }

    func unhideAll(in url: URL) {
        updateConfig(url) { $0.hidden.removeAll() }
    }

    func renameProgram(path: String, to name: String, in url: URL) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateConfig(url) { config in
            if let i = config.pinned.firstIndex(where: { $0.path == path }) {
                config.pinned[i].name = trimmed
            } else {
                config.pinned.append(PinnedProgram(name: trimmed, path: path))
            }
        }
    }

    /// Adds a double-clickable launcher (.command file) for a program to the Desktop.
    func createDesktopShortcut(for file: URL, in url: URL) {
        guard let runtime, let bottle = bottle(for: url) else { return }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let name = ProgramScanner.displayName(for: file)
        let shortcut = desktop.appendingPathComponent("\(name).command")
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let sync = bottle.config.msync ? "1" : "0"
        let script = """
        #!/bin/bash
        # Launches \(name) with Translator's Wine.
        export WINEPREFIX=\(q(bottle.url.path))
        export WINEDEBUG=-all WINEMSYNC=\(sync) WINEESYNC=\(sync) WINE_LARGE_ADDRESS_AWARE=1
        export WINEDLLOVERRIDES='winemenubuilder.exe=d'
        cd \(q(file.deletingLastPathComponent().path))
        nohup \(q(runtime.wineURL.path)) \(q(file.path)) >/dev/null 2>&1 &
        exit 0
        """
        do {
            try script.write(to: shortcut, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shortcut.path)
            toast = "Shortcut added to your Desktop"
        } catch {
            errorMessage = "Couldn't create the shortcut: \(error.localizedDescription)"
        }
    }

    // MARK: - Finder integration

    /// Called when the user double-clicks an .exe in Finder or drops one on the Dock icon.
    func openExternally(_ urls: [URL]) {
        pendingOpens.append(contentsOf: urls)
        flushPendingOpens()
    }

    private func flushPendingOpens() {
        guard !pendingOpens.isEmpty, runtime != nil, setupCompleted else { return }
        let targetURL = defaultBottleURL.flatMap { self.bottle(for: $0)?.url } ?? bottles.first?.url
        guard let targetURL, let bottle = self.bottle(for: targetURL) else {
            if busyBottles.isEmpty { Task { await createBottle(name: "My Windows", version: .win10) } }
            return
        }
        guard !busyBottles.contains(targetURL) else { return }
        let files = pendingOpens
        pendingOpens.removeAll()
        files.forEach { run($0, in: bottle) }
    }

    func setupFinished() {
        refreshRuntime()
        setupCompleted = true
        sidebar = .library
        flushPendingOpens()
    }

    // MARK: - Process plumbing

    @discardableResult
    private func launch(_ executable: URL, _ args: [String], in bottle: Bottle, cwd: URL?,
                        label: String, path: String?, track: Bool,
                        extraEnv: [String: String] = [:],
                        onExit: ((Int32) -> Void)? = nil) -> Process? {
        guard let runtime else {
            onExit?(-1)
            return nil
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        var env = runtime.environment(for: bottle)
        env.merge(extraEnv) { _, new in new }
        process.environment = env
        if let cwd, FileManager.default.fileExists(atPath: cwd.path) {
            process.currentDirectoryURL = cwd
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in AppModel.shared.log(text) }
        }

        let trackedID = UUID()
        process.terminationHandler = { proc in
            let status = proc.terminationStatus
            Task { @MainActor in
                let model = AppModel.shared
                model.log("■ \(label) exited (code \(status))\n")
                model.running.removeAll { $0.id == trackedID }
                onExit?(status)
            }
        }

        log("▶ \(label) — \(bottle.config.name)\n")
        do {
            try process.run()
        } catch {
            log("✖ Couldn't start \(label): \(error.localizedDescription)\n")
            errorMessage = "Couldn't start \(label): \(error.localizedDescription)"
            onExit?(-1)
            return nil
        }
        if track {
            running.append(RunningProgram(id: trackedID, name: label, path: path ?? "",
                                          bottleURL: bottle.url, process: process))
        }
        return process
    }

    @discardableResult
    func runAndWait(_ args: [String], in bottle: Bottle, label: String) async -> Int32 {
        guard let runtime else { return -1 }
        return await runAndWait(executable: runtime.wineURL, args, in: bottle, label: label)
    }

    @discardableResult
    func runAndWait(executable: URL, _ args: [String], in bottle: Bottle, label: String,
                    extraEnv: [String: String] = [:]) async -> Int32 {
        await withCheckedContinuation { continuation in
            // launch() calls onExit exactly once: when the process ends, or with -1 if it can't start.
            launch(executable, args, in: bottle, cwd: bottle.url, label: label, path: nil,
                   track: false, extraEnv: extraEnv) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func log(_ text: String) {
        logText += text
        if logText.count > maxLogCharacters {
            logText = String(logText.suffix(maxLogCharacters / 2))
        }
    }

    func clearLog() { logText = "" }
}
