import SwiftUI

struct ChatView: View {
    @Bindable var session: ChatSession
    @State private var followsBottom = true
    @State private var bottomDistance: CGFloat = 0
    @State private var isUserScrolling = false
    @State private var keyboardVisible = false
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var composerFocused = false
    @State private var composerFullScreen = false
    @State private var composerTransitioning = false
    @State private var settingsPresented = false
    @State private var endVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsScrollButton: Bool {
        !composerFullScreen && !composerTransitioning && !endVisible && !followsBottom && bottomDistance > 24 && !session.messages.isEmpty
    }

    var body: some View {
        GeometryReader { canvas in
            let width = canvas.size.width
            let viewportHeight = canvas.size.height
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(session.messages) { message in
                            MessageView(message: message, canRetry: !session.isGenerating, retryResponse: session.retry) { message in
                                session.edit(message)
                                composerFocused = true
                            }
                            .transition(.asymmetric(
                                insertion: message.role == .user && !reduceMotion
                                    ? .offset(y: max(0, viewportHeight - 116)).combined(with: .opacity) : .opacity,
                                removal: .opacity))
                        }
                        if session.isGenerating {
                            GenerationView(startedAt: session.generationStarted, availableWidth: width - 32)

                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onScrollVisibilityChange(threshold: 0.1) { visible in
                                guard !composerFullScreen && !composerTransitioning else { return }
                                endVisible = visible
                                if visible { followsBottom = true; bottomDistance = 0 }
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
                .scrollDismissesKeyboard(composerFullScreen || composerTransitioning ? .never : .interactively)
                .scrollDisabled(composerFullScreen || composerTransitioning)
                .onScrollPhaseChange { _, phase in
                    isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                }
                .onScrollGeometryChange(for: ConversationScrollMetrics.self) { geometry in
                    ConversationScrollMetrics(
                        distance: max(0, geometry.contentSize.height - geometry.visibleRect.maxY),
                        contentHeight: geometry.contentSize.height,
                        viewportHeight: geometry.containerSize.height,
                        canScroll: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                                   > geometry.containerSize.height + 1)
                } action: { old, value in
                    guard !composerFullScreen && !composerTransitioning else { return }
                    bottomDistance = value.distance
                    if endVisible || !value.canScroll || value.distance <= 16 { followsBottom = true }
                    else if isUserScrolling && value.distance > 48 { followsBottom = false }
                    if followsBottom && !isUserScrolling && (old.contentHeight != value.contentHeight || old.viewportHeight != value.viewportHeight) {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            if session.messages.isEmpty {
                                Button { session.toggleTemporary() } label: {
                                    StudioIcon(session.isTemporary ? .temporaryChecked : .temporary)
                                }
                                .foregroundStyle(.white)
                                .glassEffect(.regular.interactive(), in: .circle)
                                .accessibilityLabel("Temporary chat")
                                .accessibilityValue(session.isTemporary ? "On" : "Off")

                            } else {
                                HStack(spacing: 8) {
                                    Button { session.newChat() } label: {
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerView(session: session, availableWidth: width, availableHeight: viewportHeight,
                                 focused: $composerFocused, fullScreen: $composerFullScreen,
                                 changingFullscreen: $composerTransitioning) {
                        followsBottom = true
                        isUserScrolling = false
                        composerFocused = false
                        session.send()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.86)) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    }
                    .overlay(alignment: .top) {
                        ZStack {
                            if showsScrollButton {
                                Button {
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
            .task { await session.restore() }
            .sheet(isPresented: $settingsPresented) {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
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
        }
    }
}

private struct ConversationScrollMetrics: Equatable {
    let distance: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let canScroll: Bool
}
