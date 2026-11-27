import SwiftUI

struct ChatView: View {
    @Bindable var session: ChatSession
    @State private var atBottom = true
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var width: CGFloat = 430
    @State private var workSelected = false
    @State private var selectedText: String?
    @FocusState private var composerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    if workSelected {
                        ForEach(session.messages.filter { $0.role == .assistant && !$0.attachments.isEmpty }) { message in
                            MessageView(message: message, edit: { session.edit(message) }, selectText: { selectedText = message.text })
                        }
                    } else {
                        ForEach(session.messages) { message in
                            MessageView(message: message, edit: {
                                session.edit(message)
                                composerFocused = true
                            }, selectText: { selectedText = message.text })
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                        if session.isGenerating {
                            GenerationView(startedAt: session.generationStarted)
                                .accessibilityIdentifier("generation")
                        }
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
                        if session.messages.isEmpty {
                            Button { session.toggleTemporary() } label: {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 23, weight: .medium))
                                    .frame(width: 44, height: 44)
                            }
                            .foregroundStyle(session.isTemporary ? StudioPalette.accent : .white)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel("Temporary chat")
                            .accessibilityValue(session.isTemporary ? "On" : "Off")
                            .accessibilityIdentifier("temporaryChat")
                            Spacer()
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
                            Spacer()
                        }
                    }
                    .overlay {
                        if session.messages.isEmpty {
                            Picker("Studio", selection: $workSelected) {
                                Text("Chat").tag(false)
                                Text("Work").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 158, height: 44)
                            .glassEffect(.regular, in: .capsule)
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
                .padding(.top, 2)
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
                .padding(.bottom, 8)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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
