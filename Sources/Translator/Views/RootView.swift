import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.runtime == nil {
                SetupView()
            } else {
                MainView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
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
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                if let bottle = model.selectedBottle {
                    BottleDetailView(bottle: bottle)
                } else {
                    EmptyBottlesView()
                }
                if model.showLog {
                    Divider()
                    LogView()
                        .frame(minHeight: 140, idealHeight: 200, maxHeight: 320)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.chooseAndRun()
                } label: {
                    Label("Run Program", systemImage: "play.fill")
                }
                .help("Run a Windows .exe or installer in the selected bottle")
                .disabled(model.bottles.isEmpty)

                Button {
                    model.showLog.toggle()
                } label: {
                    Label("Log", systemImage: "text.alignleft")
                }
                .help("Show Wine output")
            }
        }
        .sheet(isPresented: $model.showNewBottle) {
            NewBottleSheet()
                .environmentObject(model)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var renaming: URL?
    @State private var newName = ""
    @State private var confirmDelete: Bottle?

    var body: some View {
        List(selection: $model.selection) {
            Section("Bottles") {
                ForEach(model.bottles) { bottle in
                    HStack {
                        Label(bottle.config.name, systemImage: "shippingbox.fill")
                        Spacer()
                        if model.busyBottles.contains(bottle.url) {
                            ProgressView().controlSize(.small)
                        } else if model.running.contains(where: { $0.bottleURL == bottle.url }) {
                            Circle().fill(.green).frame(width: 7, height: 7)
                                .help("Programs running")
                        }
                    }
                    .tag(bottle.url)
                    .contextMenu {
                        Button("Rename…") {
                            newName = bottle.config.name
                            renaming = bottle.url
                        }
                        Button("Use for Files Opened from Finder") {
                            model.defaultBottleURL = bottle.url
                        }
                        Button("Show in Finder") { model.openDriveC(bottle) }
                        Divider()
                        Button("Delete Bottle…", role: .destructive) { confirmDelete = bottle }
                    }
                }
            }

            if !model.running.isEmpty {
                Section("Running") {
                    ForEach(model.running) { program in
                        Label(program.name, systemImage: "app.badge.checkmark")
                            .contextMenu {
                                Button("Force Quit") { program.process.terminate() }
                            }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.showNewBottle = true
            } label: {
                Label("New Bottle", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
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

struct EmptyBottlesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Create a bottle to get started")
                .font(.title2.weight(.semibold))
            Text("A bottle is a self-contained Windows environment with its own C: drive.\nInstall each program or game into a bottle, then launch it from here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("New Bottle…") { model.showNewBottle = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
