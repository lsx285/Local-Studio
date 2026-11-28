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
            // Motion time starts when the artwork replaces the pulsing dot; Reduce Motion holds a still frame.
            let motionTime = reduceMotion ? 6 : max(0, elapsed - 1.85)
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
                            .foregroundStyle(GenerationMotion.shimmer(at: motionTime, text: imageStage, reduceMotion: reduceMotion))
                            .frame(height: 21, alignment: .leading)
                        // Same footprint the finished artwork takes: its longer side spans the column width.
                        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 0.75
                        let canvasWidth = availableWidth * min(1, ratio)
                        let canvasHeight = canvasWidth / ratio
                        // Each generation seeds its own blob paths, so the field never plays back the same way twice.
                        let blobs = GenerationMotion.blobs(seed: startedAt)
                        Canvas { context, size in
                            let appear = GenerationMotion.ease(motionTime / 0.9)
                            let build = GenerationMotion.ease(motionTime / 2.5)
                            // Soft glows drifting on layered sine paths and pulsing in and out of the grid.
                            let glows = blobs.map { blob in
                                let u = 0.5 + 0.3 * sin(motionTime * blob.wx + blob.px) + 0.12 * sin(motionTime * blob.wx2 + blob.px2)
                                let v = 0.5 + 0.3 * sin(motionTime * blob.wy + blob.py) + 0.12 * sin(motionTime * blob.wy2 + blob.py2)
                                let pulse = 0.5 + 0.5 * sin(motionTime * blob.wa + blob.pa)
                                let reach = blob.size * (0.85 + 0.15 * sin(motionTime * blob.wa * 0.5 + blob.px))
                                return (x: u * Double(size.width), y: v * Double(size.height), strength: pulse * pulse * build,
                                        falloffX: 1 / (2 * reach * reach), falloffY: 1 / (2 * 1.56 * reach * reach))
                            }
                            let pitch = 13.318
                            let columns = max(1, Int((size.width / pitch).rounded()))
                            let rows = max(1, Int((size.height / pitch).rounded()))
                            let originX = (Double(size.width) - Double(columns - 1) * pitch) / 2
                            let originY = (Double(size.height) - Double(rows - 1) * pitch) / 2
                            for row in 0..<rows {
                                let y = originY + Double(row) * pitch
                                for column in 0..<columns {
                                    let x = originX + Double(column) * pitch
                                    var calm = 1.0
                                    for glow in glows {
                                        let dx = x - glow.x, dy = y - glow.y
                                        calm *= 1 - glow.strength * exp(-dx * dx * glow.falloffX - dy * dy * glow.falloffY)
                                    }
                                    let level = 1 - calm
                                    let flicker = sin(motionTime * 2.3 + Double(column) * 1.7 + Double(row) * 2.9)
                                    let radius = appear * (0.92 + 0.08 * flicker) + 1.75 * level
                                    guard radius > 0.05 else { continue }
                                    // Dim navy at rest, saturating to blue inside a glow.
                                    let tint = GenerationMotion.ease(level / 0.45)
                                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                                    let red = (26 + 14 * tint) / 255
                                    let green = (34 + 42 * tint) / 255
                                    let blue = (68 + 132 * tint) / 255
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
    struct Blob {
        let wx, px, wx2, px2, wy, py, wy2, py2, wa, pa, size: Double
    }

    /// Smoothstep of a value clamped to 0...1.
    static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    /// Three glows with paths, pulse rates and sizes drawn from a SplitMix64 stream seeded by the start time.
    static func blobs(seed: Date) -> [Blob] {
        var state = UInt64(bitPattern: Int64(seed.timeIntervalSinceReferenceDate * 1000))
        func random(_ low: Double, _ high: Double) -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return low + (high - low) * Double(z >> 11) / 9_007_199_254_740_992
        }
        return (0..<3).map { _ in
            Blob(wx: random(0.28, 0.5), px: random(0, 2 * .pi), wx2: random(0.7, 1.1), px2: random(0, 2 * .pi),
                 wy: random(0.22, 0.45), py: random(0, 2 * .pi), wy2: random(0.6, 1.0), py2: random(0, 2 * .pi),
                 wa: random(1.1, 1.7), pa: random(0, 2 * .pi), size: random(55, 78))
        }
    }

    /// A soft dark band sweeping the stage label left to right, matched to the reference recording:
    /// about 365 pt/s, a new pass every 1.49 s, dimming the text to roughly a quarter at its center.
    static func shimmer(at time: Double, text: String, reduceMotion: Bool) -> LinearGradient {
        let lit = 0.69
        guard !reduceMotion else { return LinearGradient(colors: [Color(white: lit)], startPoint: .leading, endPoint: .trailing) }
        let width = max(1, (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width)
        let center = -100 + (time * 365).truncatingRemainder(dividingBy: 544)
        let stops = (0..<32).map { index in
            let location = Double(index) / 31
            let distance = location * width - center
            return Gradient.Stop(color: Color(white: lit * (1 - 0.74 * exp(-distance * distance / 2738))), location: location)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}
