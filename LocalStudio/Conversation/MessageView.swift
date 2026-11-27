import SwiftUI
import AVFoundation
import Photos

struct MessageView: View {
    let message: ChatMessage
    let edit: () -> Void
    @State private var speech: AVSpeechSynthesizer?
    @State private var photoError: String?
    @State private var selectingText = false
    @State private var textSize: CGSize = .zero

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if !message.attachments.isEmpty {
                if message.role == .user {
                    HStack {
                        Spacer(minLength: 90)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: message.attachments.count == 1 ? 1 : 2), spacing: 5) {
                            ForEach(message.attachments) { photo in
                                Image(uiImage: photo.image)
                                    .resizable().aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(message.attachments.count == 1 ? 1.5 : 1, contentMode: .fit)
                                    .clipped()
                                    .clipShape(.rect(cornerRadius: 24))
                                    .accessibilityLabel("Attached photo")
                                    .accessibilityIdentifier("userAttachment")
                                    .contextMenu {
                                        Button("Copy", systemImage: "square.on.square") { UIPasteboard.general.image = photo.image }
                                    }
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: 288)
                    }
                } else {
                    ForEach(message.attachments) { photo in
                        Image(uiImage: photo.image)
                            .resizable().scaledToFit()
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay(alignment: .bottomTrailing) {
                                ShareLink(item: Image(uiImage: photo.image), preview: SharePreview("Local Studio artwork", image: Image(uiImage: photo.image))) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 19, weight: .medium))
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Share artwork")
                                .foregroundStyle(.white)
                                .glassEffect(.clear.interactive(), in: .circle)
                                .padding(20)
                            }
                            .accessibilityLabel("Demo artwork")
                            .accessibilityIdentifier("assistantArtwork")
                            .contextMenu {
                                Button("Copy", systemImage: "square.on.square") {
                                    UIPasteboard.general.image = photo.image
                                }
                                Button("Save to photos", systemImage: "square.and.arrow.down") {
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
                                }
                                ShareLink(item: Image(uiImage: photo.image), preview: SharePreview("Local Studio artwork", image: Image(uiImage: photo.image))) {
                                    Label("Share", systemImage: "square.and.arrow.up")
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
                            .contextMenu {
                                Text(Calendar.current.isDateInToday(message.createdAt)
                                     ? "Today, \(message.createdAt.formatted(date: .omitted, time: .shortened))"
                                     : message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Button("Copy", systemImage: "square.on.square") { UIPasteboard.general.string = message.text }
                                Button("Edit", systemImage: "pencil", action: edit)
                                Button("Select text", systemImage: "text.cursor") { selectingText = true }
                                ShareLink(item: message.text) { Label("Share prompt", systemImage: "square.and.arrow.up") }
                            }
                            .tint(.white)
                            .accessibilityIdentifier("userMessage")
                    }
                } else {
                    Group {
                        if selectingText {
                            InlineMessageSelection(text: message.text, color: .white, active: $selectingText)
                                .frame(width: textSize.width, height: textSize.height)
                        } else {
                            Text(message.text)
                                .font(.system(size: 17))
                                .lineSpacing(3)
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { textSize = $0 }
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("assistantMessage")
                }
            }
            if message.role == .assistant {
                HStack(spacing: 16) {
                    if !message.text.isEmpty {
                        Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "square.on.square") }
                            .accessibilityLabel("Copy response")
                        Button {
                            if speech?.isSpeaking == true { speech?.stopSpeaking(at: .immediate) }
                            else {
                                if speech == nil { speech = AVSpeechSynthesizer() }
                                speech?.speak(AVSpeechUtterance(string: message.text))
                            }
                        } label: { Image(systemName: "speaker.wave.2") }
                            .accessibilityLabel("Read aloud")
                        ShareLink(item: message.text) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Share response")
                    } else if let photo = message.attachments.first {
                        ShareLink(item: Image(uiImage: photo.image), preview: SharePreview("Local Studio artwork", image: Image(uiImage: photo.image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share artwork")
                    }
                    Menu {
                        if !message.text.isEmpty {
                            Button("Select text", systemImage: "text.cursor") { selectingText = true }
                        }
                        Text("Frontend preview · local models coming later")
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Response options")
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
