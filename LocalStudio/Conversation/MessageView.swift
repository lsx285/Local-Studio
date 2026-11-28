import SwiftUI
import AVFoundation
import Photos

struct MessageView: View {
    let message: ChatMessage
    let openArtwork: (UUID) -> Void
    let reportArtworkFrame: (UUID, CGRect) -> Void
    let canRetry: Bool
    let retryResponse: (ChatMessage) -> Void
    let editPrompt: (ChatMessage) -> Void
    @State private var speech: AVSpeechSynthesizer?
    @State private var photoError: String?
    @State private var selectingText = false
    @State private var textSize: CGSize = .zero

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if !message.attachments.isEmpty {
                if message.role == .user {
                    SentPhotoAttachments(photos: message.attachments)
                } else {
                    ForEach(message.attachments) { photo in
                        Image(uiImage: photo.image)
                            .resizable().scaledToFit()
                            .clipShape(.rect(cornerRadius: 16))
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { reportArtworkFrame(photo.id, $0) }
                            .onTapGesture { openArtwork(photo.id) }
                            .overlay(alignment: .bottomTrailing) {
                                ShareLink(item: Image(uiImage: photo.image), preview: SharePreview("Local Studio artwork", image: Image(uiImage: photo.image))) {
                                    StudioIcon(.share)
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Share artwork")
                                .foregroundStyle(.white)
                                .glassEffect(.clear.interactive(), in: .circle)
                                .padding(20)
                            }
                            .accessibilityLabel("Demo artwork")
                            .contextMenu {
                                Button { UIPasteboard.general.image = photo.image } label: {
                                    Label { Text("Copy") } icon: { StudioIcon(.copy) }
                                }
                                Button {
                                    let data = photo.data
                                    Task {
                                        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                                        guard status == .authorized || status == .limited else {
                                            photoError = "Allow Local Studio to add photos in Settings to save artwork."
                                            return
                                        }
                                        do {
                                            try await PHPhotoLibrary.shared().performChanges {
                                                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                                            }
                                        } catch { photoError = "This artwork couldn’t be saved. Please try again." }
                                    }
                                } label: { Label { Text("Save to photos") } icon: { StudioIcon(.save) } }
                                ShareLink(item: Image(uiImage: photo.image), preview: SharePreview("Local Studio artwork", image: Image(uiImage: photo.image))) {
                                    Label { Text("Share") } icon: { StudioIcon(.share) }
                                }
                            }
                            .tint(.white)
                    }
                }
            }
            if !message.text.isEmpty {
                if message.role == .user {
                    HStack {
                        Spacer(minLength: 60)
                        Group {
                            if selectingText {
                                InlineMessageSelection(text: message.text, color: UIColor(StudioPalette.prompt), active: $selectingText)
                                    .frame(width: textSize.width, height: textSize.height)
                            } else {
                                Text(message.text)
                                    .font(.system(size: 17))
                                    .lineSpacing(3)
                                    .foregroundStyle(StudioPalette.prompt)
                                    .onGeometryChange(for: CGSize.self) { $0.size } action: { textSize = $0 }
                            }
                        }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(StudioPalette.bubble, in: .rect(cornerRadius: 24))
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24))
                            .contextMenu {
                                Section {
                                    Button { UIPasteboard.general.string = message.text } label: {
                                        Label { Text("Copy") } icon: { StudioIcon(.copy) }
                                    }
                                    Button { editPrompt(message) } label: {
                                        Label { Text("Edit") } icon: { StudioIcon(.edit) }
                                    }
                                    Button { selectingText = true } label: {
                                        Label { Text("Select text") } icon: { StudioIcon(.selectText) }
                                    }
                                    ShareLink(item: message.text) {
                                        Label { Text("Share prompt") } icon: { StudioIcon(.share) }
                                    }
                                } header: {
                                    Text(Calendar.current.isDateInToday(message.createdAt)
                                         ? "Today, \(message.createdAt.formatted(date: .omitted, time: .shortened))"
                                         : message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                            .tint(.white)

                    }
                } else {
                    Text(message.text)
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if message.role == .assistant {
                HStack(spacing: 12) {
                    if !message.text.isEmpty {
                        Button { UIPasteboard.general.string = message.text } label: { StudioIcon(.copyAction) }
                            .accessibilityLabel("Copy response")
                        Button {
                            if speech?.isSpeaking == true { speech?.stopSpeaking(at: .immediate) }
                            else {
                                if speech == nil { speech = AVSpeechSynthesizer() }
                                speech?.speak(AVSpeechUtterance(string: message.text))
                            }
                        } label: { StudioIcon(.speaker) }
                            .accessibilityLabel("Read aloud")
                        ShareLink(item: message.text) { StudioIcon(.shareAction) }
                            .accessibilityLabel("Share response")
                    } else if let photo = message.attachments.first {
                        ShareLink(item: Image(uiImage: photo.image), preview: SharePreview("Local Studio artwork", image: Image(uiImage: photo.image))) {
                            StudioIcon(.shareAction)
                        }
                        .accessibilityLabel("Share artwork")
                    }
                    Menu {
                        Section {
                            Button { retryResponse(message) } label: {
                                Label { Text("Retry") } icon: { StudioIcon(.retry) }
                            }
                            .disabled(!canRetry)
                        } header: {
                            Text("Used Local Model")
                                .font(.system(size: 13, weight: .medium))
                        }
                    } label: { StudioIcon(.moreAction) }
                        .accessibilityLabel("Response options")
                        .tint(.white)
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(white: 0.76))
                .padding(.top, 12)
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .onDisappear { speech?.stopSpeaking(at: .immediate) }
        .alert("Couldn’t save photo", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK") { photoError = nil }
        } message: { Text(photoError ?? "") }
    }
}

/// Sent images use their natural ratio singly, and compact square tiles in a group.
private struct SentPhotoAttachments: View {
    let photos: [PhotoAttachment]
    @State private var availableWidth: CGFloat = 398

    private var columns: Int { photos.count == 4 ? 2 : min(3, photos.count) }
    private var tileSize: CGFloat { min(128, max(1, (availableWidth - CGFloat(columns - 1) * 4) / CGFloat(columns))) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if photos.count == 1, let photo = photos.first {
                let size = fittedSize(photo.image.size)
                thumbnail(photo, size: size)
            } else {
                ForEach(Array(stride(from: 0, to: photos.count, by: columns)), id: \.self) { start in
                    HStack(spacing: 4) {
                        ForEach(Array(photos[start..<min(start + columns, photos.count)])) { photo in
                            thumbnail(photo, size: CGSize(width: tileSize, height: tileSize))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private func fittedSize(_ size: CGSize) -> CGSize {
        let scale = min(min(288, availableWidth) / max(1, size.width), 192 / max(1, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func thumbnail(_ photo: PhotoAttachment, size: CGSize) -> some View {
        Image(uiImage: photo.image)
            .resizable().scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 24))
            .accessibilityLabel("Attached photo")
            .contextMenu {
                Button { UIPasteboard.general.image = photo.image } label: { Label { Text("Copy") } icon: { StudioIcon(.copy) } }
            }
            .tint(.white)
    }
}
