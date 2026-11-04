import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.needsSetup {
                SetupWizardView()
            } else {
                MainView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Show Log") {
                model.errorMessage = nil
                model.showLog = true
            }
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch model.sidebar {
                    case .bottle(let url):
                        if let bottle = model.bottle(for: url) {
                            BottleDetailView(bottle: bottle)
                        } else {
                            LibraryView()
                        }
                    case .library, .none:
                        LibraryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.showLog {
                    Divider()
                    LogView()
                        .frame(minHeight: 150, idealHeight: 220, maxHeight: 360)
                        .transition(.move(edge: .bottom))
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastView(text: toast)
                        .padding(.bottom, model.showLog ? 240 : 22)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: 2_600_000_000)
                            withAnimation { model.toast = nil }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
            .animation(.easeInOut(duration: 0.2), value: model.showLog)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.chooseAndRun()
                } label: {
                    Label("Run Program", systemImage: "play.fill")
                }
                .help("Run a Windows program or installer")

                Button {
                    withAnimation { model.showLog.toggle() }
                } label: {
                    Label("Log", systemImage: "text.alignleft")
                }
                .help("Show what Windows programs are printing (⇧⌘L)")
            }
        }
        .sheet(isPresented: $model.showNewBottle) {
            NewBottleSheet()
                .environmentObject(model)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var renaming: URL?
    @State private var newName = ""
    @State private var confirmDelete: Bottle?

    var body: some View {
        List(selection: $model.sidebar) {
            Label {
                HStack {
                    Text("Library")
                    Spacer()
                    Text("\(model.library.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(Theme.brand)
            }
            .tag(SidebarItem.library)

            Section("Bottles") {
                ForEach(model.bottles) { bottle in
                    HStack(spacing: 8) {
                        BottleBadge(name: bottle.config.name, size: 20)
                        Text(bottle.config.name)
                            .lineLimit(1)
                        Spacer()
                        if model.busyBottles.contains(bottle.url) {
                            ProgressView().controlSize(.mini)
                        } else if model.running.contains(where: { $0.bottleURL == bottle.url }) {
                            Circle().fill(.green).frame(width: 7, height: 7)
                                .help("Programs running")
                        }
                    }
                    .tag(SidebarItem.bottle(bottle.url))
                    .contextMenu {
                        Button("Rename…") {
                            newName = bottle.config.name
                            renaming = bottle.url
                        }
                        Button("Use for Files Opened from Finder") {
                            model.defaultBottleURL = bottle.url
                        }
                        Button("Open C: Drive") { model.openDriveC(bottle) }
                        Divider()
                        Button("Delete Bottle…", role: .destructive) { confirmDelete = bottle }
                    }
                }
            }

            if !model.running.isEmpty {
                Section("Running") {
                    ForEach(model.running) { program in
                        HStack(spacing: 8) {
                            if program.path.isEmpty {
                                Image(systemName: "app.dashed").frame(width: 20)
                            } else {
                                ProgramIcon(url: URL(fileURLWithPath: program.path), name: program.name, size: 20)
                            }
                            Text(program.name).lineLimit(1)
                        }
                        .contextMenu {
                            Button("Force Quit") { program.process.terminate() }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.showNewBottle = true
            } label: {
                Label("New Bottle", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .alert("Rename Bottle", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.renameBottle(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete “\(confirmDelete?.config.name ?? "")”?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let confirmDelete { model.deleteBottle(confirmDelete.url) }
                confirmDelete = nil
            }
        } message: {
            Text("Every program installed in this bottle goes to the Trash with it.")
        }
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Log", systemImage: "text.alignleft").font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logText, forType: .string)
                }
                Button("Clear") { model.clearLog() }
                Button {
                    withAnimation { model.showLog = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.logText.isEmpty ? "Output from Windows programs appears here." : model.logText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(model.logText.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: model.logText) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
