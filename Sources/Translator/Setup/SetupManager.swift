import Foundation

/// Runs Translator's first-time setup: Rosetta, Wine, add-ons, helper tools, a ready-to-use
/// bottle, and the Windows components most programs need. Everything is downloaded and
/// installed automatically; the user only clicks one button.
@MainActor
final class SetupManager: ObservableObject {
    enum StepID: String, CaseIterable {
        case rosetta, wine, addons, tools, bottle, components
    }

    enum StepState: Equatable {
        case pending
        case running(progress: Double?, detail: String)
        case done(String)
        case skipped(String)
        case failed(String)

        var isFinished: Bool {
            switch self {
            case .done, .skipped: return true
            default: return false
            }
        }
    }

    struct Step: Identifiable {
        let id: StepID
        let title: String
        let symbol: String
        var state: StepState = .pending
    }

    @Published private(set) var steps: [Step]
    @Published private(set) var isRunning = false
    @Published private(set) var finished = false
    @Published private(set) var failed = false
    @Published var installEssentials = true

    private let model: AppModel

    // Pinned fallbacks, used only if GitHub's API can't be reached.
    private static let fallbackWineURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-staging-11.21-osx64.tar.xz")!
    private static let geckoVersion = "2.47.4"
    private static let winetricksURL = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")!
    private static let dxvkURL = URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz")!

    init(model: AppModel) {
        self.model = model
        var steps: [Step] = []
        if WineRuntime.isAppleSilicon {
            steps.append(Step(id: .rosetta, title: "Intel app support (Rosetta 2)", symbol: "cpu"))
        }
        steps.append(Step(id: .wine, title: "Windows compatibility engine (Wine)", symbol: "wineglass"))
        steps.append(Step(id: .addons, title: ".NET and web page support", symbol: "globe"))
        steps.append(Step(id: .tools, title: "Component installer & DirectX translator", symbol: "wrench.and.screwdriver"))
        steps.append(Step(id: .bottle, title: "Your Windows environment", symbol: "shippingbox"))
        steps.append(Step(id: .components, title: "Essential Windows components", symbol: "square.stack.3d.up"))
        self.steps = steps
    }

    var overallProgress: Double {
        let total = Double(steps.count)
        var done = 0.0
        for step in steps {
            switch step.state {
            case .done, .skipped: done += 1
            case .running(let p, _): done += (p ?? 0.3)
            default: break
            }
        }
        return total == 0 ? 0 : done / total
    }

    // MARK: - Run

    func start() {
        guard !isRunning else { return }
        isRunning = true
        failed = false
        Task {
            await runAll()
            isRunning = false
        }
    }

    private func runAll() async {
        for step in steps where !step.state.isFinished {
            let ok: Bool
            switch step.id {
            case .rosetta: ok = await installRosetta()
            case .wine: ok = await installWine()
            case .addons: ok = await installAddons()
            case .tools: ok = await installTools()
            case .bottle: ok = await prepareBottle()
            case .components: ok = await installComponents()
            }
            if !ok {
                failed = true
                return
            }
        }
        finished = true
    }

    private func set(_ id: StepID, _ state: StepState) {
        if let i = steps.firstIndex(where: { $0.id == id }) {
            steps[i].state = state
        }
    }

    // MARK: Steps

    private func installRosetta() async -> Bool {
        guard WineRuntime.needsRosetta else {
            set(.rosetta, .done("Already installed"))
            return true
        }
        set(.rosetta, .running(progress: nil, detail: "macOS will ask for your password to install Rosetta…"))
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        let result = await Shell.run("/usr/bin/osascript", ["-e", script])
        if !WineRuntime.needsRosetta {
            set(.rosetta, .done("Installed"))
            return true
        }
        let reason = result.output.contains("-128") ? "Cancelled. Rosetta is required to run Windows programs." : "Couldn't install Rosetta: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        set(.rosetta, .failed(reason))
        return false
    }

    /// Asks GitHub for the newest Wine Staging build for macOS.
    private func latestWineURL() async -> (URL, String) {
        let api = URL(string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases?per_page=10")!
        var request = URLRequest(url: api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Translator-macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let prerelease: Bool
            let assets: [Asset]
        }
        if let response = try? await URLSession.shared.data(for: request),
           let releases = try? JSONDecoder().decode([Release].self, from: response.0) {
            for release in releases where !release.prerelease {
                if let asset = release.assets.first(where: { $0.name.hasPrefix("wine-staging") && $0.name.hasSuffix("osx64.tar.xz") }) {
                    return (asset.browser_download_url, release.tag_name)
                }
            }
        }
        return (Self.fallbackWineURL, "11.21")
    }

    private func installWine() async -> Bool {
        if let runtime = WineRuntime.locate(customPath: nil), runtime.isManaged {
            set(.wine, .done("Wine is installed"))
            model.refreshRuntime()
            return true
        }
        set(.wine, .running(progress: nil, detail: "Finding the latest version…"))
        let (url, version) = await latestWineURL()
        let archive = AppPaths.downloads.appendingPathComponent(url.lastPathComponent)

        do {
            set(.wine, .running(progress: 0, detail: "Downloading Wine \(version)…"))
            _ = try await Downloader.download(url, to: archive) { [weak self] fraction, bytes in
                Task { @MainActor in
                    let mb = Double(bytes) / 1_048_576
                    self?.set(.wine, .running(progress: fraction.map { $0 * 0.85 },
                                              detail: String(format: "Downloading Wine \(version)… %.0f MB", mb)))
                }
            }
        } catch {
            set(.wine, .failed("Download failed: \(error.localizedDescription). Check your internet connection and try again."))
            return false
        }

        set(.wine, .running(progress: 0.9, detail: "Unpacking (about 1 GB)…"))
        let fm = FileManager.default
        let staging = AppPaths.support.appendingPathComponent("Runtime.partial", isDirectory: true)
        try? fm.removeItem(at: staging)
        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let untar = await Shell.run("/usr/bin/tar", ["-xJf", archive.path, "-C", staging.path])
        guard untar.status == 0, WineRuntime.findWineBinary(in: staging) != nil else {
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: archive)
            set(.wine, .failed("Couldn't unpack Wine. \(untar.output.suffix(300))"))
            return false
        }
        // Make sure macOS doesn't block the freshly unpacked binaries.
        await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
        try? fm.removeItem(at: AppPaths.runtime)
        do {
            try fm.moveItem(at: staging, to: AppPaths.runtime)
        } catch {
            set(.wine, .failed("Couldn't install Wine: \(error.localizedDescription)"))
            return false
        }
        try? fm.removeItem(at: archive)
        model.refreshRuntime()
        guard model.runtime != nil else {
            set(.wine, .failed("Wine was installed but couldn't be found."))
            return false
        }
        set(.wine, .done("Wine \(version) installed"))
        return true
    }

    /// Wine Mono (.NET) ships inside the Wine build; Wine Gecko (web pages inside programs and
    /// installers) is downloaded here so Wine never pops up its own download dialog.
    private func installAddons() async -> Bool {
        guard let runtime = model.runtime else {
            set(.addons, .skipped("No Wine found"))
            return true
        }
        let gecko = runtime.rootDir.appendingPathComponent("share/wine/gecko", isDirectory: true)
        let fm = FileManager.default
        let files = ["x86", "x86_64"].map { "wine-gecko-\(Self.geckoVersion)-\($0).msi" }
        if files.allSatisfy({ fm.fileExists(atPath: gecko.appendingPathComponent($0).path) }) {
            set(.addons, .done("Installed"))
            return true
        }
        guard fm.isWritableFile(atPath: runtime.rootDir.path) else {
            set(.addons, .skipped("Using a Wine copy Translator doesn't manage"))
            return true
        }
        for (index, file) in files.enumerated() {
            let url = URL(string: "https://dl.winehq.org/wine/wine-gecko/\(Self.geckoVersion)/\(file)")!
            do {
                _ = try await Downloader.download(url, to: gecko.appendingPathComponent(file)) { [weak self] fraction, _ in
                    Task { @MainActor in
                        let base = Double(index) / Double(files.count)
                        self?.set(.addons, .running(progress: base + (fraction ?? 0) / Double(files.count),
                                                    detail: "Downloading web engine (\(index + 1) of \(files.count))…"))
                    }
                }
            } catch {
                // Not fatal: only programs that embed web pages need it.
                set(.addons, .skipped("Web engine unavailable right now; most programs don't need it"))
                return true
            }
        }
        set(.addons, .done(".NET (Wine Mono) and web engine (Wine Gecko) ready"))
        return true
    }

    private func installTools() async -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppPaths.tools, withIntermediateDirectories: true)

        if AppPaths.tool("winetricks") == nil {
            set(.tools, .running(progress: 0.1, detail: "Downloading component installer…"))
            let dest = AppPaths.tools.appendingPathComponent("winetricks")
            if (try? await Downloader.download(Self.winetricksURL, to: dest, progress: { _, _ in })) != nil {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
            }
        }

        if AppPaths.dxvkRoot == nil {
            set(.tools, .running(progress: 0.5, detail: "Downloading DirectX → Metal translator (DXVK)…"))
            let archive = AppPaths.downloads.appendingPathComponent("dxvk.tar.gz")
            if (try? await Downloader.download(Self.dxvkURL, to: archive, progress: { _, _ in })) != nil {
                let temp = AppPaths.downloads.appendingPathComponent("dxvk-extract", isDirectory: true)
                try? fm.removeItem(at: temp)
                try? fm.createDirectory(at: temp, withIntermediateDirectories: true)
                await Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", temp.path])
                if let inner = (try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil))?
                    .first(where: { fm.fileExists(atPath: $0.appendingPathComponent("x64").path) }) {
                    let dest = AppPaths.tools.appendingPathComponent("dxvk")
                    try? fm.removeItem(at: dest)
                    try? fm.moveItem(at: inner, to: dest)
                }
                try? fm.removeItem(at: temp)
                try? fm.removeItem(at: archive)
            }
        }

        var parts: [String] = []
        parts.append(AppPaths.tool("winetricks") != nil ? "Component installer ready" : "Component installer unavailable")
        parts.append(AppPaths.dxvkRoot != nil ? "DXVK ready" : "DXVK unavailable")
        set(.tools, .done(parts.joined(separator: " · ")))
        return true
    }

    private func prepareBottle() async -> Bool {
        if let existing = model.bottles.first {
            set(.bottle, .done("Using “\(existing.config.name)”"))
            return true
        }
        set(.bottle, .running(progress: nil, detail: "Creating a Windows 10 environment… (about a minute)"))
        guard let bottle = await model.createBottle(name: "My Windows", version: .win10, select: false) else {
            set(.bottle, .failed("Couldn't create the Windows environment. Open the log for details."))
            return false
        }
        set(.bottle, .done("“\(bottle.config.name)” is ready"))
        return true
    }

    private func installComponents() async -> Bool {
        guard installEssentials else {
            set(.components, .skipped("Skipped; you can add components any time"))
            return true
        }
        guard let bottle = model.bottles.first else {
            set(.components, .skipped("No bottle"))
            return true
        }
        guard model.winetricksURL != nil else {
            set(.components, .skipped("Component installer unavailable"))
            return true
        }
        let pending = ComponentCatalog.essentials.filter { !bottle.config.installedComponents.contains($0.verb) }
        if pending.isEmpty {
            set(.components, .done("Already installed"))
            return true
        }
        for (index, component) in pending.enumerated() {
            set(.components, .running(progress: Double(index) / Double(pending.count),
                                      detail: "Installing \(component.name) (\(index + 1) of \(pending.count))…"))
            await model.installComponents([component.verb], in: bottle.url, reportErrors: false)
        }
        // A component that fails is not fatal; it's logged and can be retried later.
        let installed = model.bottle(for: bottle.url)?.config.installedComponents ?? []
        let count = pending.filter { installed.contains($0.verb) }.count
        set(.components, .done("\(count) of \(pending.count) components installed"))
        return true
    }
}
