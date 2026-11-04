import AppKit
import SwiftUI

struct NewBottleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var version: WindowsVersion = .win10

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Bottle").font(.title2.weight(.semibold))
            Text("Give each app or game its own bottle so their settings never clash.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Games, Office, Old Stuff"))
                Picker("Windows version", selection: $version) {
                    ForEach(WindowsVersion.allCases) { Text($0.label).tag($0) }
                }
            }
            .formStyle(.columns)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    model.createBottle(name: name, version: version)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct LogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Wine Log").font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logText, forType: .string)
                }
                Button("Clear") { model.clearLog() }
                Button {
                    model.showLog = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

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

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var winePath = ""

    var body: some View {
        Form {
            Section("Wine") {
                LabeledContent("In use") {
                    Text(model.runtime.map { "\($0.source) — \($0.wineURL.path)" } ?? "Not found")
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Custom wine binary", text: $winePath, prompt: Text("Automatic"))
                        .onSubmit { model.customWinePath = winePath }
                    Button("Choose…") {
                        model.chooseWineBinary()
                        winePath = model.customWinePath
                    }
                    Button("Reset") {
                        winePath = ""
                        model.customWinePath = ""
                    }
                }
            }
            Section("Finder") {
                Picker("Open .exe files in", selection: Binding(
                    get: { model.defaultBottleURL },
                    set: { model.defaultBottleURL = $0 }
                )) {
                    Text("First bottle").tag(URL?.none)
                    ForEach(model.bottles) { bottle in
                        Text(bottle.config.name).tag(Optional(bottle.url))
                    }
                }
                LabeledContent("Bottles folder") {
                    Button("Show in Finder") { NSWorkspace.shared.open(model.rootURL) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onAppear { winePath = model.customWinePath }
    }
}
