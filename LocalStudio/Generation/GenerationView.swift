import SwiftUI

struct GenerationView: View {
    let startedAt: Date
    var availableWidth: CGFloat = 398
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var referenceTime: Double? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           let value = ProcessInfo.processInfo.environment["LOCAL_STUDIO_GENERATION_OFFSET"] {
            return Double(value)
        }
        #endif
        return nil
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 60, paused: referenceTime != nil)) { timeline in
            let elapsed = referenceTime ?? max(0, timeline.date.timeIntervalSince(startedAt))
            let progress = GenerationMotion.progress(at: elapsed)
            let stage = elapsed < 6.45 ? "Sketching it out" : elapsed < 10.95 ? "Making the first draft" : elapsed < 14.95 ? "Setting the scene" : "Polishing details"
            let reveal = reduceMotion ? 0 : min(1, max(0, (elapsed - 16.6) / 0.95))
            let contraction = min(1, reveal / 0.5)
            let eased = contraction * contraction * (3 - 2 * contraction)
            let fieldWidth = 300 + (availableWidth - 300) * eased
            let fieldHeight = 400 + (availableWidth / 1.5 - 400) * eased
            Group {
                if elapsed < 1.85 {
                    Circle().fill(StudioPalette.accent)
                        .frame(width: 17, height: 17)
                        .scaleEffect(reduceMotion ? 1 : 0.6 + 0.4 * (0.5 + 0.5 * cos(elapsed * 2 * .pi / 1.1)))
                        .frame(width: 300, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8 * (1 - min(1, reveal * 5))) {
                        Text(stage)
                            .font(.system(size: 17))
                            .lineLimit(1)
                            .foregroundStyle(GenerationMotion.labelGradient(at: elapsed, text: stage, reduceMotion: reduceMotion))
                            .frame(height: 21 * (1 - min(1, reveal * 5)), alignment: .leading)
                            .opacity(1 - min(1, reveal * 5))
                        Canvas { context, _ in
                            let position = min(Double(GenerationMotion.frameCount - 1), max(0, ((reduceMotion ? 12 : elapsed) - 1.85) * 59))
                            let first = Int(position)
                            let second = min(first + 1, GenerationMotion.frameCount - 1)
                            let blend = position - Double(first)
                            for row in 0..<30 {
                                for column in 0..<22 {
                                    let dot = row * 22 + column
                                    let offset = 16 + first * 2704 + dot * 4
                                    let next = 16 + second * 2704 + dot * 4
                                    let radius = (Double(GenerationMotion.samples[offset]) * (1 - blend)
                                                  + Double(GenerationMotion.samples[next]) * blend) / 64
                                    guard radius > 0 else { continue }
                                    let red = (Double(GenerationMotion.samples[offset + 1]) * (1 - blend) + Double(GenerationMotion.samples[next + 1]) * blend) / 255
                                    let green = (Double(GenerationMotion.samples[offset + 2]) * (1 - blend) + Double(GenerationMotion.samples[next + 2]) * blend) / 255
                                    let blue = (Double(GenerationMotion.samples[offset + 3]) * (1 - blend) + Double(GenerationMotion.samples[next + 3]) * blend) / 255
                                    let x = (10.63 + Double(column) * 13.318) * fieldWidth / 300
                                    let y = (4.4 + Double(row) * 13.318) * fieldHeight / 400
                                    let rect = CGRect(x: x - radius, y: y - radius,
                                                      width: radius * 2, height: radius * 2)
                                    context.fill(Path(ellipseIn: rect), with: .color(Color(.sRGB, red: red, green: green, blue: blue).opacity(1 - min(1, max(0, (reveal - 0.5) * 3)))))
                                }
                            }
                        }
                        .frame(width: fieldWidth, height: fieldHeight)
                        .overlay {
                            if reveal > 0.48, let artwork = GenerationMotion.artwork {
                                Image(uiImage: artwork).resizable().scaledToFill()
                                    .frame(width: fieldWidth, height: fieldHeight).clipped()
                                    .mask {
                                        Canvas { context, size in
                                            for row in 0..<30 {
                                                for column in 0..<22 {
                                                    let delay = Double(column) * 0.003 + Double(row) * 0.0015
                                                    let phase = min(1, max(0, (reveal - 0.48 - delay) / 0.38))
                                                    let x = size.width * (CGFloat(column) + 0.5) / 22
                                                    let y = size.height * (CGFloat(row) + 0.5) / 30
                                                    let w = 2 + (size.width / 22 - 1) * pow(phase, 2.5)
                                                    let h = 2 + (size.height / 30 + 1) * min(1, phase * 2)
                                                    guard phase > 0 else { continue }
                                                    context.fill(Path(roundedRect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), cornerRadius: 2 * (1 - phase)), with: .color(.white.opacity(phase)))
                                                }
                                            }
                                        }
                                    }
                            }
                        }
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(progress) %")
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(Color(white: 0.68))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(.regular, in: .capsule)
                                .padding(20)
                                .opacity(1 - min(1, reveal * 5))
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Image generation preview, \(progress) percent")
        }
    }
}

/// Each 59 Hz frame stores 660 radius/sRGB tuples and 64 label-luminance samples.
/// Only this abstract motion trace is bundled; the recording never enters the app.
private enum GenerationMotion {
    static let artwork: UIImage? = Bundle.main.url(forResource: "DemoArtwork", withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }

    static func labelGradient(at elapsed: Double, text: String, reduceMotion: Bool) -> LinearGradient {
        let frame = min(frameCount - 1, max(0, Int((elapsed - 1.85) * 59)))
        let width = max(1, (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width)
        let stops = (0..<64).compactMap { index -> Gradient.Stop? in
            let location = Double(index) / 63 * 300 / width
            guard location <= 1 else { return nil }
            let gray = reduceMotion ? 0.52 : Double(samples[16 + frame * 2704 + 2640 + index]) / 255
            return Gradient.Stop(color: Color(white: gray), location: location)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
    static let samples: [UInt8] = {
        guard let url = Bundle.main.url(forResource: "GenerationMotion", withExtension: "dots"),
              let data = try? Data(contentsOf: url), data.count >= 16 + 2704,
              data.prefix(8) == Data("LSDOTS02".utf8), (data.count - 16).isMultiple(of: 2704) else {
            return [UInt8](repeating: 0, count: 16 + 2704)
        }
        return Array(data)
    }()
    static let frameCount = (samples.count - 16) / 2704
    static let markers: [(Double, Double)] = [
        (1.85, 0), (2, 10), (2.5, 12), (3, 14), (3.5, 28), (4, 30),
        (4.5, 32), (5, 34), (5.5, 37), (6, 39), (6.5, 41), (7, 44),
        (7.5, 46), (8, 48), (8.5, 51), (9, 52), (9.5, 54), (10, 57),
        (10.5, 60), (11, 62), (11.5, 66), (12, 69), (12.5, 72), (13, 74),
        (13.5, 78), (14, 81), (14.5, 83), (15, 87), (15.5, 89), (16, 90), (16.4, 92), (17.55, 92)
    ]

    static func progress(at elapsed: Double) -> Int {
        guard elapsed >= 1.85 else { return 0 }
        for index in 1..<markers.count where elapsed <= markers[index].0 {
            let previous = markers[index - 1]
            let next = markers[index]
            let fraction = (elapsed - previous.0) / (next.0 - previous.0)
            return Int(previous.1 + fraction * (next.1 - previous.1))
        }
        return 92
    }
}
