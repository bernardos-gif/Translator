import SwiftUI

/// Signed in, VPN not on the server yet: one button installs it, with live output.
struct InstallView: View {
    @EnvironmentObject private var model: VPNModel

    private var installing: Bool { model.phase == .installing }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)
            AppIconView(size: 76)

            if installing {
                Text("Installing the VPN on your server")
                    .font(.title.bold())
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.installStep).foregroundStyle(.secondary)
                }
            } else {
                Text("Connected to \(model.profile?.host ?? "your server")")
                    .font(.title.bold())
                Text("Installing sets up WireGuard, turns on secure routing and starts the VPN. It takes a minute or two, and the VPN keeps running after the server restarts.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 480)
                Button {
                    Task { await model.install() }
                } label: {
                    Text("Install VPN").frame(minWidth: 160)
                }
                .buttonStyle(GradientButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
                Button("Use a different server") { model.signOut() }
                    .buttonStyle(.link)
            }

            if !model.installLog.isEmpty {
                LogView(lines: model.installLog)
                    .frame(maxWidth: 640, maxHeight: 240)
            }
            Spacer(minLength: 24)
        }
        .padding(32)
    }
}
