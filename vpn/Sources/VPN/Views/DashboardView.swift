import AppKit
import SwiftUI

/// The main screen once the VPN runs: server status, this Mac, and every device.
struct DashboardView: View {
    @EnvironmentObject private var model: VPNModel
    @State private var removing: Device?
    @State private var confirmUninstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                serverCard
                thisMacCard

                HStack {
                    Text("Devices").font(.title2.bold())
                    if model.busy { ProgressView().controlSize(.small).padding(.leading, 4) }
                    Spacer()
                    Button { model.showAddDevice = true } label: {
                        Label("Add Device", systemImage: "plus")
                    }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(model.busy)
                }
                .padding(.top, 6)

                if model.devices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("No devices yet").font(.headline)
                        Text("Add your phone, tablet or laptop. You'll get a QR code to scan with the WireGuard app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .card(padding: 28)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.devices) { device in
                            DeviceRow(device: device,
                                      onShow: { Task { await model.showDevice(device.name) } },
                                      onRemove: { removing = device })
                            if device != model.devices.last { Divider().padding(.leading, 64) }
                        }
                    }
                    .card(padding: 0)
                }
            }
            .padding(28)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(model.busy)
                Menu {
                    Button("Use a Different Server…") { model.signOut() }
                    if model.macImported {
                        Button("Send This Mac's Config to WireGuard Again") {
                            Task { await model.resendMacConfig() }
                        }
                    }
                    Divider()
                    Button("Remove VPN from Server…", role: .destructive) { confirmUninstall = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Remove \(removing?.name ?? "this device")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { device in
            Button("Remove", role: .destructive) { Task { await model.removeDevice(device.name) } }
        } message: { _ in
            Text("It will no longer be able to connect. You can add it again later with a new code.")
        }
        .confirmationDialog("Remove the VPN from your server?", isPresented: $confirmUninstall) {
            Button("Remove VPN", role: .destructive) { Task { await model.uninstallServer() } }
        } message: {
            Text("Every device stops working and all device configs are deleted. You can install it again afterwards.")
        }
        .sheet(item: $model.shownConfig) { config in
            DeviceConfigSheet(config: config)
        }
        .background(EmptyView().sheet(isPresented: $model.showAddDevice) {
            AddDeviceSheet().environmentObject(model)
        })
        .task {
            // Keep "last seen" and traffic current while the window is open.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await model.refresh(silently: true)
            }
        }
    }

    @ViewBuilder private var serverCard: some View {
        if let server = model.server {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.brand).frame(width: 46, height: 46)
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your VPN server").font(.headline)
                    Text("\(server.endpoint) · UDP port \(server.port)")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(server.running ? Theme.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(server.running ? "Running" : "Stopped")
                        .font(.callout.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .card()
        }
    }

    private var thisMacCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer")
                .font(.title)
                .foregroundStyle(Theme.teal)
                .frame(width: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("This Mac").font(.headline)
                Text(model.macImported
                     ? "Set up as \u{201C}\(model.macDeviceName)\u{201D}. Turn the VPN on or off in the WireGuard app or menu bar."
                     : "Send this Mac's traffic through your VPN, using the free WireGuard app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(model.macImported ? "Open WireGuard" : "Connect This Mac") {
                Task { await model.connectThisMac() }
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(model.busy)
        }
        .card()
    }
}

struct DeviceRow: View {
    let device: Device
    let onShow: () -> Void
    let onRemove: () -> Void

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.symbol)
                .font(.title2)
                .frame(width: 34)
                .foregroundStyle(device.isOnline ? Theme.teal : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.body.weight(.semibold))
                Text(device.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(device.statusText)
                    .font(.callout)
                    .foregroundStyle(device.isOnline ? Theme.green : Color.secondary)
                if device.uploaded + device.downloaded > 0 {
                    Text("↓ \(bytes(device.downloaded))  ↑ \(bytes(device.uploaded))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: onShow) { Image(systemName: "qrcode") }
                .buttonStyle(.borderless)
                .help("Show QR code and config")
            Button(action: onRemove) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove device")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct AddDeviceSheet: View {
    @EnvironmentObject private var model: VPNModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var taken: Bool { model.devices.contains { $0.name == name } }
    private var valid: Bool { VPNModel.isValidName(name) && !taken }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a device").font(.title2.bold())
            Text("Pick a name you'll recognize, like iphone or work-laptop. Use letters, numbers, - and _.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("iphone", text: $name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: name) { newValue in
                    let cleaned = newValue.replacingOccurrences(of: " ", with: "-")
                    if cleaned != newValue { name = cleaned }
                }
            if taken {
                Text("You already have a device with that name.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Device") {
                    let chosen = name
                    dismiss()
                    Task { await model.addDevice(chosen) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

/// QR code for phones, plus copy/save for computers.
struct DeviceConfigSheet: View {
    let config: DeviceConfig
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Text(config.name).font(.title2.bold())
            Text("On a phone or tablet: open the WireGuard app, tap +, then Scan from QR Code.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let qr = QRCode.image(for: config.text) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 250, height: 250)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("On a computer: save the config file and import it in the WireGuard app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(copied ? "Copied" : "Copy Config") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(config.text, forType: .string)
                    copied = true
                }
                Button("Save Config File…", action: save)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Label("This contains the device's private key. Share it only with that device.", systemImage: "key.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(config.name).conf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try config.text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSSound.beep()
        }
    }
}
