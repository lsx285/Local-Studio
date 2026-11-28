import SwiftUI

struct GenerationView: View {
    let startedAt: Date
    let stage: String
    let progress: Double?
    let image: Bool
    /// Width ÷ height of the requested artwork; the dot field takes the same shape.
    let aspectRatio: Double
    /// Width of the conversation column; the artwork fits a square this wide, like the finished image.
    let availableWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var imageStage: String {
        guard let progress else { return "Sketching it out" }
        if progress < 0.3 { return "Sketching it out" }
        if progress < 0.6 { return "Making the first draft" }
        if progress < 0.85 { return "Setting the scene" }
        return "Polishing details"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 60)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let motionElapsed = 1.85 + max(0, elapsed - 1.85).truncatingRemainder(dividingBy: 14.75)
            Group {
                if !image || progress == nil || elapsed < 1.85 {
                    Circle().fill(StudioPalette.accent)
                        .frame(width: 17, height: 17)
                        .scaleEffect(reduceMotion ? 1 : 0.6 + 0.4 * (0.5 + 0.5 * cos(elapsed * 2 * .pi / 1.1)))
                        .frame(width: 300, alignment: .leading)
                        .accessibilityLabel(stage)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(imageStage)
                            .font(.system(size: 17))
                            .lineLimit(1)
                            .foregroundStyle(GenerationMotion.labelGradient(at: motionElapsed, text: imageStage, reduceMotion: reduceMotion))
                            .frame(height: 21, alignment: .leading)
                        // Same footprint the finished artwork takes: its longer side spans the column width.
                        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 0.75
                        let canvasWidth = availableWidth * min(1, ratio)
                        let canvasHeight = canvasWidth / ratio
                        Canvas { context, size in
                            let samples = GenerationMotion.samples
                            let frameCount = GenerationMotion.frameCount
                            let position = min(Double(frameCount - 1), max(0, ((reduceMotion ? 12 : motionElapsed) - 1.85) * 59))
                            let first = Int(position)
                            let second = min(first + 1, frameCount - 1)
                            let blend = position - Double(first)
                            let keep = 1 - blend
                            // Keep the dot pitch and spread the 22 × 30 recorded field across as many dots as fit.
                            let pitch = 13.318
                            let columns = max(1, Int((size.width / pitch).rounded()))
                            let rows = max(1, Int((size.height / pitch).rounded()))
                            let originX = (size.width - Double(columns - 1) * pitch) / 2
                            let originY = (size.height - Double(rows - 1) * pitch) / 2
                            for row in 0..<rows {
                                let sourceRow = min(29, row * 30 / rows)
                                for column in 0..<columns {
                                    let dot = sourceRow * 22 + min(21, column * 22 / columns)
                                    let offset = 16 + first * 2704 + dot * 4
                                    let next = 16 + second * 2704 + dot * 4
                                    let radius = (Double(samples[offset]) * keep + Double(samples[next]) * blend) / 64
                                    guard radius > 0 else { continue }
                                    let red = (Double(samples[offset + 1]) * keep + Double(samples[next + 1]) * blend) / 255
                                    let green = (Double(samples[offset + 2]) * keep + Double(samples[next + 2]) * blend) / 255
                                    let blue = (Double(samples[offset + 3]) * keep + Double(samples[next + 3]) * blend) / 255
                                    let x = originX + Double(column) * pitch
                                    let y = originY + Double(row) * pitch
                                    let rect = CGRect(x: x - radius, y: y - radius,
                                                      width: radius * 2, height: radius * 2)
                                    context.fill(Path(ellipseIn: rect), with: .color(Color(.sRGB, red: red, green: green, blue: blue)))
                                }
                            }
                        }
                        .frame(width: canvasWidth, height: canvasHeight)
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay(alignment: .bottomTrailing) {
                            if let progress {
                                Text("\(Int(progress * 100)) %")
                                    .font(.system(size: 15).monospacedDigit())
                                    .foregroundStyle(Color(white: 0.68))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .glassEffect(.regular, in: .capsule)
                                    .padding(20)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(imageStage), \(Int((progress ?? 0) * 100)) percent")
                }
            }
        }
    }
}

private enum GenerationMotion {
    static func labelGradient(at elapsed: Double, text: String, reduceMotion: Bool) -> LinearGradient {
        let frame = min(frameCount - 1, max(0, Int((elapsed - 1.85) * 59)))
        let width = max(1, (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width)
        let samples = Self.samples
        let stops = (0..<64).compactMap { index -> Gradient.Stop? in
            let location = Double(index) / 63 * 300 / width
            guard location <= 1 else { return nil }
            let gray = reduceMotion ? 0.52 : Double(samples[16 + frame * 2704 + 2640 + index]) / 255
            return Gradient.Stop(color: Color(white: gray), location: location)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
    static let samples: [UInt8] = {
        let url = Bundle.main.url(forResource: "GenerationMotion", withExtension: "dots")!
        let data = try! Data(contentsOf: url)
        precondition(data.count >= 16 + 2704 && data.prefix(8) == Data("LSDOTS02".utf8) && (data.count - 16).isMultiple(of: 2704))
        return Array(data)
    }()
    static let frameCount = (samples.count - 16) / 2704
}
