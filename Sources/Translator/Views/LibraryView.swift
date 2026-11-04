import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var dropTargeted = false

    private var items: [LibraryItem] {
        let all = model.library
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.bottleName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.library.isEmpty {
                    EmptyLibraryView()
                } else if items.isEmpty {
                    Text("No programs match “\(search)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ProgramGrid(items: items, showBottle: model.bottles.count > 1)
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $search, placement: .toolbar, prompt: "Search programs")
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(WindowsFileTypes.isWindowsFile)
            guard let target = model.defaultBottleURL.flatMap(model.bottle(for:)) ?? model.bottles.first else { return false }
            files.forEach { model.run($0, in: target) }
            return !files.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Theme.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(Label("Drop to run or install", systemImage: "arrow.down.app.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.violet))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { model.refreshAllPrograms() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.chooseAndRun()
            } label: {
                Label("Install or Run…", systemImage: "plus")
            }
            .buttonStyle(GradientButtonStyle())
        }
    }

    private var subtitle: String {
        let count = model.library.count
        let programs = count == 1 ? "1 program" : "\(count) programs"
        let bottles = model.bottles.count == 1 ? "1 bottle" : "\(model.bottles.count) bottles"
        return "\(programs) across \(bottles)"
    }
}

struct EmptyLibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 130, height: 130)
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.brand)
            }
            Text("Install your first Windows program")
                .font(.title2.weight(.semibold))
            Text("Download a Windows installer (setup.exe or .msi) like you would on a PC, then drop it here or choose it below. Installed programs appear in your library automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
            Button("Choose Installer…") { model.chooseAndRun() }
                .buttonStyle(GradientButtonStyle(large: true))
            HStack(spacing: 20) {
                Tip(symbol: "hand.point.up.left.fill", text: "Double-click .exe files in Finder")
                Tip(symbol: "square.and.arrow.down.fill", text: "Drag installers onto this window")
                Tip(symbol: "gamecontroller.fill", text: "Make a Games bottle for DirectX titles")
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .card(padding: 24, radius: 20)
    }

    private struct Tip: View {
        let symbol: String
        let text: String
        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.violet)
                Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(width: 150)
        }
    }
}

struct ProgramGrid: View {
    let items: [LibraryItem]
    var showBottle = true

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)], spacing: 16) {
            ForEach(items) { item in
                ProgramCard(item: item, showBottle: showBottle)
            }
        }
    }
}

struct ProgramCard: View {
    @EnvironmentObject private var model: AppModel
    let item: LibraryItem
    var showBottle = true

    @State private var hovering = false
    @State private var renaming = false
    @State private var newName = ""

    private var isRunning: Bool { model.isRunning(item.url) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ProgramIcon(url: item.url, name: item.name, size: 64)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .scaleEffect(hovering ? 1.06 : 1)
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Theme.violet, in: Circle())
                        .offset(x: 8, y: -6)
                }
            }
            .frame(height: 70)

            VStack(spacing: 3) {
                Text(item.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if showBottle {
                    Text(item.bottleName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                run()
            } label: {
                Label(isRunning ? "Running" : "Play", systemImage: isRunning ? "circle.fill" : "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .foregroundStyle(isRunning ? Color.green : Color.white)
            .background(
                Capsule().fill(isRunning ? AnyShapeStyle(Color.green.opacity(0.15)) : AnyShapeStyle(Theme.brand))
            )
            .opacity(hovering || isRunning ? 1 : 0.0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(hovering ? 0.14 : 0.05), radius: hovering ? 14 : 6, y: hovering ? 6 : 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hovering ? Theme.violet.opacity(0.45) : Theme.cardStroke, lineWidth: hovering ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .onTapGesture(count: 2) { run() }
        .help(item.url.path)
        .contextMenu {
            Button("Open") { run() }
            Divider()
            if item.isPinned {
                Button("Unpin") { model.unpin(path: item.url.path, in: item.bottleURL) }
            } else {
                Button("Pin to Top") { model.pin(item.url, in: item.bottleURL) }
            }
            Button("Rename…") {
                newName = item.name
                renaming = true
            }
            Button("Add Shortcut to Desktop") { model.createDesktopShortcut(for: item.url, in: item.bottleURL) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Hide from Library") { model.hide(path: item.url.path, in: item.bottleURL) }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { model.renameProgram(path: item.url.path, to: newName, in: item.bottleURL) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func run() {
        guard let bottle = model.bottle(for: item.bottleURL) else { return }
        model.run(item.url, in: bottle)
    }
}
