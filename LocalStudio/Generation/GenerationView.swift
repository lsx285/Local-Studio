import SwiftUI

struct GenerationView: View {
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let progress = min(99, Int(elapsed / 22 * 100))
            VStack(alignment: .leading, spacing: 12) {
                Text(progress < 35 ? "Sketching it out" : progress < 55 ? "Making the first draft" : progress < 72 ? "Setting the scene" : progress < 90 ? "Polishing details" : "Finishing up")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: 0.55))
                Canvas { context, size in
                    let columns = 40
                    let step = size.width / CGFloat(columns)
                    let time = reduceMotion ? 2.0 : elapsed
                    for row in 0..<columns {
                        for column in 0..<columns {
                            let x = Double(column) / Double(columns)
                            let y = Double(row) / Double(columns)
                            let wave = sin(x * 9 + time * 0.7) * cos(y * 7 - time * 0.45)
                            let glow = max(0, wave) * (0.3 + min(elapsed / 15, 0.7))
                            let radius = 0.5 + glow * 0.8
                            let dot = CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: radius * 2, height: radius * 2)
                            context.fill(Path(ellipseIn: dot), with: .color(StudioPalette.accent.opacity(0.10 + glow * 0.85)))
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(progress) %")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Color(white: 0.7))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(white: 0.12), in: .capsule)
                        .padding(10)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Image generation preview, \(progress) percent")
        }
    }
}
