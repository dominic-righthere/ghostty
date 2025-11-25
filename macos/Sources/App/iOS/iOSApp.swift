import SwiftUI

@main
struct Ghostty_iOSApp: App {
    @StateObject private var ghostty_app = Ghostty.App()

    var body: some Scene {
        WindowGroup {
            iOS_GhosttyTerminal()
                .environmentObject(ghostty_app)
        }
    }
}

struct iOS_GhosttyTerminal: View {
    @EnvironmentObject private var ghostty_app: Ghostty.App
    @State private var showShellInfo = true

    var body: some View {
        ZStack {
            // Make sure that our background color extends to all parts of the screen
            Color(ghostty_app.config.backgroundColor).ignoresSafeArea()

            // Terminal view (always present, even if no shell)
            Ghostty.Terminal()

            // Show shell configuration info overlay on first launch
            if showShellInfo {
                ShellConfigurationOverlay(isPresented: $showShellInfo)
            }
        }
    }
}

/// Overlay shown on first launch to explain shell configuration
struct ShellConfigurationOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("Ghostty Terminal for iOS")
                    .font(.title)
                    .fontWeight(.bold)

                Text("MVP - Terminal Input/Output Ready!")
                    .font(.headline)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "checkmark.circle.fill", text: "Full keyboard support", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "Touch gestures (scroll, zoom)", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "Metal-accelerated rendering", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "Pipe-based PTY (iOS sandbox)", color: .green)
                    FeatureRow(icon: "info.circle.fill", text: "Shell integration: See docs", color: .orange)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)

                Text("Next Steps:")
                    .font(.headline)
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Add ios_system framework for local commands")
                    Text("2. Or add SSH client for remote shells")
                    Text("3. Configure shell in Settings")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                Button(action: {
                    isPresented = false
                }) {
                    Text("Continue to Terminal")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: 500)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}

struct iOS_GhosttyInitView: View {
    @EnvironmentObject private var ghostty_app: Ghostty.App

    var body: some View {
        VStack {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 96)
            Text("Ghostty")
            Text("State: \(ghostty_app.readiness.rawValue)")
        }
        .padding()
    }
}
