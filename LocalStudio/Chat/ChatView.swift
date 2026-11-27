import SwiftUI

struct ChatView: View {
    @Bindable var session: ChatSession
    @State private var followsBottom = true
    @State private var bottomDistance: CGFloat = 0
    @State private var isUserScrolling = false
    @State private var keyboardVisible = false
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var width: CGFloat = 430
    @State private var viewportHeight: CGFloat = 839
    @State private var composerFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(session.messages) { message in
                        MessageView(message: message, edit: {
                            session.edit(message)
                            composerFocused = true
                        })
                        .transition(.asymmetric(
                            insertion: message.role == .user && !reduceMotion
                                ? .offset(y: max(0, viewportHeight - 116)).combined(with: .opacity) : .opacity,
                            removal: .opacity))
                    }
                    if session.isGenerating {
                        GenerationView(startedAt: session.generationStarted)
                            .accessibilityIdentifier("generation")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 14)
            }
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("conversation")
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: ConversationScrollMetrics.self) { geometry in
                ConversationScrollMetrics(
                    distance: max(0, geometry.contentSize.height + geometry.contentInsets.bottom
                                  - geometry.containerSize.height - geometry.contentOffset.y),
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height,
                    canScroll: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                               > geometry.containerSize.height + 1)
            } action: { old, value in
                bottomDistance = value.distance
                if !value.canScroll || value.distance <= 12 { followsBottom = true }
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
                                Path { path in
                                    path.move(to: CGPoint(x: 3, y: 4))
                                    path.addCurve(to: CGPoint(x: 21, y: 4), control1: CGPoint(x: 8, y: -1), control2: CGPoint(x: 16, y: -1))
                                    path.move(to: CGPoint(x: 23, y: 9))
                                    path.addCurve(to: CGPoint(x: 15, y: 23), control1: CGPoint(x: 25, y: 16), control2: CGPoint(x: 21, y: 22))
                                    path.move(to: CGPoint(x: 10, y: 23))
                                    path.addLine(to: CGPoint(x: 5, y: 21))
                                    path.addLine(to: CGPoint(x: 1, y: 23))
                                    path.addLine(to: CGPoint(x: 2, y: 18))
                                    path.addCurve(to: CGPoint(x: 1, y: 8), control1: CGPoint(x: -1, y: 15), control2: CGPoint(x: 0, y: 11))
                                }
                                    .stroke(style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                                    .frame(width: 23, height: 23)
                                    .frame(width: 44, height: 44)
                            }
                            .foregroundStyle(session.isTemporary ? StudioPalette.accent : .white)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel("Temporary chat")
                            .accessibilityValue(session.isTemporary ? "On" : "Off")
                            .accessibilityIdentifier("temporaryChat")
                        } else {
                            HStack(spacing: 8) {
                                Button { session.newChat() } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 23, weight: .medium))
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("New chat")
                                .accessibilityIdentifier("newChat")
                                Menu {
                                    Text(session.isTemporary ? "Temporary chat" : "Local Studio")
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 23, weight: .semibold))
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
                .padding(.horizontal, 20)
                .padding(.top, 0)
                .padding(.bottom, 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerView(session: session, availableWidth: width, focused: $composerFocused) {
                    followsBottom = true
                    isUserScrolling = false
                    composerFocused = false
                    session.send()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.86)) {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                }
                .overlay(alignment: .top) {
                    if !followsBottom && bottomDistance > 24 && !session.messages.isEmpty {
                        Button {
                            followsBottom = true
                            isUserScrolling = false
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { scrollPosition.scrollTo(edge: .bottom) }
                        } label: {
                            Path { path in
                                path.move(to: CGPoint(x: 18, y: 11.5))
                                path.addLine(to: CGPoint(x: 18, y: 24))
                                path.move(to: CGPoint(x: 12.5, y: 18.5))
                                path.addLine(to: CGPoint(x: 18, y: 24))
                                path.addLine(to: CGPoint(x: 23.5, y: 18.5))
                            }
                                .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                .frame(width: 36, height: 36)
                        }
                        .foregroundStyle(.white)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Scroll to bottom")
                        .accessibilityIdentifier("scrollToBottom")
                        .offset(y: -50)
                    }
                }
                .padding(.bottom, keyboardVisible ? 12 : 0)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: {
                width = $0.width
                viewportHeight = $0.height
            }
            .onChange(of: session.messages.count) {
                if session.messages.isEmpty { followsBottom = true }
                if followsBottom { withAnimation(reduceMotion ? nil : .smooth) { scrollPosition.scrollTo(edge: .bottom) } }
            }
        }
        .task { await session.restore() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) { keyboardVisible = frame.height > 100 }
            if followsBottom { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                keyboardVisible = false
                composerFocused = false
            }
            if followsBottom { scrollPosition.scrollTo(edge: .bottom) }
        }
        .alert("Storage unavailable", isPresented: Binding(get: { session.storageError != nil }, set: { if !$0 { session.storageError = nil } })) {
            Button("OK") { session.storageError = nil }
        } message: { Text(session.storageError ?? "") }
    }
}

private struct ConversationScrollMetrics: Equatable {
    let distance: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let canScroll: Bool
}
