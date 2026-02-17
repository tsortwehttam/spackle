import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var ctl: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
            }

            if ctl.hasAccessibility {
                if ctl.settings.typedEnabled {
                    Button {
                        if ctl.state == .paused {
                            ctl.resume()
                        } else {
                            ctl.pause()
                        }
                    } label: {
                        Text(ctl.state == .paused ? "▶️ Resume Listening" : "⏸️ Pause Listening")
                    }
                }

                Button {
                    ctl.rewriteSelectionNow()
                } label: {
                    Text("Rewrite Selection (\(ctl.settings.rewriteShortcut.displayName))")
                }
            }

            HStack(spacing: 8) {
                Button("About & Settings") {
                    ctl.showAbout()
                }
                if ctl.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Label("api key set", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private var statusText: String {
        if ctl.state == .awaiting || ctl.state == .replacing {
            return "Spackling..."
        }
        if ctl.state == .paused {
            return "Paused"
        }
        if ctl.hasAccessibility == false {
            return "Accessibility Required"
        }
        return "Ready"
    }

    private var statusColor: Color {
        if ctl.state == .awaiting || ctl.state == .replacing {
            return .blue
        }
        if ctl.state == .paused || ctl.hasAccessibility == false {
            return .red
        }
        return .green
    }
}
