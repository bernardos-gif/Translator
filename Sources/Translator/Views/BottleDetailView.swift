import AppKit
import SwiftUI

struct BottleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    enum Tab: String, CaseIterable, Identifiable {
        case programs = "Programs"
        case components = "Components"
        case settings = "Settings"
        case tools = "Tools"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .programs
    @State private var dropTargeted = false

    private var isBusy: Bool { model.busyBottles.contains(bottle.url) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if isBusy { busyBanner }
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)

                switch tab {
                case .programs: programsTab
                case .components: ComponentsTab(bottle: bottle)
                case .settings: SettingsTab(bottle: bottle)
                case .tools: toolsTab
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(WindowsFileTypes.isWindowsFile)
            files.forEach { model.run($0, in: bottle) }
            return !files.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Theme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(Label("Drop to run in “\(bottle.config.name)”", systemImage: "arrow.down.app.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.violet))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .task(id: bottle.url) { await model.refreshPrograms(bottle.url) }
    }

    // MARK: Hero

    private var hero: some View {
        let color = Theme.color(for: bottle.config.name)
        return HStack(alignment: .center, spacing: 18) {
            BottleBadge(name: bottle.config.name, size: 64)
                .shadow(color: color.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(bottle.config.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    Chip(text: bottle.config.windowsVersion.label, symbol: "pc")
                    Chip(text: "\(programCount) programs", symbol: "square.grid.2x2")
                    if bottle.config.dxvk { Chip(text: "DXVK", symbol: "bolt.fill") }
                    if model.defaultBottleURL == bottle.url { Chip(text: "Default", symbol: "star.fill") }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    model.chooseAndRun(in: bottle.url)
                } label: {
                    Label("Install or Run…", systemImage: "plus")
                }
                .buttonStyle(GradientButtonStyle())
                HStack(spacing: 8) {
                    Button {
                        model.openDriveC(bottle)
                    } label: {
                        Label("C: Drive", systemImage: "internaldrive")
                    }
                    .buttonStyle(PillButtonStyle())
                    Button {
                        Task { await model.killAll(in: bottle.url) }
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                    .help("Quit every Windows program running in this bottle")
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(color.opacity(0.25)))
    }

    private var programCount: Int {
        model.library.filter { $0.bottleURL == bottle.url }.count
    }

    private var busyBanner: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(model.busyMessage[bottle.url] ?? "Working…")
                .font(.callout.weight(.medium))
            Spacer()
            Button("Show Log") { model.showLog = true }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Theme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Programs

    @ViewBuilder
    private var programsTab: some View {
        let items = model.library.filter { $0.bottleURL == bottle.url }
        if items.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.app")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.brand)
                Text(model.scanning.contains(bottle.url) ? "Looking for programs…" : "No programs installed in this bottle yet")
                    .font(.headline)
                Text("Drop a Windows installer here or click Install or Run.")
                    .foregroundStyle(.secondary)
                if !bottle.config.hidden.isEmpty {
                    Button("Show \(bottle.config.hidden.count) hidden programs") { model.unhideAll(in: bottle.url) }
                        .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
            .card(radius: 18)
        } else {
            ProgramGrid(items: items, showBottle: false)
            if !bottle.config.hidden.isEmpty {
                Button("Show \(bottle.config.hidden.count) hidden programs") { model.unhideAll(in: bottle.url) }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: Tools

    private var toolsTab: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            ForEach(WineTool.allCases) { tool in
                Button {
                    model.runTool(tool, in: bottle)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tool.symbol)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title).font(.body.weight(.semibold))
                            Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card(padding: 14)
            }
        }
    }
}

struct Chip: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

// MARK: - Components tab

private struct ComponentsTab: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    private var isBusy: Bool { model.busyBottles.contains(bottle.url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Windows components")
                        .font(.title3.weight(.semibold))
                    Text("When a program complains about a missing DLL, runtime or font, install it here. Components download from Microsoft and other official sources.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                let missing = ComponentCatalog.essentials.filter { !bottle.config.installedComponents.contains($0.verb) }
                if !missing.isEmpty {
                    Button("Install Essentials") {
                        Task { await model.installComponents(missing.map(\.verb), in: bottle.url) }
                    }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(isBusy)
                }
            }

            if model.winetricksURL == nil {
                Label("The component installer is missing. Run setup again from Settings to restore it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            ForEach(WindowsComponent.Category.allCases) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Label(category.rawValue, systemImage: category.symbol)
                        .font(.headline)
                    VStack(spacing: 0) {
                        let items = ComponentCatalog.all.filter { $0.category == category }
                        ForEach(items) { component in
                            ComponentRow(component: component, bottle: bottle, disabled: isBusy)
                            if component.id != items.last?.id { Divider().padding(.leading, 14) }
                        }
                    }
                    .card(padding: 4)
                }
            }
        }
    }
}

private struct ComponentRow: View {
    @EnvironmentObject private var model: AppModel
    let component: WindowsComponent
    let bottle: Bottle
    let disabled: Bool

    private var installed: Bool { bottle.config.installedComponents.contains(component.verb) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(component.name).font(.body.weight(.medium))
                    if component.essential {
                        Text("Essential")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.violet.opacity(0.12), in: Capsule())
                    }
                }
                Text(component.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if installed {
                Menu {
                    Button("Reinstall") {
                        Task { await model.installComponents([component.verb], in: bottle.url) }
                    }
                } label: {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(disabled)
            } else {
                Button("Install") {
                    Task { await model.installComponents([component.verb], in: bottle.url) }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(disabled || model.winetricksURL == nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Settings tab

private struct SettingsTab: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingGroup(title: "Compatibility", symbol: "puzzlepiece.extension.fill") {
                SettingRow(title: "Windows version", detail: "What version of Windows programs see. Try Windows 7 for older software.") {
                    Picker("", selection: binding(\.windowsVersion)) {
                        ForEach(WindowsVersion.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Divider()
                SettingRow(title: "Faster multithreading",
                           detail: "Speeds up most games and apps. Turn off if a program freezes at startup.") {
                    Toggle("", isOn: binding(\.msync)).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingGroup(title: "Graphics", symbol: "sparkles.tv.fill") {
                SettingRow(title: "DirectX → Metal translation (DXVK)",
                           detail: model.dxvkAvailable
                           ? "Runs DirectX 9, 10 and 11 games through Vulkan and Metal. Usually faster and more compatible for games; turn off if a program shows a black window."
                           : "Not available. Run setup again from Settings to install it.") {
                    Toggle("", isOn: binding(\.dxvk)).labelsHidden().toggleStyle(.switch)
                        .disabled(!model.dxvkAvailable)
                }
                Divider()
                SettingRow(title: "Retina mode",
                           detail: "Renders at full Mac resolution. Sharper, but some programs look small.") {
                    Toggle("", isOn: binding(\.retina)).labelsHidden().toggleStyle(.switch)
                }
            }

            SettingGroup(title: "Bottle", symbol: "shippingbox.fill") {
                SettingRow(title: "Open .exe files from Finder here",
                           detail: "Double-clicked Windows files run in this bottle.") {
                    Toggle("", isOn: Binding(
                        get: { model.defaultBottleURL == bottle.url },
                        set: { if $0 { model.defaultBottleURL = bottle.url } }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "Detailed logging", detail: "Shows more of Wine's output in the log. Useful when something won't start.") {
                    Toggle("", isOn: binding(\.verboseLogging)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "Location", detail: bottle.url.path) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([bottle.url]) }
                        .buttonStyle(PillButtonStyle())
                }
            }

            SettingGroup(title: "Danger zone", symbol: "exclamationmark.triangle.fill") {
                SettingRow(title: "Delete this bottle",
                           detail: "Moves the bottle and every program installed in it to the Trash.") {
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .confirmationDialog("Delete “\(bottle.config.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { model.deleteBottle(bottle.url) }
        } message: {
            Text("Every program installed in this bottle goes to the Trash with it.")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<BottleConfig, T>) -> Binding<T> {
        Binding(
            get: { model.bottle(for: bottle.url)?.config[keyPath: keyPath] ?? bottle.config[keyPath: keyPath] },
            set: { value in model.updateConfig(bottle.url) { $0[keyPath: keyPath] = value } }
        )
    }
}

struct SettingGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            VStack(spacing: 0) { content }
                .card(padding: 4)
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
