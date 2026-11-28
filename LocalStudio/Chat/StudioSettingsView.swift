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
                            Label { Text("\(ratio.rawValue) \(ratio.name)") } icon: { Image(uiImage: ratio.icon) }
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
                    Text("Qwen3-VL 4B Heretic NVFP4 powers text chat, image-aware chat and enhancement.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            // Breathing room beneath the sheet's grabber now that the form has no title.
            .contentMargins(.top, 24, for: .scrollContent)
            // Detent-like ticks while scrubbing resolution, and a click for each menu choice.
            .sensoryFeedback(.selection, trigger: session.canvasMegapixels)
            .sensoryFeedback(.selection, trigger: session.canvasAspectRatio)
            .sensoryFeedback(.selection, trigger: session.maxTokens)
        }
        .tint(.white)
        .onDisappear { session.saveSettings() }
    }
}

enum CanvasAspectRatio: String, CaseIterable, Identifiable {
    case poster = "2:3"
    case photoPrint = "3:2"
    case presentation = "4:3"
    case square = "1:1"
    case story = "9:16"
    case widescreen = "16:9"
    case cinematic = "21:9"
    case banner = "5:2"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .poster: "Poster"
        case .photoPrint: "Photo Print"
        case .presentation: "Presentation"
        case .square: "Square"
        case .story: "Story"
        case .widescreen: "Widescreen"
        case .cinematic: "Cinematic"
        case .banner: "Banner"
        }
    }
    var ratio: Double {
        let parts = rawValue.split(separator: ":").map { Double($0)! }
        return parts[0] / parts[1]
    }

    @MainActor var icon: UIImage { Self.icons[self]! }

    /// Rendered once; the settings form re-evaluates on every slider step.
    @MainActor private static let icons: [CanvasAspectRatio: UIImage] = Dictionary(uniqueKeysWithValues: allCases.map { ratio in
        let width = CGFloat(20 * min(1, ratio.ratio))
        let height = CGFloat(20 / max(1, ratio.ratio))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
            UIColor.white.setStroke()
            let outline = UIBezierPath(roundedRect: CGRect(x: (24 - width) / 2, y: (24 - height) / 2,
                                                          width: width, height: height).insetBy(dx: 0.75, dy: 0.75), cornerRadius: 1.5)
            outline.lineWidth = 1.5
            outline.stroke()
        }.withRenderingMode(.alwaysTemplate)
        return (ratio, image)
    })
}
