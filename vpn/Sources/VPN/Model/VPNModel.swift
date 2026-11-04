import AppKit
import SwiftUI

struct ServerInfo: Equatable {
    var endpoint: String
    var port: String
    var running: Bool
}

struct Device: Identifiable, Equatable {
    var name: String
    var address: String
    var lastHandshake: Date?
    /// Bytes the server received from the device (the device's upload).
    var uploaded: Int64
    /// Bytes the server sent to the device (the device's download).
    var downloaded: Int64

    var id: String { name }

    /// WireGuard handshakes every two minutes while a device is active.
    var isOnline: Bool {
        guard let lastHandshake else { return false }
        return Date().timeIntervalSince(lastHandshake) < 180
    }

    var statusText: String {
        if isOnline { return "Connected" }
        guard let lastHandshake else { return "Never connected" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last seen " + formatter.localizedString(for: lastHandshake, relativeTo: Date())
    }

    var symbol: String {
        let n = name.lowercased()
        if ["iphone", "phone", "android", "pixel", "galaxy", "mobile"].contains(where: { n.contains($0) }) { return "iphone" }
        if ["ipad", "tablet"].contains(where: { n.contains($0) }) { return "ipad" }
        if ["mac", "laptop", "book", "notebook"].contains(where: { n.contains($0) }) { return "laptopcomputer" }
        if n.contains("tv") { return "appletv" }
        return "desktopcomputer"
    }
}

struct DeviceConfig: Identifiable {
    let name: String
    let text: String
    var id: String { name }
}

@MainActor
final class VPNModel: ObservableObject {
    static let shared = VPNModel()

    enum Phase: Equatable {
        case signedOut, connecting, needsInstall, installing, ready
    }

    @Published var phase: Phase = .signedOut
    @Published private(set) var profile: ServerProfile?
    @Published private(set) var password: String?
    @Published private(set) var server: ServerInfo?
    @Published private(set) var devices: [Device] = []
    @Published private(set) var installLog: [String] = []
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var toast: String?
    @Published var shownConfig: DeviceConfig?
    @Published var showAddDevice = false
    @Published var needsWireGuard = false

    private init() {
        if let saved = ServerProfile.load() {
            profile = saved
            if saved.auth == .password { password = Keychain.password(for: saved.keychainAccount) }
            Task { await connect(isNew: false) }
        }
    }

    // MARK: Server

    func signIn(_ newProfile: ServerProfile, password newPassword: String) async {
        profile = newProfile
        password = newProfile.auth == .password ? newPassword : nil
        await connect(isNew: true)
    }

    private func connect(isNew: Bool) async {
        guard let profile else { return }
        phase = .connecting
        do {
            try await uploadScript()
            if isNew {
                profile.save()
                if let password { Keychain.setPassword(password, for: profile.keychainAccount) }
            }
            try await loadStatus()
        } catch {
            self.error = error.localizedDescription
            phase = .signedOut
        }
    }

    func signOut() {
        if let profile { Keychain.delete(profile.keychainAccount) }
        ServerProfile.clear()
        try? FileManager.default.removeItem(at: SSH.knownHosts)
        UserDefaults.standard.removeObject(forKey: macImportedKey)
        profile = nil
        password = nil
        server = nil
        devices = []
        installLog = []
        phase = .signedOut
    }

    func install() async {
        phase = .installing
        installLog = []
        do {
            try await runScript("install") { line in
                DispatchQueue.main.async { VPNModel.shared.installLog.append(line) }
            }
            try await loadStatus()
            toast = "Your VPN is running"
        } catch {
            self.error = error.localizedDescription
            phase = .needsInstall
        }
    }

    func uninstallServer() async {
        await perform {
            try await self.runScript("uninstall --yes")
            UserDefaults.standard.removeObject(forKey: self.macImportedKey)
            self.server = nil
            self.devices = []
            self.installLog = []
            self.phase = .needsInstall
        }
    }

    func refresh(silently: Bool = false) async {
        guard phase == .ready, !busy else { return }
        if silently {
            try? await loadStatus()
        } else {
            await perform { try await self.loadStatus() }
        }
    }

    var installStep: String {
        installLog.last(where: { $0.hasPrefix("==> ") }).map { String($0.dropFirst(4)) } ?? "Starting…"
    }

    // MARK: Devices

    static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil
    }

    func addDevice(_ name: String) async {
        guard Self.isValidName(name) else {
            error = "Device names use letters, numbers, - and _ (up to 32 characters)."
            return
        }
        await perform {
            try await self.runScript("add \(name)")
            try await self.loadDevices()
            let text = try await self.runScript("export \(name)")
            self.shownConfig = DeviceConfig(name: name, text: text)
        }
    }

    func showDevice(_ name: String) async {
        guard Self.isValidName(name) else { return }
        await perform {
            let text = try await self.runScript("export \(name)")
            self.shownConfig = DeviceConfig(name: name, text: text)
        }
    }

    func removeDevice(_ name: String) async {
        guard Self.isValidName(name) else { return }
        await perform {
            try await self.runScript("remove \(name)")
            if name == self.macDeviceName { UserDefaults.standard.removeObject(forKey: self.macImportedKey) }
            try await self.loadDevices()
            self.toast = "Removed \(name)"
        }
    }

    // MARK: This Mac

    /// A device name derived from the Mac's name, e.g. "Sam's MacBook Air" → "sams-macbook-air".
    var macDeviceName: String {
        let raw = Host.current().localizedName ?? ""
        var result = ""
        for character in raw.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                result.append(character)
            } else if character == " " || character == "-" || character == "_" {
                if !result.isEmpty && result.last != "-" { result.append("-") }
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        result = String(result.prefix(32))
        return result.isEmpty ? "this-mac" : result
    }

    private var macImportedKey: String { "macImported:\(profile?.keychainAccount ?? "")" }

    var macImported: Bool {
        UserDefaults.standard.bool(forKey: macImportedKey) && devices.contains { $0.name == macDeviceName }
    }

    static let wireGuardBundleID = "com.wireguard.macos"
    static let wireGuardStoreURL = URL(string: "https://apps.apple.com/app/wireguard/id1451685025")!

    var macConfigFile: URL { SSH.supportDirectory.appendingPathComponent("MyVPN.conf") }

    /// Gets this Mac's config from the server and hands it to the WireGuard app, which runs the tunnel.
    func connectThisMac() async {
        let wireGuard = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.wireGuardBundleID)
        if macImported, let wireGuard {
            NSWorkspace.shared.openApplication(at: wireGuard, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let name = macDeviceName
        await perform {
            if !self.devices.contains(where: { $0.name == name }) {
                try await self.runScript("add \(name)")
                try await self.loadDevices()
            }
            let text = try await self.runScript("export \(name)")
            let file = self.macConfigFile
            try text.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

            guard let wireGuard else {
                self.needsWireGuard = true
                return
            }
            NSWorkspace.shared.open([file], withApplicationAt: wireGuard,
                                    configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            UserDefaults.standard.set(true, forKey: self.macImportedKey)
            self.objectWillChange.send()
            self.toast = "Sent to WireGuard: allow the VPN configuration, then click Activate"
        }
    }

    func resendMacConfig() async {
        UserDefaults.standard.removeObject(forKey: macImportedKey)
        await connectThisMac()
    }

    func revealMacConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([macConfigFile])
    }

    // MARK: Plumbing

    private func perform(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadStatus() async throws {
        let output = try await runScript("status")
        let line = output.split(separator: "\n").last.map(String.init) ?? ""
        let fields = line.components(separatedBy: "\t")
        if fields.first == "installed", fields.count >= 4 {
            server = ServerInfo(endpoint: fields[1], port: fields[2], running: fields[3] == "running")
            try await loadDevices()
            phase = .ready
        } else {
            server = nil
            devices = []
            phase = .needsInstall
        }
    }

    private func loadDevices() async throws {
        let output = try await runScript("list --tsv")
        devices = output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2, !f[0].isEmpty else { return nil }
            let handshake = f.count > 2 ? TimeInterval(f[2]) ?? 0 : 0
            return Device(name: f[0], address: f[1],
                          lastHandshake: handshake > 0 ? Date(timeIntervalSince1970: handshake) : nil,
                          uploaded: f.count > 3 ? Int64(f[3]) ?? 0 : 0,
                          downloaded: f.count > 4 ? Int64(f[4]) ?? 0 : 0)
        }
    }

    private var ssh: SSH {
        get throws {
            guard let profile else { throw RemoteError(message: "No server is set up.") }
            return SSH(profile: profile, password: password)
        }
    }

    /// The server script ships inside the app; it's copied to the server on every connect so it stays current.
    private func uploadScript() async throws {
        let bundled = Bundle.main.url(forResource: "vpn", withExtension: "sh")
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("vpn.sh")
        guard let url = bundled ?? (FileManager.default.fileExists(atPath: local.path) ? local : nil),
              let data = try? Data(contentsOf: url) else {
            throw RemoteError(message: "The server script is missing from the app. Download VPN again.")
        }
        try await ssh.run("mkdir -p ~/.vpn-app && cat > ~/.vpn-app/vpn.sh", input: data)
    }

    /// Runs the server script with administrator rights.
    @discardableResult
    private func runScript(_ arguments: String, onLine: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let client = try ssh
        let script = "bash ~/.vpn-app/vpn.sh \(arguments)"
        if client.profile.isRoot {
            return try await client.run(script, onLine: onLine)
        }
        if client.profile.auth == .password {
            let input = Data(((password ?? "") + "\n").utf8)
            return try await client.run("sudo -S -p '' \(script)", input: input, onLine: onLine)
        }
        return try await client.run("sudo -n \(script)", onLine: onLine)
    }
}
