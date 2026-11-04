import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var runtime: WineRuntime?
    @Published private(set) var bottles: [Bottle] = []
    @Published var selection: URL?
    @Published private(set) var running: [RunningProgram] = []
    @Published private(set) var busyBottles: Set<URL> = []
    @Published private(set) var busyMessage: [URL: String] = [:]
    @Published private(set) var logText = ""
    @Published var showLog = false
    @Published var showNewBottle = false
    @Published var errorMessage: String?

    /// Files opened from Finder before Wine or a bottle was ready.
    private var pendingOpens: [URL] = []

    private let defaults = UserDefaults.standard
    private let maxLogCharacters = 200_000

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

    let rootURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Translator/Bottles", isDirectory: true)
    }()

    private init() {
        refreshRuntime()
        loadBottles()
    }

    var selectedBottle: Bottle? {
        guard let selection else { return nil }
        return bottle(for: selection)
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
            if runtime == nil {
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

        if selection == nil || selectedBottle == nil {
            selection = bottles.first?.url
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
    }

    func createBottle(name: String, version: WindowsVersion) {
        guard runtime != nil else { return }
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
            return
        }

        let bottle = Bottle(url: url, config: BottleConfig(name: displayName, windowsVersion: version))
        save(bottle)
        bottles.append(bottle)
        selection = url
        if defaultBottleURL == nil { defaultBottleURL = url }

        Task {
            setBusy(url, "Setting up Windows… (this takes a minute the first time)")
            let status = await runAndWait(["wineboot", "--init"], in: bottle, label: "wineboot")
            if status != 0 {
                log("⚠️ wineboot finished with code \(status). The bottle may still work; check the log.\n")
            }
            await applyWindowsVersion(bottle)
            if bottle.config.retina { await applyRetina(bottle) }
            setBusy(url, nil)
            objectWillChange.send()
            flushPendingOpens()
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
            loadBottles()
            if selection == url { selection = bottles.first?.url }
        }
    }

    private func setBusy(_ url: URL, _ message: String?) {
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

    // MARK: - Running programs

    /// Opens a picker and runs the chosen Windows program in the selected bottle.
    func chooseAndRun(in url: URL? = nil) {
        guard let target = url ?? selection ?? bottles.first?.url, let bottle = self.bottle(for: target) else {
            showNewBottle = true
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows program or installer"
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
        launch(runtime.wineURL, args, in: bottle,
               cwd: file.deletingLastPathComponent(),
               label: file.deletingPathExtension().lastPathComponent,
               track: true)
    }

    /// Built-in Windows tools that ship with Wine.
    func runTool(_ tool: WineTool, in bottle: Bottle) {
        guard let runtime else { return }
        let args: [String]
        switch tool {
        case .commandPrompt: args = ["start", "cmd"]
        default: args = [tool.command]
        }
        launch(runtime.wineURL, args, in: bottle, cwd: bottle.driveC, label: tool.title, track: true)
    }

    /// Ends every Windows process running in a bottle.
    func killAll(in url: URL) async {
        guard let runtime, let bottle = self.bottle(for: url) else { return }
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

    // MARK: - Pinning

    func pin(_ file: URL, in url: URL) {
        updateConfig(url) { config in
            guard !config.pinned.contains(where: { $0.path == file.path }) else { return }
            config.pinned.append(PinnedProgram(name: file.deletingPathExtension().lastPathComponent, path: file.path))
        }
    }

    func unpin(_ program: PinnedProgram, in url: URL) {
        updateConfig(url) { $0.pinned.removeAll { $0.id == program.id } }
    }

    func renamePinned(_ program: PinnedProgram, to name: String, in url: URL) {
        updateConfig(url) { config in
            if let i = config.pinned.firstIndex(where: { $0.id == program.id }) {
                config.pinned[i].name = name
            }
        }
    }

    // MARK: - Finder integration

    /// Called when the user double-clicks an .exe in Finder or drops one on the Dock icon.
    func openExternally(_ urls: [URL]) {
        pendingOpens.append(contentsOf: urls)
        flushPendingOpens()
    }

    private func flushPendingOpens() {
        guard !pendingOpens.isEmpty else { return }
        guard runtime != nil else { return }
        let targetURL = defaultBottleURL.flatMap { self.bottle(for: $0)?.url } ?? bottles.first?.url
        guard let targetURL, let bottle = self.bottle(for: targetURL) else {
            // No bottle yet: make one, then run once it's ready.
            if busyBottles.isEmpty { createBottle(name: "Default", version: .win10) }
            return
        }
        guard !busyBottles.contains(targetURL) else { return }
        let files = pendingOpens
        pendingOpens.removeAll()
        files.forEach { run($0, in: bottle) }
    }

    // MARK: - Program discovery

    /// Finds installed .exe files in a bottle's Program Files folders.
    func discoverPrograms(in bottle: Bottle) async -> [URL] {
        let driveC = bottle.driveC
        return await Task.detached(priority: .utility) {
            ProgramScanner.scan(driveC: driveC)
        }.value
    }

    // MARK: - Process plumbing

    @discardableResult
    private func launch(_ executable: URL, _ args: [String], in bottle: Bottle, cwd: URL?,
                        label: String, track: Bool,
                        onExit: ((Int32) -> Void)? = nil) -> Process? {
        guard let runtime else {
            onExit?(-1)
            return nil
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = runtime.environment(for: bottle)
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
            running.append(RunningProgram(id: trackedID, name: label, bottleURL: bottle.url, process: process))
        }
        return process
    }

    @discardableResult
    private func runAndWait(_ args: [String], in bottle: Bottle, label: String) async -> Int32 {
        guard let runtime else { return -1 }
        return await runAndWait(executable: runtime.wineURL, args, in: bottle, label: label)
    }

    @discardableResult
    private func runAndWait(executable: URL, _ args: [String], in bottle: Bottle, label: String) async -> Int32 {
        await withCheckedContinuation { continuation in
            // launch() calls onExit exactly once: when the process ends, or with -1 if it can't start.
            launch(executable, args, in: bottle, cwd: bottle.url, label: label, track: false) { status in
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
