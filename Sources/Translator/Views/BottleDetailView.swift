import AppKit
import SwiftUI

struct BottleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    @State private var discovered: [URL] = []
    @State private var scanning = false
    @State private var isDropTargeted = false

    private var isBusy: Bool { model.busyBottles.contains(bottle.url) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if isBusy {
                    busyBanner
                }
                dropZone
                pinnedSection
                installedSection
                settingsSection
                toolsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isBusy)
        .task(id: bottle.url) { await rescan() }
        .onChange(of: isBusy) { busy in
            if !busy { Task { await rescan() } }
        }
        .onChange(of: model.running.count) { _ in
            // Installers usually just finished; pick up what they installed.
            Task { await rescan() }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.config.name).font(.largeTitle.weight(.semibold))
                Text("\(bottle.config.windowsVersion.label) · \(model.runtime?.source ?? "Wine")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.openDriveC(bottle)
            } label: {
                Label("C: Drive", systemImage: "internaldrive")
            }
            Button(role: .destructive) {
                Task { await model.killAll(in: bottle.url) }
            } label: {
                Label("Stop All", systemImage: "stop.fill")
            }
            .help("Quit every Windows program running in this bottle")
            Button {
                model.chooseAndRun(in: bottle.url)
            } label: {
                Label("Run Program…", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var busyBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(model.busyMessage[bottle.url] ?? "Working…")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.app")
                .font(.title)
            Text("Drop a Windows .exe or .msi here to run or install it")
                .font(.callout)
        }
        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        )
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(WindowsFileTypes.isWindowsFile)
            files.forEach { model.run($0, in: bottle) }
            return !files.isEmpty
        } isTargeted: { isDropTargeted = $0 }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        if !bottle.config.pinned.isEmpty {
            SectionBox(title: "Pinned") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(bottle.config.pinned) { program in
                        PinnedTile(program: program, bottle: bottle)
                    }
                }
            }
        }
    }

    private var installedSection: some View {
        SectionBox(title: "Installed Programs", trailing: {
            Button {
                Task { await rescan() }
            } label: {
                if scanning { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.borderless)
            .help("Scan the bottle again")
        }) {
            if discovered.isEmpty {
                Text(scanning ? "Scanning…" : "Nothing installed yet. Run an installer (setup.exe or .msi) to add programs.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(discovered, id: \.self) { exe in
                        ProgramRow(exe: exe, bottle: bottle)
                        if exe != discovered.last { Divider() }
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        SectionBox(title: "Settings") {
            Form {
                Picker("Windows version", selection: binding(\.windowsVersion)) {
                    ForEach(WindowsVersion.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Faster multithreading (MSync)", isOn: binding(\.msync))
                    .help("Speeds up most games. Turn off if a program hangs or crashes.")
                Toggle("Retina mode (sharper, but smaller UI)", isOn: binding(\.retina))
                Toggle("Detailed Wine logging", isOn: binding(\.verboseLogging))
                    .help("Useful when diagnosing why a program won't start.")
            }
            .formStyle(.columns)
        }
    }

    private var toolsSection: some View {
        SectionBox(title: "Windows Tools") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(WineTool.allCases) { tool in
                    Button {
                        model.runTool(tool, in: bottle)
                    } label: {
                        Label(tool.title, systemImage: tool.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<BottleConfig, T>) -> Binding<T> {
        Binding(
            get: { model.bottle(for: bottle.url)?.config[keyPath: keyPath] ?? bottle.config[keyPath: keyPath] },
            set: { value in model.updateConfig(bottle.url) { $0[keyPath: keyPath] = value } }
        )
    }

    private func rescan() async {
        scanning = true
        discovered = await model.discoverPrograms(in: bottle)
        scanning = false
    }
}

// MARK: - Subviews

private struct SectionBox<Content: View, Trailing: View>: View {
    let title: String
    let trailing: Trailing
    let content: Content

    init(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                trailing
            }
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

extension SectionBox where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

private struct PinnedTile: View {
    @EnvironmentObject private var model: AppModel
    let program: PinnedProgram
    let bottle: Bottle

    var body: some View {
        Button {
            model.run(program.url, in: bottle)
        } label: {
            VStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: program.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(program.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Run") { model.run(program.url, in: bottle) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([program.url]) }
            Divider()
            Button("Unpin") { model.unpin(program, in: bottle.url) }
        }
        .help(program.path)
    }
}

private struct ProgramRow: View {
    @EnvironmentObject private var model: AppModel
    let exe: URL
    let bottle: Bottle

    private var isPinned: Bool {
        bottle.config.pinned.contains { $0.path == exe.path }
    }

    private var relativeFolder: String {
        let base = bottle.driveC.path
        let folder = exe.deletingLastPathComponent().path
        return folder.hasPrefix(base) ? "C:" + folder.dropFirst(base.count).replacingOccurrences(of: "/", with: "\\") : folder
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: exe.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(exe.deletingPathExtension().lastPathComponent)
                Text(relativeFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                if let pinned = bottle.config.pinned.first(where: { $0.path == exe.path }) {
                    model.unpin(pinned, in: bottle.url)
                } else {
                    model.pin(exe, in: bottle.url)
                }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(isPinned ? "Unpin" : "Pin to the top")
            Button("Run") { model.run(exe, in: bottle) }
        }
        .padding(.vertical, 6)
    }
}
