import SwiftUI

struct GenerationView: View {
    let startedAt: Date
    let stage: String
    let progress: Double?
    let image: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(stage).font(.system(size: 15)).foregroundStyle(.secondary)
            }
            if image {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                        Canvas { context, _ in
                            let position = min(Double(GenerationMotion.frameCount - 1), max(0, (reduceMotion ? 12 : elapsed.truncatingRemainder(dividingBy: 14)) * 59))
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
                                    let x = (10.63 + Double(column) * 13.318)
                                    let y = (9.18 + Double(row) * 13.318)
                                    let rect = CGRect(x: x - radius, y: y - radius,
                                                      width: radius * 2, height: radius * 2)
                                    context.fill(Path(ellipseIn: rect), with: .color(Color(.sRGB, red: red, green: green, blue: blue)))
                                }
                            }
                        }
                        .frame(width: 300, height: 400)
                        .clipShape(.rect(cornerRadius: 16))

                }
                if let progress {
                    ProgressView(value: progress)
                    Text("\(Int(progress * 100))% of current sampling pass")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private enum GenerationMotion {
    static let samples: [UInt8] = {
        let url = Bundle.main.url(forResource: "GenerationMotion", withExtension: "dots")!
        let data = try! Data(contentsOf: url)
        precondition(data.prefix(8) == Data("LSDOTS02".utf8) && (data.count - 16).isMultiple(of: 2704))
        return Array(data)
    }()
    static let frameCount = (samples.count - 16) / 2704
}
