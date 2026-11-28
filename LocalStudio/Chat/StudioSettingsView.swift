import SwiftUI

struct StudioSettingsView: View {
    @Bindable var session: ChatSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Your PC") {
                    Label(session.connection.status, systemImage: session.connection.isConnected ? "checkmark.circle" : "network")
                    if let name = session.connection.serverName { Text(name).foregroundStyle(.secondary) }
                    Button("Find PC again") { session.connection.discover() }
                        .disabled(session.isGenerating || session.isEnhancing)
                    Text("Start run_nvidia_gpu.bat on your PC. Keep both devices on the same local network and allow Local Studio to access it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Image canvas") {
                    Picker("Width", selection: $session.canvasWidth) {
                        ForEach([512, 768, 1024, 1280, 1536], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    Picker("Height", selection: $session.canvasHeight) {
                        ForEach([512, 768, 1024, 1280, 1536], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    Text("Edits follow the reference image’s aspect ratio at the model’s trained resolution.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Text") {
                    Picker("Maximum response length", selection: $session.maxTokens) {
                        ForEach([256, 512, 1024, 2048, 4096], id: \.self) { Text("\($0) tokens").tag($0) }
                    }
                    Text("Qwen3-VL 4B powers chat and the composer’s Enhance button locally on your PC.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Models") {
                    ForEach(session.connection.models) { model in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(model.name)
                                Spacer()
                                Image(systemName: model.installed ? "checkmark.circle.fill" : "arrow.down.circle")
                                    .foregroundStyle(model.installed ? Color.green : Color.secondary)
                            }
                            Text(model.capability).font(.caption).foregroundStyle(.secondary)
                            if model.steps > 0 {
                                Text("\(model.steps) steps · CFG \(model.cfg.formatted()) · \(model.sampler) · \(model.scheduler)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Sampling presets follow the published workflows. Qwen Turbo’s fixed sigma schedule and Fibo Turbo’s four-step preset are preserved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("Local Studio", value: "1.0")
                    Text("Messages stay on this iPhone. Prompts and original attachments are sent to the discovered PC for inference.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear { session.saveSettings() }
    }
}
