import AppKit
import SwiftUI

/// Shown until a Wine installation is found.
struct SetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Translator")
                        .font(.largeTitle.weight(.bold))
                    Text("Translator runs Windows programs on your Mac using Wine, a free compatibility layer that translates Windows calls into macOS ones on the fly. Wine is a separate download; install it once and Translator finds it automatically.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if WineRuntime.needsRosetta {
                    StepCard(
                        number: 1,
                        title: "Install Rosetta 2",
                        detail: "Wine for macOS is built for Intel, so Apple Silicon Macs run it through Rosetta.",
                        command: "softwareupdate --install-rosetta --agree-to-license"
                    )
                }

                StepCard(
                    number: WineRuntime.needsRosetta ? 2 : 1,
                    title: "Install Wine with Homebrew",
                    detail: "If you don't have Homebrew yet, get it from brew.sh first. Then run:",
                    command: "brew install --cask wine-stable && xattr -drs com.apple.quarantine \"/Applications/Wine Stable.app\""
                )

                StepCard(
                    number: WineRuntime.needsRosetta ? 3 : 2,
                    title: "…or download Wine directly",
                    detail: "Download “wine-stable” for macOS, unzip it, and drag “Wine Stable.app” into Applications. Then clear the download flag so macOS lets it run:",
                    command: "xattr -drs com.apple.quarantine \"/Applications/Wine Stable.app\"",
                    link: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases")
                )

                HStack(spacing: 12) {
                    Button {
                        model.refreshRuntime()
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Choose Wine Manually…") { model.chooseWineBinary() }
                        .controlSize(.large)

                    Button("Open Terminal") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    }
                    .controlSize(.large)
                }

                Text("Already use CrossOver, Whisky or another Wine build? Choose its `wine` or `wine64` binary manually.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(36)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from Terminal: look again automatically.
            model.refreshRuntime()
        }
    }
}

private struct StepCard: View {
    let number: Int
    let title: String
    let detail: String
    let command: String
    var link: URL?

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    Link(link.absoluteString, destination: link)
                }
                HStack(alignment: .top) {
                    Text(command)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                }
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
