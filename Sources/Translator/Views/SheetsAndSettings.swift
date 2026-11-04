import AppKit
import SwiftUI

/// Ready-made bottle configurations.
enum BottlePreset: String, CaseIterable, Identifiable {
    case apps, games, legacy, blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .games: return "Games"
        case .legacy: return "Older Software"
        case .blank: return "Empty"
        }
    }

    var detail: String {
        switch self {
        case .apps: return "Windows 10 with fonts and Visual C++ runtimes."
        case .games: return "DXVK graphics plus DirectX, audio and controller libraries."
        case .legacy: return "Windows 7 with older Visual C++ runtimes."
        case .blank: return "Nothing extra. Add components later."
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "app.badge.fill"
        case .games: return "gamecontroller.fill"
        case .legacy: return "clock.arrow.circlepath"
        case .blank: return "square.dashed"
        }
    }

    var defaultName: String {
        switch self {
        case .apps: return "Apps"
        case .games: return "Games"
        case .legacy: return "Older Software"
        case .blank: return "New Bottle"
        }
    }

    var version: WindowsVersion { self == .legacy ? .win7 : .win10 }

    var components: [String] {
        switch self {
        case .apps: return ["corefonts", "vcrun2022"]
        case .games: return ["corefonts", "vcrun2022", "d3dx9", "d3dx10_43", "d3dx11_43", "d3dcompiler_47", "xact", "xinput"]
        case .legacy: return ["corefonts", "vcrun2005", "vcrun2008", "vcrun2010", "d3dx9"]
        case .blank: return []
        }
    }
}

struct NewBottleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var preset: BottlePreset = .apps
    @State private var name = ""
    @State private var version: WindowsVersion = .win10

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                BottleBadge(name: name.isEmpty ? preset.defaultName : name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Bottle").font(.title2.weight(.bold))
                    Text("A separate Windows environment. Give apps and games their own so they never clash.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(BottlePreset.allCases) { option in
                    PresetCard(preset: option, selected: preset == option)
                        .onTapGesture {
                            preset = option
                            version = option.version
                        }
                }
            }

            Form {
                TextField("Name", text: $name, prompt: Text(preset.defaultName))
                Picker("Windows version", selection: $version) {
                    ForEach(WindowsVersion.allCases) { Text($0.label).tag($0) }
                }
            }
            .formStyle(.columns)

            HStack {
                if model.winetricksURL == nil && !preset.components.isEmpty {
                    Label("Components will be skipped (installer missing).", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Bottle") { create() }
                    .buttonStyle(GradientButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 560)
    }

    private func create() {
        let finalName = name.isEmpty ? preset.defaultName : name
        let components = model.winetricksURL == nil ? [] : preset.components
        let wantsDXVK = preset == .games && model.dxvkAvailable
        Task {
            guard let bottle = await model.createBottle(name: finalName, version: version) else { return }
            if wantsDXVK { model.updateConfig(bottle.url) { $0.dxvk = true } }
            if !components.isEmpty { await model.installComponents(components, in: bottle.url) }
        }
        dismiss()
    }
}

private struct PresetCard: View {
    let preset: BottlePreset
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: preset.symbol)
                .font(.title2)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.brand))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.violet.opacity(0.12)))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title).font(.headline)
                Text(preset.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? Theme.violet.opacity(0.08) : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Theme.violet : Theme.cardStroke, lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReinstall = false

    var body: some View {
        Form {
            Section("Windows compatibility engine") {
                LabeledContent("Wine") {
                    Text(model.runtime.map { "\($0.source)" } ?? "Not installed")
                        .foregroundStyle(.secondary)
                }
                if let runtime = model.runtime {
                    LabeledContent("Location") {
                        Text(runtime.wineURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                LabeledContent("Component installer") {
                    Text(model.winetricksURL != nil ? "Ready" : "Missing")
                        .foregroundStyle(model.winetricksURL != nil ? Color.green : Color.orange)
                }
                LabeledContent("DXVK (DirectX → Metal)") {
                    Text(model.dxvkAvailable ? "Ready" : "Missing")
                        .foregroundStyle(model.dxvkAvailable ? Color.green : Color.orange)
                }
                HStack {
                    Button("Run Setup Again") { model.setupCompleted = false }
                        .help("Checks every part of Translator and reinstalls anything missing")
                    Button("Reinstall Wine…") { confirmReinstall = true }
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

            Section("Advanced") {
                LabeledContent("Custom Wine") {
                    HStack {
                        Text(model.customWinePath.isEmpty ? "Not set" : model.customWinePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { model.chooseWineBinary() }
                        if !model.customWinePath.isEmpty {
                            Button("Reset") { model.customWinePath = "" }
                        }
                    }
                }
                Text("Point Translator at another Wine build, for example CrossOver's or Apple's Game Porting Toolkit, to use its DirectX 12 support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .confirmationDialog("Reinstall Wine?", isPresented: $confirmReinstall, titleVisibility: .visible) {
            Button("Download and Reinstall", role: .destructive) {
                try? FileManager.default.removeItem(at: AppPaths.runtime)
                model.refreshRuntime()
                model.setupCompleted = false
            }
        } message: {
            Text("Your bottles and installed programs are kept. Translator downloads a fresh copy of Wine.")
        }
    }
}
