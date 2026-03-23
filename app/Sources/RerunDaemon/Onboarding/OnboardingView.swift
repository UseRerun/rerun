import SwiftUI

enum OnboardingDismissal {
    case automatic
    case explicit
}

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel
    var onDismiss: (OnboardingDismissal) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .padding(.bottom, 4)
                Text("Welcome to Rerun")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("A few things to set up before we begin.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Setup items
            VStack(spacing: 12) {
                SetupItemView(
                    title: "Accessibility",
                    description: "Read text from any window on screen",
                    isComplete: viewModel.accessibilityGranted,
                    actionLabel: "Grant Access",
                    action: viewModel.requestAccessibility
                )

                SetupItemView(
                    title: "Screen Recording",
                    description: "Capture screen content when text isn't available",
                    isComplete: viewModel.screenRecordingGranted,
                    actionLabel: "Grant Access",
                    action: viewModel.requestScreenRecording
                )

                if viewModel.showsAppManagementPrompt {
                    AppManagementSetupItemView(action: viewModel.openAppManagementSettings)
                }

                ModelSetupItemView(state: viewModel.modelState)
            }
            .padding(.horizontal, 28)

            Spacer()

            // Footer
            Button("Get Started") { onDismiss(.explicit) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.isComplete)
                .padding(.bottom, 24)
        }
        .frame(width: 440, height: 520)
        .onChange(of: viewModel.isComplete) { _, complete in
            if complete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [onDismiss] in
                    onDismiss(.automatic)
                }
            }
        }
    }
}

// MARK: - Setup Item Row

private struct SetupItemView: View {
    let title: String
    let description: String
    let isComplete: Bool
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isComplete ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isComplete {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Model Download Row

private struct AppManagementSetupItemView: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("App Management").font(.headline)
                Text("Optional. Recommended for automatic updates on the production app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Settings", action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ModelSetupItemView: View {
    let state: ModelManager.ModelState

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .ready:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                default:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.title3)
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Model").font(.headline)
                switch state {
                case .idle:
                    Text("Preparing download\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .downloading(let progress):
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .frame(width: 100)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                case .ready:
                    Text("Downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
