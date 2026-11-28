import SwiftUI
import UIKit

struct StudioSettingsView: View {
    @Bindable var session: ChatSession

    var body: some View {
        NavigationStack {
            Form {
                Section("Image canvas") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Resolution", value: "\(session.canvasMegapixels.formatted(.number.precision(.fractionLength(1)))) MP")
                        Slider(value: $session.canvasMegapixels, in: 0.1...4.0, step: 0.1)
                            .accessibilityLabel("Resolution in megapixels")
                        Text("\(session.canvasWidth) × \(session.canvasHeight) pixels")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Aspect ratio", selection: $session.canvasAspectRatio) {
                        ForEach(CanvasAspectRatio.allCases) { ratio in
                            Label { Text(ratio.rawValue) } icon: { Image(uiImage: ratio.icon) }
                                .tag(ratio)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Reference-based edits preserve the source aspect ratio.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Text") {
                    Picker("Maximum response length", selection: $session.maxTokens) {
                        ForEach([256, 512, 1024, 2048, 4096], id: \.self) { Text("\($0) tokens").tag($0) }
                    }
                    Text("Qwen3 4B Heretic NVFP4 powers text chat and enhancement. Requests with attached images use Qwen3-VL 4B.")
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
                            if let shift = model.shift { Text("Shift: \(shift.formatted())").font(.caption).foregroundStyle(.secondary) }
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
        }
        .tint(.white)
        .onDisappear { session.saveSettings() }
    }
}

enum CanvasAspectRatio: String, CaseIterable, Identifiable {
    case square = "1:1"
    case portrait = "3:4"
    case landscape = "4:3"
    case portraitPhoto = "2:3"
    case landscapePhoto = "3:2"
    case portraitWide = "9:16"
    case widescreen = "16:9"
    case portraitCinema = "9:21"
    case cinema = "21:9"

    var id: String { rawValue }
    var ratio: Double {
        let parts = rawValue.split(separator: ":").map { Double($0)! }
        return parts[0] / parts[1]
    }

    @MainActor var icon: UIImage {
        let width = CGFloat(20 * min(1, ratio))
        let height = CGFloat(20 / max(1, ratio))
        return UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
            UIColor.white.setStroke()
            let outline = UIBezierPath(roundedRect: CGRect(x: (24 - width) / 2, y: (24 - height) / 2,
                                                          width: width, height: height).insetBy(dx: 0.75, dy: 0.75), cornerRadius: 1.5)
            outline.lineWidth = 1.5
            outline.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}
