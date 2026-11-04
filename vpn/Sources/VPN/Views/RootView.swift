import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: VPNModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch model.phase {
                case .signedOut:
                    ConnectView()
                case .connecting:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Connecting to \(model.profile?.host ?? "your server")…")
                            .foregroundStyle(.secondary)
                    }
                case .needsInstall, .installing:
                    InstallView()
                case .ready:
                    DashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Something went wrong", isPresented: Binding(
                get: { model.error != nil },
                set: { if !$0 { model.error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }

            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        model.toast = nil
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .alert("Install WireGuard to connect this Mac", isPresented: $model.needsWireGuard) {
            Button("Get WireGuard") { NSWorkspace.shared.open(VPNModel.wireGuardStoreURL) }
            Button("Show Config File") { model.revealMacConfig() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WireGuard is the free app that runs the VPN connection on your Mac. Install it from the App Store, then click Connect This Mac again.")
        }
    }
}
