import SwiftUI

struct SettingsView: View {
    @ObservedObject var ctl: AppController
    private let providers: [ProviderKind] = [.openAI, .anthropic, .openRouter]
    private let SPACE_XXS: CGFloat = 4
    private let SPACE_XS: CGFloat = 8
    private let SPACE_SM: CGFloat = 10
    private let SPACE_MD: CGFloat = 12

    var body: some View {
        Form {
            Section {
                    VStack(alignment: .leading, spacing: SPACE_SM) {
                        Text("Settings")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Use AI to fill gaps in your writing anywhere on macOS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("How it Works")
                            .font(.system(size: 13, weight: .semibold))

                        VStack(alignment: .leading, spacing: SPACE_XS) {
                            HStack(spacing: SPACE_XS) {
                                Text("1.")
                                Button("Grant Accessibility") {
                                    ctl.requestAccessibility()
                                }
                                Spacer()
                                calcStatusBadge("Granted", isVisible: ctl.hasAccessibility)
                            }
                            Text("Required so Spackle can read and replace text in other apps.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: SPACE_XS) {
                                Text("2.")
                                Text("Choose your provider and model, then add your API key.")
                                Spacer()
                                calcStatusBadge("API Key Set", isVisible: hasApiKey)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: SPACE_XS) {
                                Text("3.")
                                Text("Select text anywhere on your Mac, then press \(ctl.settings.rewriteShortcut.displayName) to rewrite with AI.")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12))

                        HStack(spacing: SPACE_XS) {
                            Text("Spackle is free software.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Link("☕ Leave us a tip", destination: URL(string: "https://aisatsu.co/tips/")!)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            Section {
                    Picker("Provider", selection: $ctl.settings.provider) {
                        ForEach(providers) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }

                    HStack {
                        Text("Model")
                        Spacer()
                        ModelComboBox(
                            value: $ctl.settings.model,
                            options: ModelCatalog.calcOptions(provider: ctl.settings.provider)
                        )
                        .frame(width: 320)
                    }

                    SecureField("API key", text: $ctl.apiKey)
                } header: {
                    Text("AI Provider")
                }

            Section("Selection Rewrite") {
                    Picker("Shortcut", selection: $ctl.settings.rewriteShortcut) {
                        ForEach(RewriteShortcut.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                }

            Section {
                    Toggle("Enable typed triggers", isOn: $ctl.settings.typedEnabled)

                    Group {
                        TextField("Typed start", text: $ctl.settings.typedStart)
                        TextField("Typed end", text: $ctl.settings.typedEnd)
                    }
                    .disabled(ctl.settings.typedEnabled == false)
                    .opacity(ctl.settings.typedEnabled ? 1 : 0.5)
                } header: {
                    Text("Typed Delimiters")
                } footer: {
                    Text("Type a start and end delimiter in your text to trigger automatic replacement.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            Section {
                    Toggle("Enable spoken triggers", isOn: $ctl.settings.spokenEnabled)

                    Group {
                        TextField("Spoken start", text: $ctl.settings.spokenStart)
                        TextField("Spoken end", text: $ctl.settings.spokenEnd)
                    }
                    .disabled(ctl.settings.spokenEnabled == false)
                    .opacity(ctl.settings.spokenEnabled ? 1 : 0.5)
                } header: {
                    Text("Spoken Delimiters")
                } footer: {
                    Text("If you're using dictation or transcription, spoken delimiters can trigger auto-replace.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            Section("Rewrite Context") {
                    HStack {
                        Text("Chars before")
                        Spacer()
                        Text("\(ctl.settings.contextBeforeChars)")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        Stepper("", value: $ctl.settings.contextBeforeChars, in: 0...5000, step: 25)
                            .labelsHidden()
                    }

                    HStack {
                        Text("Chars after")
                        Spacer()
                        Text("\(ctl.settings.contextAfterChars)")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        Stepper("", value: $ctl.settings.contextAfterChars, in: 0...5000, step: 25)
                            .labelsHidden()
                    }
                }

            Section("AI System Prompt") {
                    Text("Use \(AppSettings.inputPlaceholder) where the extracted text should be inserted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $ctl.settings.systemPromptTemplate)
                        .frame(minHeight: 140)

                    Button("Restore Default Prompt") {
                        ctl.settings.systemPromptTemplate = AppSettings.default.systemPromptTemplate
                    }
                }

            Section("Behavior") {
                    HStack {
                        Text("Trigger delay (ms)")
                        Spacer()
                        Text("\(ctl.settings.triggerDelayMs)")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                        Stepper("", value: $ctl.settings.triggerDelayMs, in: 0...1500, step: 50)
                            .labelsHidden()
                    }
                }

            Section {
                Toggle("Use clipboard fallback", isOn: $ctl.settings.useClipboardFallback)
            } header: {
                Text("Advanced")
            } footer: {
                VStack(alignment: .leading, spacing: SPACE_XXS) {
                    Text("Copyright © 2026")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: SPACE_XS) {
                        Link("Aisatsu LLC", destination: URL(string: "https://aisatsu.co")!)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Link("Privacy", destination: URL(string: "https://aisatsu.co/privacy")!)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Link("Terms", destination: URL(string: "https://aisatsu.co/terms")!)
                    }
                    .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SPACE_MD)
            }
        }
        .formStyle(.grouped)
        .padding(SPACE_MD)
        .frame(minWidth: 640, minHeight: 700)
        .onDisappear {
            ctl.saveSettings()
            ctl.saveAPIKey()
        }
    }

    @ViewBuilder
    private func calcStatusBadge(_ text: String, isVisible: Bool) -> some View {
        if isVisible {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, SPACE_XS)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.12))
                )
        }
    }

    private var hasApiKey: Bool {
        ctl.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
