import SwiftUI
import AVFoundation

struct MessageView: View {
    let message: ChatMessage
    let edit: () -> Void
    let selectText: () -> Void
    @State private var speech: AVSpeechSynthesizer?

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
                                .foregroundStyle(.white)
                                .glassEffect(.clear.interactive(), in: .circle)
                                .padding(20)
                            }
                            .accessibilityLabel("Demo artwork")
                    }
                }
            }
            if !message.text.isEmpty {
                if message.role == .user {
                    HStack {
                        Spacer(minLength: 60)
                        Text(message.text)
                            .font(.system(size: 17))
                            .lineSpacing(3)
                            .foregroundStyle(StudioPalette.prompt)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(StudioPalette.bubble, in: .rect(cornerRadius: 24))
                            .contextMenu {
                                Text(Calendar.current.isDateInToday(message.createdAt)
                                     ? "Today, \(message.createdAt.formatted(date: .omitted, time: .shortened))"
                                     : message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Button("Copy", systemImage: "square.on.square") { UIPasteboard.general.string = message.text }
                                Button("Edit", systemImage: "pencil", action: edit)
                                Button("Select text", systemImage: "text.cursor", action: selectText)
                                ShareLink(item: message.text) { Label("Share prompt", systemImage: "square.and.arrow.up") }
                            }
                            .tint(.white)
                            .accessibilityIdentifier("userMessage")
                    }
                } else {
                    Text(message.text)
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
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
                            Button("Select text", systemImage: "text.cursor", action: selectText)
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
    }
}
