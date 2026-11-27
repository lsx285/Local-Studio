import SwiftUI

/// Recorded contour geometry only. Image pixels always come from the app's artwork.
struct GenerationRevealView: View {
    let elapsed: Double
    let width: CGFloat

    var body: some View {
        let index = min(RevealGeometry.frames.count - 1, max(0, Int((elapsed - 16.6) * 59)))
        let frame = RevealGeometry.frames[index]
        let scale = width / 398
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.scaleBy(x: scale, y: scale)
                for shape in frame.shapes where !shape.image {
                    context.fill(shape.path, with: .color(shape.color))
                }
            }
            if let artwork = RevealGeometry.artwork {
                Image(uiImage: artwork).resizable().scaledToFill()
                    .frame(width: width, height: width / 1.5)
                    .mask {
                        Canvas { context, _ in
                            context.scaleBy(x: scale, y: scale)
                            for shape in frame.shapes where shape.image {
                                context.fill(shape.path, with: .color(.white))
                            }
                        }
                    }
            }
        }
        .frame(width: width, height: max(width / 1.5, frame.height * scale), alignment: .topLeading)
    }
}

private enum RevealGeometry {
    struct Shape {
        let path: Path
        let color: Color
        let image: Bool
    }
    struct Frame {
        let shapes: [Shape]
        let height: CGFloat
    }
    static let artwork = Bundle.main.url(forResource: "DemoArtwork", withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    static let frames: [Frame] = {
        guard let url = Bundle.main.url(forResource: "GenerationReveal", withExtension: "mask"),
              let data = try? Data(contentsOf: url), data.count > 12,
              data.prefix(8) == Data("LSMASK01".utf8) else { return [Frame(shapes: [], height: 400)] }
        let bytes = Array(data)
        var cursor = 8
        func integer(_ count: Int) -> UInt32 {
            guard cursor + count <= bytes.count else { return 0 }
            var result: UInt32 = 0
            for shift in 0..<count { result |= UInt32(bytes[cursor + shift]) << (shift * 8) }
            cursor += count
            return result
        }
        let count = Int(integer(2))
        _ = integer(2)
        var result: [Frame] = []
        for _ in 0..<count {
            let shapeCount = Int(integer(2))
            var shapes: [Shape] = []
            var height: CGFloat = 0
            for _ in 0..<shapeCount {
                let image = integer(1) != 0
                let red = Double(integer(1)) / 255
                let green = Double(integer(1)) / 255
                let blue = Double(integer(1)) / 255
                let points = Int(integer(2))
                var path = Path()
                for pointIndex in 0..<points {
                    let x = CGFloat(Float(bitPattern: integer(4)))
                    let y = CGFloat(Float(bitPattern: integer(4)))
                    height = max(height, y)
                    if pointIndex == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                path.closeSubpath()
                shapes.append(Shape(path: path, color: Color(.sRGB, red: red, green: green, blue: blue), image: image))
            }
            result.append(Frame(shapes: shapes, height: height))
        }
        return result.isEmpty ? [Frame(shapes: [], height: 400)] : result
    }()
}
