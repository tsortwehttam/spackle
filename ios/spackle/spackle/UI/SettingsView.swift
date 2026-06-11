import SwiftUI

struct SettingsView: View {
    @ObservedObject var ctl: AppController
    @ObservedObject private var l10n = LocalizationManager.shared
    private let providers: [ProviderKind] = [.openAI, .anthropic, .openRouter, .custom]
    private let SPACE_XXS: CGFloat = 4
    private let SPACE_XS: CGFloat = 8
    private let SPACE_SM: CGFloat = 10
    private let SPACE_MD: CGFloat = 12

    var body: some View {
        Form {
            Section {
                    VStack(alignment: .leading, spacing: SPACE_SM) {
                        HStack {
                            Text(l10n.tr("Settings"))
                                .font(.system(size: 20, weight: .semibold))
                            Spacer()
                            Picker("Language", selection: $l10n.language) {
                                ForEach(Language.allCases) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .help(Text(verbatim: l10n.tr("Switch between English and Chinese.")))
                        }

                        Text(l10n.tr("Use AI to fill gaps in your writing anywhere on macOS."))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text(l10n.tr("How it Works"))
                            .font(.system(size: 13, weight: .semibold))

                        VStack(alignment: .leading, spacing: SPACE_XS) {
                            HStack(spacing: SPACE_XS) {
                                Text("1.")
                                Button(l10n.tr("Grant Accessibility")) {
                                    ctl.requestAccessibility()
                                }
                                Spacer()
                                calcStatusBadge(l10n.tr("Granted"), isVisible: ctl.hasAccessibility)
                            }
                            Text(l10n.tr("Required so Spackle can read and replace text in other apps."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: SPACE_XS) {
                                Text("2.")
                                Text(l10n.tr("Choose your provider and model, then add your API key."))
                                Spacer()
                                calcStatusBadge(l10n.tr("API Key Set"), isVisible: hasApiKey)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: SPACE_XS) {
                                Text("3.")
                                Text(buildStep3Text())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12))

                        HStack(spacing: SPACE_XS) {
                            Text(l10n.tr("Spackle is free software."))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Link("☕ \(l10n.tr("Leave us a tip"))", destination: URL(string: "https://aisatsu.co/tips/")!)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            Section {
                    Picker(l10n.tr("Provider"), selection: $ctl.settings.provider) {
                        ForEach(providers) { p in
                            Text(providerLabel(p)).tag(p)
                        }
                    }
                    .help(Text(verbatim: l10n.tr("Choose the AI provider that processes your text.")))

                    HStack {
                        HStack(spacing: SPACE_XS) {
                            Image(systemName: "cpu")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Text(l10n.tr("Model"))
                        }
                        Spacer()
                        ModelComboBox(
                            value: $ctl.settings.model,
                            options: ModelCatalog.calcOptions(provider: ctl.settings.provider)
                        )
                        .frame(width: 320)
                    }
                    .help(Text(verbatim: l10n.tr("The specific AI model to use. Type any model name for custom providers.")))

                    if ctl.settings.provider == .custom {
                        TextField(l10n.tr("Base URL (e.g. http://localhost:1234/v1/chat/completions)"), text: $ctl.settings.customBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        SecureField(l10n.tr("API key"), text: $ctl.apiKey)
                    }
                    .help(Text(verbatim: l10n.tr("Your API key for the selected provider.")))
                } header: {
                    Text(l10n.tr("AI Provider"))
                }

            Section {
                    HStack {
                        HStack(spacing: SPACE_XS) {
                            Image(systemName: "keyboard")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Text(l10n.tr("Shortcut"))
                        }
                        Spacer()
                        ShortcutRecorderView(shortcut: $ctl.settings.rewriteShortcut)
                    }
                    .help(Text(verbatim: l10n.tr("Keyboard shortcut to rewrite the selected text in place.")))
                } header: {
                    Text(l10n.tr("Selection Rewrite"))
                }

            Section {
                    Toggle(isOn: $ctl.settings.typedEnabled) {
                        HStack(spacing: SPACE_XS) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                            Text(l10n.tr("Enable typed triggers"))
                        }
                    }
                    .help(Text(verbatim: l10n.tr("Wrap your prompt in delimiters (e.g. <<prompt>>) in any text field to trigger AI rewriting.")))

                    Group {
                        TextField(l10n.tr("Typed start"), text: $ctl.settings.typedStart)
                        TextField(l10n.tr("Typed end"), text: $ctl.settings.typedEnd)
                    }
                    .disabled(ctl.settings.typedEnabled == false)
                    .opacity(ctl.settings.typedEnabled ? 1 : 0.5)
                } header: {
                    Text(l10n.tr("Typed Delimiters"))
                } footer: {
                    Text(l10n.tr("Type a start and end delimiter in your text to trigger automatic replacement."))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            Section {
                    Toggle(isOn: $ctl.settings.spokenEnabled) {
                        HStack(spacing: SPACE_XS) {
                            Image(systemName: "waveform")
                            Text(l10n.tr("Enable spoken triggers"))
                        }
                    }
                    .help(Text(verbatim: l10n.tr("When using dictation, say the start and end words to trigger AI rewriting.")))

                    Group {
                        TextField(l10n.tr("Spoken start"), text: $ctl.settings.spokenStart)
                        TextField(l10n.tr("Spoken end"), text: $ctl.settings.spokenEnd)
                    }
                    .disabled(ctl.settings.spokenEnabled == false)
                    .opacity(ctl.settings.spokenEnabled ? 1 : 0.5)
                } header: {
                    Text(l10n.tr("Spoken Delimiters"))
                } footer: {
                    Text(l10n.tr("If you're using dictation or transcription, spoken delimiters can trigger auto-replace."))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            Section {
                    HStack {
                        HStack(spacing: SPACE_XS) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Text(l10n.tr("Chars before"))
                        }
                        Spacer()
                        Text("\(ctl.settings.contextBeforeChars)")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        Stepper("", value: $ctl.settings.contextBeforeChars, in: 0...5000, step: 25)
                            .labelsHidden()
                    }

                    HStack {
                        HStack(spacing: SPACE_XS) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Text(l10n.tr("Chars after"))
                        }
                        Spacer()
                        Text("\(ctl.settings.contextAfterChars)")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        Stepper("", value: $ctl.settings.contextAfterChars, in: 0...5000, step: 25)
                            .labelsHidden()
                    }
                } header: {
                    Text(l10n.tr("Rewrite Context"))
                }
                .help(Text(verbatim: l10n.tr("Send surrounding text as context for better AI results.")))

            Section {
                    Text(l10n.tr("Use {{SPACKLE_INPUT}} where the extracted text should be inserted."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $ctl.settings.systemPromptTemplate)
                        .frame(minHeight: 140)

                    Button(l10n.tr("Restore Default Prompt")) {
                        ctl.settings.systemPromptTemplate = AppSettings.default.systemPromptTemplate
                    }
                } header: {
                    Text(l10n.tr("AI System Prompt"))
                }

            Section {
                    HStack {
                        HStack(spacing: SPACE_XS) {
                            Image(systemName: "timer")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Text(l10n.tr("Trigger delay (ms)"))
                        }
                        Spacer()
                        Text("\(ctl.settings.triggerDelayMs)")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                        Stepper("", value: $ctl.settings.triggerDelayMs, in: 0...1500, step: 50)
                            .labelsHidden()
                    }
                    .help(Text(verbatim: l10n.tr("After typing the closing delimiter, wait this long before triggering. Prevents false triggers.")))
                } header: {
                    Text(l10n.tr("Behavior"))
                }

            Section {
                Toggle(isOn: $ctl.settings.useClipboardFallback) {
                    HStack(spacing: SPACE_XS) {
                        Image(systemName: "clipboard")
                        Text(l10n.tr("Use clipboard fallback"))
                    }
                }
                .help(Text(verbatim: l10n.tr("If direct text replacement fails (common in Electron apps), fall back to clipboard paste.")))
            } header: {
                Text(l10n.tr("Advanced"))
            } footer: {
                VStack(alignment: .leading, spacing: SPACE_XXS) {
                    Text(appVersionText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Copyright © 2026")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: SPACE_XS) {
                        Link("Aisatsu LLC", destination: URL(string: "https://aisatsu.co")!)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Link(l10n.tr("Privacy"), destination: URL(string: "https://aisatsu.co/privacy")!)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Link(l10n.tr("Terms"), destination: URL(string: "https://aisatsu.co/terms")!)
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
        }
    }

    private func buildStep3Text() -> String {
        let shortcut = ctl.settings.rewriteShortcut.displayName
        return l10n.tr("Select text anywhere on your Mac, then press %@ to rewrite with AI.", shortcut: shortcut)
    }

    private func providerLabel(_ p: ProviderKind) -> String {
        switch p {
        case .openAI: return l10n.tr("OpenAI")
        case .anthropic: return l10n.tr("Anthropic")
        case .openRouter: return l10n.tr("OpenRouter")
        case .custom: return l10n.tr("Custom")
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

    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let v = short?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let b = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if v.isEmpty && b.isEmpty {
            return "Version unknown"
        }
        if v.isEmpty {
            return "Build \(b)"
        }
        if b.isEmpty || b == v {
            return "Version \(v)"
        }
        return "Version \(v) (\(b))"
    }
}

private let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

private struct ShortcutRecorderView: View {
    @Binding var shortcut: ShortcutBinding
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press a shortcut\u{2026}" : shortcut.displayName) {
            startRecording()
        }
        .buttonStyle(.bordered)
        .foregroundStyle(recording ? .secondary : .primary)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            guard modifierKeyCodes.contains(event.keyCode) == false else {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.isEmpty == false else { return event }
            shortcut = ShortcutBinding(keyCode: event.keyCode, modifierFlags: flags.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
