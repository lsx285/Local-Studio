import SwiftUI

struct ChatView: View {
    @Bindable var session: ChatSession
    @State private var followsBottom = true
    @State private var farFromBottom = false
    @State private var isUserScrolling = false
    @State private var keyboardVisible = false
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var composerFocused = false
    @State private var composerFullScreen = false
    @State private var composerTransitioning = false
    @State private var settingsPresented = false
    @State private var galleryPresented = false
    @State private var viewer: ViewerRequest?
    @State private var imageFrames = ArtworkFrames()
    @State private var endVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsScrollButton: Bool {
        !composerFullScreen && !composerTransitioning && !endVisible && !followsBottom && farFromBottom && !session.messages.isEmpty
    }

    private func openArtwork(_ id: UUID) {
        let photos = session.messages.filter { $0.role == .assistant }.flatMap { message in
            message.attachments.map { ViewerPhoto(photo: $0, date: message.createdAt, metadata: message.metadata) }
        }
        guard photos.contains(where: { $0.id == id }) else { return }
        composerFocused = false
        viewer = ViewerRequest(photos: photos, selectedID: id, limited: false)
    }

    var body: some View {
        GeometryReader { canvas in
            let width = canvas.size.width
            let viewportHeight = canvas.size.height
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(session.messages.filter { !$0.text.isEmpty || !$0.attachments.isEmpty || $0.id == session.respondingMessageID }) { message in
                            if !message.text.isEmpty || !message.attachments.isEmpty {
                                MessageView(message: message, isResponding: session.respondingMessageID == message.id, availableWidth: max(1, width - 32), openArtwork: openArtwork, reportArtworkFrame: { imageFrames.values[$0] = $1 }, editArtwork: { photo in
                                    guard session.attachments.count < 8, let attachment = PhotoAttachment(data: photo.data) else {
                                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                        return
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) { session.attachments.append(attachment) }
                                    composerFocused = true
                                }, canRetry: !session.isGenerating && !session.isEnhancing && session.connection.isConnected, retryResponse: session.retry) { message in
                                    session.edit(message)
                                    composerFocused = true
                                }
                                .equatable()
                                .transition(.asymmetric(
                                    insertion: message.role == .user && !reduceMotion
                                        ? .offset(y: max(0, viewportHeight - 116)).combined(with: .opacity) : .opacity,
                                    removal: .opacity))
                            }
                            // Progress renders at the response's own position, so a retry of an earlier reply
                            // generates in place instead of looking like a new message at the bottom.
                            if message.id == session.respondingMessageID {
                                GenerationView(startedAt: session.generationStarted, stage: session.generationStage,
                                               progress: session.generationProgress, image: session.isImageGeneration,
                                               aspectRatio: session.generationAspectRatio, availableWidth: max(1, width - 32))
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onScrollVisibilityChange(threshold: 0.1) { visible in
                                guard !composerFullScreen && !composerTransitioning else { return }
                                if endVisible != visible { endVisible = visible }
                                if visible {
                                    if !followsBottom { followsBottom = true }
                                    if farFromBottom { farFromBottom = false }
                                }
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 14)
                }
                // Continue drawing artwork beneath the safe-area composer so Liquid Glass samples it.
                .scrollClipDisabled()
                .scrollPosition($scrollPosition)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                // Growing content (streamed text, new rows, keyboard) keeps the bottom in view while following;
                // otherwise the reader's position stays put.
                .defaultScrollAnchor(followsBottom ? .bottom : .top, for: .sizeChanges)
                .scrollDismissesKeyboard(composerFullScreen || composerTransitioning ? .never : .interactively)
                .scrollDisabled(composerFullScreen || composerTransitioning)
                .onScrollPhaseChange { _, phase in
                    let scrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    if isUserScrolling != scrolling { isUserScrolling = scrolling }
                }
                .onScrollGeometryChange(for: ConversationScrollMetrics.self) { geometry in
                    ConversationScrollMetrics(
                        distance: max(0, geometry.contentSize.height - geometry.visibleRect.maxY),
                        canScroll: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                                   > geometry.containerSize.height + 1)
                } action: { _, value in
                    guard !composerFullScreen && !composerTransitioning else { return }
                    // Only write state when it changes: this runs on every scroll frame, and each
                    // write re-renders the conversation.
                    let far = value.distance > 24
                    if farFromBottom != far { farFromBottom = far }
                    if endVisible || !value.canScroll || value.distance <= 16 { if !followsBottom { followsBottom = true } }
                    else if isUserScrolling && value.distance > 48 && followsBottom { followsBottom = false }
                    // No scrolling from here: this runs inside layout. Rows restored from disk start with
                    // estimated heights, so scrolling to the bottom from a geometry change could realize a row,
                    // change the content height, and scroll again without end — the send-after-relaunch freeze.
                    // Pinning on size changes is left to the scroll view's own anchor below.
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            if session.messages.isEmpty {
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    session.toggleTemporary()
                                } label: {
                                    StudioIcon(session.isTemporary ? .temporaryChecked : .temporary)
                                }
                                .foregroundStyle(.white)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .accessibilityLabel("Temporary chat")
                                .accessibilityValue(session.isTemporary ? "On" : "Off")

                            } else {
                                HStack(spacing: 8) {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        session.newChat()
                                    } label: {
                                        StudioIcon(.newChat)
                                    }
                                    .accessibilityLabel("New chat")

                                    Menu {
                                        Section {
                                            Button {
                                                composerFocused = false
                                                settingsPresented = true
                                            } label: {
                                                Label { Text("Settings") } icon: { StudioIcon(.settings) }
                                            }
                                        } header: {
                                            Text("Local Studio \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                    } label: {
                                        StudioIcon(.moreHeader)
                                    }
                                    .accessibilityLabel("More options")
                                    .tint(.white)
                                }
                                .padding(.horizontal, 4)
                                .foregroundStyle(.white)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                        }
                    }
                    .frame(height: composerFullScreen ? 0 : nil)
                    .opacity(composerFullScreen ? 0 : 1)
                    .allowsHitTesting(!composerFullScreen)
                    .padding(.horizontal, 20)
                }
                // While the gallery is open, any touch outside it closes it. This layer sits above the
                // conversation and header but beneath the composer inset, which hosts the gallery.
                .overlay {
                    if galleryPresented {
                        Color.clear
                            .contentShape(.rect)
                            .ignoresSafeArea()
                            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                                guard galleryPresented else { return }
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { galleryPresented = false }
                            })
                            .accessibilityAction(.escape) { galleryPresented = false }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerView(session: session, availableWidth: width, availableHeight: viewportHeight,
                                 focused: $composerFocused, fullScreen: $composerFullScreen,
                                 changingFullscreen: $composerTransitioning, pickerPresented: $galleryPresented,
                                 openAttachment: { id in
                                     composerFocused = false
                                     viewer = ViewerRequest(photos: session.attachments.map { ViewerPhoto(photo: $0, date: .now) }, selectedID: id, limited: true)
                                 }, reportAttachmentFrame: { imageFrames.values[$0] = $1 }) {
                        followsBottom = true
                        isUserScrolling = false
                        composerFocused = false
                        session.send()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.86)) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    }
                    .disabled(!session.connection.isConnected)
                    .allowsHitTesting(session.connection.isConnected)
                    .opacity(session.connection.isConnected ? 1 : 0.45)
                    // Behind the composer, so the photo gallery it presents covers the button.
                    .background(alignment: .top) {
                        ZStack {
                            if showsScrollButton {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    followsBottom = true
                                    isUserScrolling = false
                                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { scrollPosition.scrollTo(edge: .bottom) }
                                } label: {
                                    StudioIcon(.downArrow)
                                }
                                .foregroundStyle(.white)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .accessibilityLabel("Scroll to bottom")
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                                .offset(y: -50)
                            }
                        }
                        .animation(reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2), value: showsScrollButton)
                    }
                    .padding(.bottom, keyboardVisible && !composerFullScreen ? 12 : 0)
                }
                .onChange(of: session.messages.count) {
                    if session.messages.isEmpty { followsBottom = true }
                    if followsBottom && !composerFullScreen && !composerTransitioning { withAnimation(reduceMotion ? nil : .smooth) { scrollPosition.scrollTo(edge: .bottom) } }
                }
            }
            .overlay {
                if let viewer {
                    ArtworkViewer(request: viewer, sourceFrames: imageFrames.values, edit: { photo in
                        if session.attachments.count < 8, let attachment = PhotoAttachment(data: photo.data) { session.attachments.append(attachment) }
                        else { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                        composerFocused = true
                    }, remove: { id in
                        if viewer.limited { session.attachments.removeAll { $0.id == id } }
                        else { session.removeArtwork(id) }
                    }, dismiss: { self.viewer = nil })
                    .zIndex(10)
                }
            }
            .task { session.connection.discover(); await session.restore() }
            .sheet(isPresented: $settingsPresented) {
                StudioSettingsView(session: session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) { keyboardVisible = frame.height > 100 }
                if followsBottom && !composerFullScreen && !composerTransitioning { scrollPosition.scrollTo(edge: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    keyboardVisible = false
                }
                if followsBottom && !composerFullScreen && !composerTransitioning { scrollPosition.scrollTo(edge: .bottom) }
            }
            .alert("Storage unavailable", isPresented: Binding(get: { session.storageError != nil }, set: { if !$0 { session.storageError = nil } })) {
                Button("OK") { session.storageError = nil }
            } message: { Text(session.storageError ?? "") }
            .alert("Couldn’t complete request", isPresented: Binding(get: { session.generationError != nil }, set: { if !$0 { session.generationError = nil } })) {
                Button("OK") { session.generationError = nil }
            } message: { Text(session.generationError ?? "") }
            // A finished image lands with a success tap; a finished text reply settles with a soft one.
            .sensoryFeedback(trigger: session.completedResponses) { _, _ in
                session.isImageGeneration ? .success : .impact(flexibility: .soft, intensity: 0.6)
            }
            .sensoryFeedback(.error, trigger: session.generationError) { _, new in new != nil }
            .sensoryFeedback(.error, trigger: session.storageError) { _, new in new != nil }
            .sensoryFeedback(.warning, trigger: session.connection.isConnected) { old, new in old && !new }
            .onChange(of: session.connection.isConnected) {
                if !session.connection.isConnected { composerFocused = false }
            }
        }
    }
}

/// Artwork frames are reported on every scroll frame but only read when the viewer opens,
/// so they live outside observed state and never invalidate the conversation.
private final class ArtworkFrames {
    var values: [UUID: CGRect] = [:]
}

private struct ConversationScrollMetrics: Equatable {
    let distance: CGFloat
    let canScroll: Bool
}
