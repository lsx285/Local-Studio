import SwiftUI

struct ChatView: View {
    @Bindable var session: ChatSession
    @State private var atBottom = true
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var width: CGFloat = 430
    @State private var viewportHeight: CGFloat = 839
    @State private var selectedText: String?
    @FocusState private var composerFocused: Bool
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
                        }, selectText: { selectedText = message.text })
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
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 50
            } action: { _, value in atBottom = value }
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
                    if session.messages.isEmpty && session.isTemporary {
                        Label("Temporary chat", systemImage: "text.badge.minus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(red: 65 / 255, green: 167 / 255, blue: 247 / 255))
                            .accessibilityIdentifier("temporaryBanner")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 0)
                .padding(.bottom, 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 14) {
                    if !atBottom && !session.messages.isEmpty {
                        Button {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { scrollPosition.scrollTo(edge: .bottom) }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 23, weight: .medium))
                                .frame(width: 36, height: 36)
                        }
                        .foregroundStyle(.white)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Scroll to bottom")
                    }
                    ComposerView(session: session, availableWidth: width, focused: $composerFocused) {
                        composerFocused = false
                        session.send()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.86)) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    }
                }
                .padding(.bottom, 0)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: {
                width = $0.width
                viewportHeight = $0.height
            }
            .onChange(of: session.messages.count) {
                if atBottom { withAnimation(reduceMotion ? nil : .smooth) { scrollPosition.scrollTo(edge: .bottom) } }
            }
        }
        .task { await session.restore() }
        .sheet(isPresented: Binding(get: { selectedText != nil }, set: { if !$0 { selectedText = nil } })) {
            NavigationStack {
                ScrollView { Text(selectedText ?? "").textSelection(.enabled).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                    .navigationTitle("Select text")
                    .toolbar { Button("Done") { selectedText = nil } }
            }
            .preferredColorScheme(.dark)
        }
        .alert("Storage unavailable", isPresented: Binding(get: { session.storageError != nil }, set: { if !$0 { session.storageError = nil } })) {
            Button("OK") { session.storageError = nil }
        } message: { Text(session.storageError ?? "") }
    }
}
