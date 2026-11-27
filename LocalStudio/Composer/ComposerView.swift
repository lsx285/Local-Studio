import PhotosUI
import SwiftUI
import ImageIO

struct ComposerView: View {
    @Bindable var session: ChatSession
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    @Binding var focused: Bool
    @Binding var fullScreen: Bool
    let send: () -> Void
    @State private var pickerPresented = false
    @State private var fullPickerPresented = false
    @State private var pendingSelection: [PhotosPickerItem] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @State private var photoError = false
    @State private var galleryDrag: CGFloat = 0
    @State private var fullscreenOffset: CGFloat = 0
    @State private var changingFullscreen = false
    @State private var fullscreenTransition: Task<Void, Never>?
    @State private var editorGestureBounds: CGRect = .null
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var railAnimation: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86) }

    private func setFullscreenLayout(_ expanded: Bool, offset: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            fullScreen = expanded
            fullscreenOffset = offset
        }
    }

    private func toggleFullscreen() {
        guard !changingFullscreen else { return }
        fullscreenTransition?.cancel()
        if reduceMotion {
            setFullscreenLayout(!fullScreen, offset: 0)
            focused = true
            return
        }
        changingFullscreen = true
        focused = true
        let closing = fullScreen
        let travel = min(650, availableHeight)
        fullscreenTransition = Task { @MainActor in
            defer { changingFullscreen = false; fullscreenTransition = nil }
            do {
                if closing {
                    // The reference dismisses the large panel faster than it presents it.
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) {
                        fullscreenOffset = travel
                    }
                    try await Task.sleep(for: .seconds(0.22))
                    try Task.checkCancellation()
                    setFullscreenLayout(false, offset: 0)
                } else {
                    // Presentation changes only the panel; keep the current keyboard/responder.
                    setFullscreenLayout(true, offset: travel)
                    // Commit the offscreen layout before starting its presentation transform.
                    try await Task.sleep(for: .milliseconds(17))
                    try Task.checkCancellation()
                    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.35)) {
                        fullscreenOffset = 0
                    }
                    try await Task.sleep(for: .seconds(0.35))
                }
            } catch { /* The view disappeared or the presentation was cancelled. */ }
        }
    }

    private func dismissGallery() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            pickerPresented = false
            galleryDrag = 0
        }
        pendingSelection = []
    }

    private var expanded: Bool {
        fullScreen || session.draft.contains("\n") || (session.draft as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 17)]).width > availableWidth - sideInset * 2 - 100
    }

    private var sideInset: CGFloat { focused || session.draft.contains("\n") ? 12 : 34 }

    private var draftHeight: CGFloat {
        let width = max(1, availableWidth - 24 - 32)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        return ((session.draft + "\u{200B}") as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 17), .paragraphStyle: paragraph], context: nil).height
    }

    private var overflowing: Bool { draftHeight > 168 }
    private var showsExpansionControl: Bool { fullScreen || draftHeight >= 96 }

    var body: some View {
        VStack(spacing: 0) {
            if !session.attachments.isEmpty && !fullScreen {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(session.attachments) { attachment in
                            Image(uiImage: attachment.image)
                                .resizable().scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(.rect(cornerRadius: 20))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation(railAnimation) { session.attachments.removeAll { $0.id == attachment.id } }
                                    } label: {
                                        StudioIcon(.close)
                                            .background(.black.opacity(0.5), in: .circle)
                                    }
                                    .accessibilityLabel("Remove attachment")
                                    .padding(8)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .clipped()

            }
            ZStack(alignment: .bottom) {
                ComposerEditor(text: $session.draft, focused: $focused, expanded: expanded, overflowing: !fullScreen && overflowing,
                               fullScreen: fullScreen, transitioning: changingFullscreen,
                               showsExpansionControl: showsExpansionControl && !fullScreen)
                    .frame(height: fullScreen ? max(100, availableHeight - 158) : nil)
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .named("composerGestures"))
                    } action: { editorGestureBounds = $0 }
                    .padding(.leading, expanded ? 16 : 48)
                    .padding(.trailing, expanded ? 16 : 52)
                    .padding(.top, fullScreen ? 78 : expanded ? 16 : 8)
                    .padding(.bottom, fullScreen ? 80 : expanded ? 52 : 8)
                HStack(alignment: .center, spacing: 12) {
                    if !fullScreen {
                        Button {
                            focused = false
                            pendingSelection = []
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { pickerPresented = true }
                        } label: {
                            if loadingPhotos {
                                ProgressView().frame(width: 32, height: 32)
                            } else {
                                StudioIcon(.plus)
                            }
                        }
                        .disabled(loadingPhotos || session.attachments.count >= 8)
                        .accessibilityLabel("Add photos")

                    }
                    Spacer(minLength: 0)
                    Button {
                        if session.isGenerating { session.cancelGeneration() }
                        else { fullScreen = false; send() }
                    } label: {
                        ZStack {
                            Circle().fill(StudioPalette.accent)
                            StudioIcon(session.isGenerating ? .stop : .upArrow)
                        }
                        .frame(width: 32, height: 32)
                    }
                    .disabled(!session.isGenerating && !session.canSend)
                    .opacity(session.isGenerating || session.canSend ? 1 : 0)
                    .allowsHitTesting(session.isGenerating || session.canSend)
                    .accessibilityHidden(!session.isGenerating && !session.canSend)
                    .accessibilityLabel(session.isGenerating ? "Stop generation" : "Send prompt")

                }
                .padding(.horizontal, fullScreen ? 24 : 8)
                .padding(.vertical, fullScreen ? 24 : 8)
            }
        }
        .foregroundStyle(.white)
        .background {
            if !fullScreen {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: expanded || !session.attachments.isEmpty ? 28 : 26))
            }
        }
        .clipShape(.rect(topLeadingRadius: fullScreen ? 40 : expanded || !session.attachments.isEmpty ? 28 : 26,
                         bottomLeadingRadius: fullScreen ? 0 : expanded || !session.attachments.isEmpty ? 28 : 26,
                         bottomTrailingRadius: fullScreen ? 0 : expanded || !session.attachments.isEmpty ? 28 : 26,
                         topTrailingRadius: fullScreen ? 40 : expanded || !session.attachments.isEmpty ? 28 : 26))
        .background {
            if fullScreen {
                // Extend only the backdrop below the keyboard and home indicator.
                // Applied after clipping so the editor keeps its keyboard-aware bounds.
                UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40)
                    .fill(StudioPalette.fullscreenComposer)
                    .ignoresSafeArea(.all, edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsExpansionControl {
                Button {
                    toggleFullscreen()
                } label: {
                    StudioIcon(fullScreen ? .collapse : .expand)
                }
                .foregroundStyle(.white.opacity(fullScreen ? 1 : 0.65))
                .disabled(changingFullscreen)
                .accessibilityLabel(fullScreen ? "Collapse composer" : "Expand composer")
                .padding(.top, fullScreen ? 16 : (session.attachments.isEmpty ? 12 : 148))
                .padding(.trailing, fullScreen ? 16 : 8)
            }
        }
        .padding(.horizontal, fullScreen ? 0 : expanded || focused ? 12 : 34)
        .coordinateSpace(name: "composerGestures")
        .simultaneousGesture(DragGesture(minimumDistance: 12, coordinateSpace: .named("composerGestures")).onChanged { value in
            guard !pickerPresented, !changingFullscreen,
                  !editorGestureBounds.isNull,
                  !editorGestureBounds.insetBy(dx: -16, dy: -28).contains(value.startLocation),
                  abs(value.translation.height) > abs(value.translation.width) * 1.25 else { return }
            focused = value.translation.height < 0
        })
        .animation(.easeOut(duration: 0.18), value: expanded)
        .animation(.easeOut(duration: 0.25), value: focused)
        .offset(y: fullscreenOffset)
        .onDisappear { fullscreenTransition?.cancel() }
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
                                dismissGallery()
                            } label: {
                                StudioIcon(.back)
                            }
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel("Close photo gallery")

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
                            .glassEffect((pendingSelection.isEmpty ? Glass.clear : Glass.clear.tint(Color(red: 0.02, green: 0.19, blue: 0.96))).interactive(), in: .capsule)

                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 12)
                    .offset(y: 22 + galleryDrag)
                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard value.translation.height > 0,
                                  value.translation.height > abs(value.translation.width) * 1.25 else { return }
                            galleryDrag = value.translation.height
                        }
                        .onEnded { value in
                            if galleryDrag > 44 || (galleryDrag > 12 && value.predictedEndTranslation.height > 100) {
                                dismissGallery()
                            } else {
                                withAnimation(railAnimation) { galleryDrag = 0 }
                            }
                        })
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
