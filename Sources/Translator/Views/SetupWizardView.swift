import SwiftUI

/// First-run experience: one button installs everything Translator needs.
struct SetupWizardView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var setup = SetupManager(model: AppModel.shared)

    private var started: Bool {
        setup.isRunning || setup.finished || setup.failed
    }

    var body: some View {
        ZStack {
            background
            HStack(spacing: 0) {
                intro
                    .frame(width: 360)
                    .padding(40)
                Divider().opacity(0.4)
                progressPanel
                    .padding(40)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Theme.brandSoft
            Circle()
                .fill(Theme.violet.opacity(0.18))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(x: -300, y: -220)
            Circle()
                .fill(Theme.pink.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: 360, y: 260)
        }
        .ignoresSafeArea()
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            AppIconView(size: 104)
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Translator")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Run Windows programs and games on your Mac. No Windows license, no virtual machine.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "arrow.down.circle.fill", title: "Everything included",
                        text: "Translator downloads and installs all it needs. Nothing for you to find or configure.")
                Feature(symbol: "gamecontroller.fill", title: "Apps and games",
                        text: "DirectX is translated to Metal, and common Windows runtimes are pre-installed.")
                Feature(symbol: "lock.shield.fill", title: "Neatly contained",
                        text: "Windows programs live in their own sandboxed folder, separate from your Mac's files.")
            }
            Spacer()
        }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(setup.finished ? "You're all set" : "Set up in one click")
                    .font(.title2.weight(.semibold))
                Text(setup.finished
                     ? "Translator is ready. Install a Windows program to get started."
                     : "Takes about 5–10 minutes and roughly 1.5 GB of space, depending on your connection.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(setup.steps) { step in
                    StepRow(step: step)
                    if step.id != setup.steps.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .card(padding: 6, radius: 16)

            if started && !setup.finished {
                ProgressView(value: setup.overallProgress)
                    .tint(Theme.violet)
            }

            if !started {
                Toggle(isOn: $setup.installEssentials) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pre-install essential Windows components (recommended)")
                        Text(ComponentCatalog.essentials.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: 0)

            HStack {
                if setup.failed {
                    Label("Setup stopped. Fix the issue above, then try again.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Spacer()
                if setup.finished {
                    Button("Start Using Translator") { model.setupFinished() }
                        .buttonStyle(GradientButtonStyle(large: true))
                        .keyboardShortcut(.defaultAction)
                } else if setup.failed {
                    Button("Show Log") { model.showLog = true }
                        .buttonStyle(PillButtonStyle())
                    Button("Try Again") { setup.start() }
                        .buttonStyle(GradientButtonStyle(large: true))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(setup.isRunning ? "Setting Up…" : "Set Up Translator") { setup.start() }
                        .buttonStyle(GradientButtonStyle(large: true))
                        .disabled(setup.isRunning)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .sheet(isPresented: $model.showLog) {
            LogView()
                .environmentObject(model)
                .frame(width: 720, height: 420)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StepRow: View {
    let step: SetupManager.Step

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 34, height: 34)
                icon
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.body.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isFailed ? Color.red : Color.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .running(let progress, _) = step.state, let progress {
                    ProgressView(value: progress)
                        .tint(Theme.violet)
                        .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: step.state)
    }

    private var isFailed: Bool {
        if case .failed = step.state { return true }
        return false
    }

    private var detail: String? {
        switch step.state {
        case .pending: return nil
        case .running(_, let detail): return detail
        case .done(let text), .skipped(let text), .failed(let text): return text
        }
    }

    private var iconBackground: Color {
        switch step.state {
        case .done: return .green.opacity(0.18)
        case .failed: return .red.opacity(0.18)
        case .running: return Theme.violet.opacity(0.18)
        default: return Color.primary.opacity(0.06)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch step.state {
        case .done:
            Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus").font(.body.weight(.bold)).foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(.red)
        case .running:
            ProgressView().controlSize(.small)
        case .pending:
            Image(systemName: step.symbol).foregroundStyle(.secondary)
        }
    }
}
