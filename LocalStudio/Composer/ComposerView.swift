import PhotosUI
import SwiftUI
import ImageIO

struct ComposerView: View {
    @Bindable var session: ChatSession
    let availableWidth: CGFloat
    var focused: FocusState<Bool>.Binding
    let send: () -> Void
    @State private var pickerPresented = false
    @State private var fullPickerPresented = false
    @State private var pendingSelection: [PhotosPickerItem] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @State private var photoError = false

    private var expanded: Bool {
        session.draft.contains("\n") || (session.draft as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width > availableWidth - 158
    }

    var body: some View {
        VStack(spacing: 0) {
            if !session.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(session.attachments) { attachment in
                            Image(uiImage: attachment.image)
                                .resizable().scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(.rect(cornerRadius: 20))
                                .overlay(alignment: .topTrailing) {
                                    Button { session.attachments.removeAll { $0.id == attachment.id } } label: {
                                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                                            .frame(width: 23, height: 23)
                                            .background(.black.opacity(0.5), in: .circle)
                                    }
                                    .accessibilityLabel("Remove attachment")
                                    .padding(8)
                                }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
            }
            if expanded {
                TextField("Ask Local Studio", text: $session.draft, axis: .vertical)
                    .font(.system(size: 17))
                    .lineLimit(2...6)
                    .focused(focused)
                    .accessibilityIdentifier("composer")
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
            HStack(alignment: .center, spacing: 12) {
                Button {
                    focused.wrappedValue = false
                    pendingSelection = []
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { pickerPresented = true }
                } label: {
                    if loadingPhotos {
                        ProgressView().frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "plus").font(.system(size: 26, weight: .regular))
                            .frame(width: 32, height: 32)
                    }
                }
                .disabled(loadingPhotos || session.attachments.count >= 8)
                .accessibilityLabel("Add photos")
                .accessibilityIdentifier("addPhotos")
                if !expanded {
                    TextField("Ask Local Studio", text: $session.draft, axis: .vertical)
                        .font(.system(size: 17))
                        .lineLimit(1)
                        .focused(focused)
                        .accessibilityIdentifier("composer")
                }
                Spacer(minLength: 0)
                Button {
                    if session.isGenerating { session.cancelGeneration() } else { send() }
                } label: {
                    Image(systemName: session.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: session.isGenerating ? 14 : 23, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(StudioPalette.accent, in: .circle)
                }
                .disabled(!session.isGenerating && !session.canSend)
                .opacity(session.isGenerating || session.canSend ? 1 : 0.5)
                .accessibilityLabel(session.isGenerating ? "Stop generation" : "Send prompt")
                .accessibilityIdentifier("sendPrompt")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .foregroundStyle(.white)
        .glassEffect(.regular, in: .rect(cornerRadius: expanded || !session.attachments.isEmpty ? 28 : 26))
        .padding(.horizontal, expanded ? 12 : 34)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: expanded)
        .overlay(alignment: .bottom) {
            if pickerPresented {
                PhotosPicker(selection: $pendingSelection, maxSelectionCount: max(1, 8 - session.attachments.count),
                             selectionBehavior: .continuousAndOrdered, matching: .images) { EmptyView() }
                    .photosPickerStyle(.inline)
                    .photosPickerAccessoryVisibility(.hidden)
                    .photosPickerDisabledCapabilities([.selectionActions, .search, .collectionNavigation, .stagingArea])
                    .frame(height: availableWidth * 1.26)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: 44))
                    .overlay(alignment: .bottom) {
                        HStack {
                            Button {
                                withAnimation { pickerPresented = false }
                                pendingSelection = []
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 23, weight: .medium))
                                    .frame(width: 44, height: 44)
                            }
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel("Close photo gallery")
                            .accessibilityIdentifier("closePhotoGallery")
                            Spacer()
                            Button {
                                pickerPresented = false
                                if pendingSelection.isEmpty { fullPickerPresented = true }
                                else {
                                    selection = pendingSelection
                                    pendingSelection = []
                                }
                            } label: {
                                Text(pendingSelection.isEmpty ? "All Photos" : "Add \(pendingSelection.count) photo\(pendingSelection.count == 1 ? "" : "s")")
                                    .font(.system(size: 17, weight: .semibold))
                                    .padding(.horizontal, 22)
                                    .frame(height: 44)
                            }
                            .glassEffect(.regular.tint(pendingSelection.isEmpty ? .clear : StudioPalette.accent).interactive(), in: .capsule)
                            .accessibilityIdentifier("confirmPhotos")
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 12)
                    .offset(y: 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .photosPicker(isPresented: $fullPickerPresented, selection: $selection,
                      maxSelectionCount: max(1, 8 - session.attachments.count), selectionBehavior: .ordered, matching: .images)
        .task(id: selection) {
            guard !selection.isEmpty else { return }
            loadingPhotos = true
            defer { loadingPhotos = false }
            for item in selection {
                guard !Task.isCancelled else { return }
                do {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let resized = await Self.downsample(data), let photo = PhotoAttachment(data: resized), session.attachments.count < 8 {
                        session.attachments.append(photo)
                    } else { photoError = true }
                } catch { photoError = true }
            }
            selection = []
        }
        .alert("Photo couldn’t be opened", isPresented: $photoError) {
            Button("OK", role: .cancel) { }
        } message: { Text("Try another photo or download the original from iCloud first.") }
    }

    /// Decode off the main actor and cap memory before a photo enters the view tree.
    nonisolated private static func downsample(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1600
                  ] as CFDictionary) else { return nil }
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return result as Data
        }.value
    }
}
