import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ArtworkInfoView: View {
    let photo: ViewerPhoto
    @State private var file: ArtworkFileInfo?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(photo.date.formatted(.dateTime.weekday(.wide))) · \(photo.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 15))
                    Label(photo.photo.filename ?? "Local Studio image", systemImage: "photo")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(16)
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "cpu").font(.system(size: 20))
                    Text(photo.metadata?.model ?? "Image")
                        .font(.system(size: 17, weight: .medium))
                    Spacer(minLength: 4)
                    if let file {
                        Text(file.format).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.08), in: .capsule)
                    }
                }
                .padding(16)
                Divider()
                if let file {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\((Double(file.width * file.height) / 1_000_000).formatted(.number.precision(.fractionLength(1)))) MP · \(file.width) × \(file.height) · \(ByteCountFormatter.string(fromByteCount: Int64(photo.photo.data.count), countStyle: .file))")
                        if !file.colorDetails.isEmpty { Text(file.colorDetails) }
                    }
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .padding(16)
                }
                if let metadata = photo.metadata, let steps = metadata.steps, let cfg = metadata.cfg {
                    Divider()
                    HStack(spacing: 0) {
                        metric(String(steps), label: "Steps")
                        Divider().frame(height: 30)
                        metric(cfg.formatted(), label: "CFG")
                        Divider().frame(height: 30)
                        metric(metadata.sampler ?? "", label: "Sampler")
                    }
                    .padding(.vertical, 14)
                }
            }
            .background(Color(white: 0.12), in: .rect(cornerRadius: 24))

            if let metadata = photo.metadata {
                VStack(spacing: 12) {
                    field("Seed", String(metadata.seed))
                    field("Schedule", metadata.scheduler)
                    if let seconds = metadata.requestSeconds {
                        field("Request time", seconds.formatted(.number.precision(.fractionLength(1))) + " s")
                    }
                    field("Model file", metadata.diffusionModel)
                    field("Text encoder", metadata.encoder)
                    field("VAE", metadata.vae)
                    field("Sigmas", metadata.sigmas)
                }
                .padding(16)
                .background(Color(white: 0.12), in: .rect(cornerRadius: 24))

                promptCard("Prompt", text: metadata.prompt)
                if let negative = metadata.negativePrompt, !negative.isEmpty {
                    promptCard("Negative prompt", text: negative)
                }
            }
        }
        .foregroundStyle(.white)
        .task(id: photo.id) { file = ArtworkFileInfo(data: photo.photo.data) }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 14, weight: .medium))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func field(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 16) {
                Text(label).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            .font(.system(size: 14))
        }
    }

    private func promptCard(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 16)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.12), in: .rect(cornerRadius: 24))
    }
}

private struct ArtworkFileInfo {
    let width: Int
    let height: Int
    let format: String
    let depth: Int?
    let profile: String?
    let colorModel: String?
    let hasAlpha: Bool

    var colorDetails: String {
        [colorModel, depth.map { "\($0)-bit" }, hasAlpha ? "Alpha" : nil, profile]
            .compactMap { $0 }.joined(separator: " · ")
    }

    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              let type = CGImageSourceGetType(source) else { return nil }
        self.width = width
        self.height = height
        format = UTType(type as String)?.preferredFilenameExtension?.uppercased() ?? (type as String)
        depth = properties[kCGImagePropertyDepth as String] as? Int
        profile = properties[kCGImagePropertyProfileName as String] as? String
        colorModel = properties[kCGImagePropertyColorModel as String] as? String
        hasAlpha = properties[kCGImagePropertyHasAlpha as String] as? Bool == true
    }
}
