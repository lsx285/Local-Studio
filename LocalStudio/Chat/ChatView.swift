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
    @State private var endVisible = true
    @State private var promptMenu: PresentedPromptMenu?
    @State private var promptShare: PromptShare?
    @State private var selectedMessageID: UUID?
    @State private var selectionRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsScrollButton: Bool {
        !composerFullScreen && !endVisible && !followsBottom && bottomDistance > 24 && !session.messages.isEmpty
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
                            MessageView(message: message, showPromptMenu: { message, frame in
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                                    promptMenu = PresentedPromptMenu(message: message, frame: frame)
                                }
                            }, selectionRequest: selectedMessageID == message.id ? selectionRevision : 0)
                            .transition(.asymmetric(
                                insertion: message.role == .user && !reduceMotion
                                    ? .offset(y: max(0, viewportHeight - 116)).combined(with: .opacity) : .opacity,
                                removal: .opacity))
                        }
                        if session.isGenerating {
                            GenerationView(startedAt: session.generationStarted, availableWidth: width - 32)
                                .accessibilityIdentifier("generation")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onScrollVisibilityChange(threshold: 0.1) { visible in
                                guard !composerFullScreen else { return }
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
                .scrollDismissesKeyboard(.interactively)
                .scrollDisabled(composerFullScreen)
                .accessibilityIdentifier("conversation")
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
                    guard !composerFullScreen else { return }
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
                                .accessibilityIdentifier("temporaryChat")
                            } else {
                                HStack(spacing: 8) {
                                    Button { session.newChat() } label: {
                                        StudioIcon(.newChat)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("New chat")
                                    .accessibilityIdentifier("newChat")
                                    Menu {
                                        Text(session.isTemporary ? "Temporary chat" : "Local Studio")
                                    } label: {
                                        StudioIcon(.moreHeader)
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("More options")
                                }
                                .padding(.horizontal, 4)
                                .foregroundStyle(.white)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                        }
                    }
                    .frame(height: composerFullScreen ? 0 : nil)
                    .clipped()
                    .opacity(composerFullScreen ? 0 : 1)
                    .allowsHitTesting(!composerFullScreen)
                    .padding(.horizontal, 20)
                    .padding(.top, 0)
                    .padding(.bottom, 0)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerView(session: session, availableWidth: width, availableHeight: viewportHeight,
                                 focused: $composerFocused, fullScreen: $composerFullScreen) {
                        followsBottom = true
                        isUserScrolling = false
                        composerFocused = false
                        session.send()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.86)) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    }
                    .overlay(alignment: .top) {
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
                            .accessibilityIdentifier("scrollToBottom")
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.55)
                                .combined(with: .opacity).combined(with: .offset(y: 8)))
                            .offset(y: -50)
                        }
                    }
                    .animation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: showsScrollButton)
                    .padding(.bottom, keyboardVisible && !composerFullScreen ? 12 : 0)
                }
                .onChange(of: session.messages.count) {
                    if session.messages.isEmpty { followsBottom = true }
                    if followsBottom && !composerFullScreen { withAnimation(reduceMotion ? nil : .smooth) { scrollPosition.scrollTo(edge: .bottom) } }
                }
            }
            .overlay {
                if let presented = promptMenu {
                    GeometryReader { geometry in
                        let origin = geometry.frame(in: .global).origin
                        let anchor = presented.frame.offsetBy(dx: -origin.x - 4, dy: -origin.y)
                        let previewBottom = anchor.midY + anchor.height * 0.575
                        let below = previewBottom + 20
                        let menuTop = below + 216 <= geometry.size.height - 8
                            ? below : max(8, anchor.minY - 236)
                        ZStack(alignment: .topLeading) {
                            Color.black.opacity(0.5).ignoresSafeArea()
                                .onTapGesture { promptMenu = nil }
                            Text(presented.message.text)
                                .font(.system(size: 17)).lineSpacing(3)
                                .foregroundStyle(StudioPalette.prompt)
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                .frame(width: presented.frame.width, height: presented.frame.height)
                                .background(StudioPalette.bubble, in: .rect(cornerRadius: 24))
                                .scaleEffect(1.15, anchor: .trailing)
                                .transition(.scale(scale: 1 / 1.15, anchor: .trailing).combined(with: .opacity))
                                .position(x: anchor.midX, y: anchor.midY)
                                .allowsHitTesting(false)
                            PromptContextMenu(message: presented.message) { action in
                                promptMenu = nil
                                switch action {
                                case .copy: UIPasteboard.general.string = presented.message.text
                                case .edit:
                                    session.edit(presented.message)
                                    composerFocused = true
                                case .selectText:
                                    selectedMessageID = presented.message.id
                                    selectionRevision += 1
                                case .share: promptShare = PromptShare(text: presented.message.text)
                                }
                            }
                            .position(x: geometry.size.width - 145, y: menuTop + 108)
                        }
                    }
                }
            }
            .sheet(item: $promptShare) { PromptShareSheet(text: $0.text) }
            .task { await session.restore() }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) { keyboardVisible = frame.height > 100 }
                if followsBottom && !composerFullScreen { scrollPosition.scrollTo(edge: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    keyboardVisible = false
                    composerFocused = false
                }
                if followsBottom && !composerFullScreen { scrollPosition.scrollTo(edge: .bottom) }
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
