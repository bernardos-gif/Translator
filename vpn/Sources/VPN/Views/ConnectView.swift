import AppKit
import SwiftUI

/// First screen: where the server is and how to sign in to it.
struct ConnectView: View {
    @EnvironmentObject private var model: VPNModel

    @State private var host = ""
    @State private var user = "root"
    @State private var port = "22"
    @State private var auth: ServerProfile.Auth = .password
    @State private var password = ""
    @State private var keyPath = ""

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canConnect: Bool {
        guard !trimmedHost.isEmpty, !user.trimmingCharacters(in: .whitespaces).isEmpty,
              let portNumber = Int(port), (1...65535).contains(portNumber) else { return false }
        return auth == .key || !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AppIconView(size: 92)

                VStack(spacing: 8) {
                    Text("Your own private VPN")
                        .font(.largeTitle.bold())
                    Text("Connect a Linux server you rent (any small cloud server works) and this app turns it into a VPN for all your devices.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                }

                VStack(alignment: .leading, spacing: 14) {
                    field("Server address") {
                        TextField("203.0.113.7 or vpn.example.com", text: $host)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        field("Username") { TextField("root", text: $user) }
                        field("SSH port") { TextField("22", text: $port).frame(width: 70) }
                    }
                    field("Sign in with") {
                        Picker("Sign in with", selection: $auth) {
                            Text("Password").tag(ServerProfile.Auth.password)
                            Text("SSH key").tag(ServerProfile.Auth.key)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    if auth == .password {
                        field("Password") { SecureField("Server password", text: $password) }
                    } else {
                        field("Key file") {
                            HStack {
                                TextField("Default keys in ~/.ssh", text: $keyPath)
                                Button("Choose…", action: chooseKey)
                            }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .card(padding: 20)

                Button(action: connect) {
                    Text("Connect").frame(minWidth: 160)
                }
                .buttonStyle(GradientButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!canConnect)

                Text("The app signs in to your server over SSH and sets up WireGuard there. Your traffic only goes through your own server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: prefill)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func prefill() {
        guard let profile = model.profile else { return }
        host = profile.host
        user = profile.user
        port = String(profile.port)
        auth = profile.auth
        keyPath = profile.keyPath
        password = model.password ?? ""
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.title = "Choose your SSH private key"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            keyPath = url.path
        }
    }

    private func connect() {
        let profile = ServerProfile(host: trimmedHost,
                                    user: user.trimmingCharacters(in: .whitespaces),
                                    port: Int(port) ?? 22,
                                    auth: auth,
                                    keyPath: auth == .key ? keyPath : "")
        let secret = password
        Task { await model.signIn(profile, password: secret) }
    }
}
