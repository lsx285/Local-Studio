import SwiftUI

struct GenerationView: View {
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let progress = GenerationMotion.progress(at: elapsed)
            Group {
                if elapsed < 2.8 {
                    Circle().fill(StudioPalette.accent)
                        .frame(width: 7, height: 7)
                        .frame(width: 300, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(progress < 35 ? "Sketching it out" : progress < 55 ? "Making the first draft" : progress < 72 ? "Setting the scene" : progress < 90 ? "Polishing details" : "Finishing up")
                            .font(.system(size: 17))
                            .foregroundStyle(Color(white: 0.52))
                        Canvas { context, _ in
                            let position = min(Double(GenerationMotion.frameCount - 1), max(0, ((reduceMotion ? 18 : elapsed) - 2.8) * 15))
                            let first = Int(position)
                            let second = min(first + 1, GenerationMotion.frameCount - 1)
                            let blend = position - Double(first)
                            let reveal = reduceMotion ? 0 : min(1, max(0, elapsed - 23.2) / 0.8)
                            for row in 0..<30 {
                                for column in 0..<22 {
                                    let dot = row * 22 + column
                                    let offset = 16 + first * 2640 + dot * 4
                                    let next = 16 + second * 2640 + dot * 4
                                    let radius = (Double(GenerationMotion.samples[offset]) * (1 - blend)
                                                  + Double(GenerationMotion.samples[next]) * blend) / 64
                                    guard radius > 0 else { continue }
                                    let red = (Double(GenerationMotion.samples[offset + 1]) * (1 - blend) + Double(GenerationMotion.samples[next + 1]) * blend) / 255
                                    let green = (Double(GenerationMotion.samples[offset + 2]) * (1 - blend) + Double(GenerationMotion.samples[next + 2]) * blend) / 255
                                    let blue = (Double(GenerationMotion.samples[offset + 3]) * (1 - blend) + Double(GenerationMotion.samples[next + 3]) * blend) / 255
                                    let x = 9.85 + Double(column) * 13.318
                                    let y = 9.26 + Double(row) * 13.318
                                    let rect = CGRect(x: x - radius, y: y - radius,
                                                      width: radius * 2, height: radius * 2 + reveal * 8)
                                    context.fill(Path(ellipseIn: rect), with: .color(Color(.sRGB, red: red, green: green, blue: blue).opacity(1 - reveal)))
                                }
                            }
                        }
                        .frame(width: 300, height: 400)
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(progress) %")
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(Color(white: 0.68))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(.regular, in: .capsule)
                                .padding(20)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Image generation preview, \(progress) percent")
        }
    }
}

/// Four bytes per dot: radius in 1/64 pt and sRGB, interpolated by Canvas at 30 fps.
/// Only this abstract motion trace is bundled; the recording never enters the app.
private enum GenerationMotion {
    static let samples: [UInt8] = {
        guard let url = Bundle.main.url(forResource: "GenerationMotion", withExtension: "dots"),
              let data = try? Data(contentsOf: url), data.count >= 16 + 2640,
              data.prefix(8) == Data("LSDOTS01".utf8), (data.count - 16).isMultiple(of: 2640) else {
            return [UInt8](repeating: 0, count: 16 + 2640)
        }
        return Array(data)
    }()
    static let frameCount = (samples.count - 16) / 2640
    static let markers: [(Double, Double)] = [
        (2.8, 0), (3, 10), (4, 26), (5, 30), (6, 34), (7, 37), (8, 39),
        (9, 45), (10, 48), (11, 52), (12, 55), (13, 59), (14, 64),
        (15, 69), (16, 74), (17, 79), (18, 81), (19, 88), (20, 90),
        (21, 93), (22, 95), (24, 95)
    ]

    static func progress(at elapsed: Double) -> Int {
        guard elapsed >= 2.8 else { return 0 }
        for index in 1..<markers.count where elapsed <= markers[index].0 {
            let previous = markers[index - 1]
            let next = markers[index]
            let fraction = (elapsed - previous.0) / (next.0 - previous.0)
            return Int(previous.1 + fraction * (next.1 - previous.1))
        }
        return 95
    }
}
