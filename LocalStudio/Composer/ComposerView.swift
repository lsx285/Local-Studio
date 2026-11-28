import PhotosUI
import SwiftUI

struct ComposerView: View {
    @Bindable var session: ChatSession
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    @Binding var focused: Bool
    @Binding var fullScreen: Bool
    @Binding var changingFullscreen: Bool
    /// Owned by the chat so a touch anywhere outside the gallery can close it.
    @Binding var pickerPresented: Bool
    let openAttachment: (UUID) -> Void
    let reportAttachmentFrame: (UUID, CGRect) -> Void
    let send: () -> Void
    @State private var fullPickerPresented = false
    @State private var pendingSelection: [PhotosPickerItem] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @State private var photoError = false
    @State private var galleryDrag: CGFloat = 0
    @State private var editorGestureBounds: CGRect = .null
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var railAnimation: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86) }
    /// Shared by the Enhance and send buttons as they appear and disappear.
    private var controlAnimation: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.82) }

    private func toggleFullscreen() {
        guard !changingFullscreen else { return }
        focused = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let animation: Animation? = reduceMotion ? nil : fullScreen
            ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
            : .timingCurve(0.16, 1, 0.3, 1, duration: 0.35)
        changingFullscreen = true
        // Animate the same editor into its destination bounds. No offscreen
        // translation or delayed layout swap can move it beneath the keyboard.
        withAnimation(animation, completionCriteria: .removed) {
            fullScreen.toggle()
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { changingFullscreen = false }
        }
    }

    private func dismissGallery() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            pickerPresented = false
            galleryDrag = 0
        }
        pendingSelection = []
    }

    private func pasteImages(_ images: [Data]) {
        guard !loadingPhotos else { return }
        for data in images.prefix(session.attachmentSlots) {
            guard let photo = PhotoAttachment(data: data) else {
                photoError = true
                continue
            }
            withAnimation(railAnimation) { session.attachments.append(photo) }
        }
        if !images.isEmpty { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    var body: some View {
        // Text measurement is the composer's costliest work, and the body re-evaluates whenever the
        // conversation changes, so every draft metric is computed exactly once per pass.
        let draft = session.draft
        let multiline = draft.contains("\n")
        let sideInset: CGFloat = focused || multiline ? 12 : 34
        let inlineExpanded = multiline || (draft as NSString).size(withAttributes: ComposerEditor.attributes).width > availableWidth - sideInset * 2 - 100
        let expanded = fullScreen || inlineExpanded
        let draftHeight = ((draft + "\u{200B}") as NSString).boundingRect(with: CGSize(width: max(1, availableWidth - 24 - 32), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: ComposerEditor.attributes, context: nil).height
        let overflowing = draftHeight > 168
        let showsExpansionControl = fullScreen || draftHeight >= 96
        let inlineEditorHeight = inlineExpanded
            ? ComposerEditor.measuredHeight(text: draft, width: max(1, availableWidth - 56), reserve: showsExpansionControl) : 32
        let horizontalInset: CGFloat = fullScreen ? 0 : expanded || focused ? 12 : 34
        let canSend = session.canSend
        let showsEnhance = session.isEnhancing || session.hasPrompt
        let showsSend = session.isGenerating || canSend
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(session.connection.models) { model in
                        Button {
                            if session.selectedModelID != model.id { UISelectionFeedbackGenerator().selectionChanged() }
                            session.selectedModelID = model.id
                            session.saveSettings()
                        } label: {
                            Label("\(model.name) · \(model.capability)",
                                  systemImage: session.selectedModelID == model.id ? "checkmark" : "circle")
                        }
                        .disabled(!model.installed || session.isGenerating || session.isEnhancing || session.attachments.count > model.maxImages)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(session.selectedModel?.name ?? session.connection.status)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .accessibilityLabel("Model")
                .tint(.white)
                Spacer(minLength: 4)
                Button {
                    if session.isEnhancing {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
                        session.cancelGeneration()
                    } else {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        session.enhancePrompt()
                    }
                } label: {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !session.isEnhancing)) { timeline in
                        HStack(spacing: 5) {
                            // Palette rendering splits the symbol's layers: the wand holds still while its stars twinkle.
                            Image(systemName: "wand.and.stars")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.primary, .primary.opacity(session.isEnhancing
                                    ? 0.6 + 0.4 * sin(timeline.date.timeIntervalSinceReferenceDate * 7) : 1))
                            Text(session.isEnhancing ? "Enhancing" : "Enhance")
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                }
                .disabled(!session.canEnhance && !session.isEnhancing)
                .opacity(showsEnhance ? 1 : 0)
                .scaleEffect(showsEnhance || reduceMotion ? 1 : 0.7)
                .blur(radius: showsEnhance || reduceMotion ? 0 : 4)
                .allowsHitTesting(showsEnhance)
                .accessibilityHidden(!showsEnhance)
                .animation(controlAnimation, value: showsEnhance)
                .accessibilityLabel(session.isEnhancing ? "Stop prompt enhancement" : "Enhance prompt with Qwen")
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            if !session.attachments.isEmpty && !fullScreen {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(session.attachments) { attachment in
                            Image(uiImage: attachment.image)
                                .resizable().scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(.rect(cornerRadius: 20))
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { reportAttachmentFrame(attachment.id, $0) }
                                .onTapGesture { openAttachment(attachment.id) }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
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
                .frame(width: max(1, availableWidth - horizontalInset * 2), height: 136)
                .scrollIndicators(.hidden)
                .scrollClipDisabled(false)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))

            }
            ZStack(alignment: .bottom) {
                ComposerEditor(text: $session.draft, focused: $focused, expanded: expanded, overflowing: !fullScreen && overflowing,
                               fullScreen: fullScreen, transitioning: changingFullscreen,
                               showsExpansionControl: showsExpansionControl && !fullScreen,
                               pasteImageLimit: loadingPhotos ? 0 : session.attachmentSlots, pasteImages: pasteImages)
                    .frame(height: fullScreen ? max(100, availableHeight - 194) : inlineEditorHeight)
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                        .disabled(loadingPhotos || session.attachmentSlots == 0)
                        .accessibilityLabel("Add photos")

                    }
                    Spacer(minLength: 0)
                    Button {
                        if session.isGenerating {
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            session.cancelGeneration()
                        } else {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            fullScreen = false
                            send()
                        }
                    } label: {
                        ZStack {
                            Circle().fill(StudioPalette.accent)
                            StudioIcon(session.isGenerating ? .stop : .upArrow)
                        }
                        .frame(width: 32, height: 32)
                    }
                    .disabled(!showsSend)
                    .opacity(showsSend ? 1 : 0)
                    .scaleEffect(showsSend || reduceMotion ? 1 : 0.7)
                    .blur(radius: showsSend || reduceMotion ? 0 : 4)
                    .allowsHitTesting(showsSend)
                    .accessibilityHidden(!showsSend)
                    .animation(controlAnimation, value: showsSend)
                    .accessibilityLabel(session.isGenerating ? "Stop generation" : "Send prompt")

                }
                .padding(.horizontal, fullScreen ? 24 : 8)
                .padding(.vertical, fullScreen ? 24 : 8)
            }
        }
        .foregroundStyle(.white)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40)
                .fill(StudioPalette.fullscreenComposer)
                .ignoresSafeArea(.all, edges: .bottom)
                .opacity(fullScreen ? 1 : 0)
                .allowsHitTesting(false)
        }
        .glassEffect(fullScreen ? .identity : .regular.interactive(),
                     in: .rect(cornerRadius: expanded || !session.attachments.isEmpty ? 28 : 26))
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
                .padding(.top, fullScreen ? 52 : (session.attachments.isEmpty ? 48 : 184))
                .padding(.trailing, fullScreen ? 16 : 8)
            }
        }
        .padding(.horizontal, horizontalInset)
        .coordinateSpace(name: "composerGestures")
        .simultaneousGesture(DragGesture(minimumDistance: 12, coordinateSpace: .named("composerGestures")).onChanged { value in
            guard !pickerPresented, !changingFullscreen,
                  !editorGestureBounds.isNull,
                  !editorGestureBounds.insetBy(dx: -16, dy: -28).contains(value.startLocation),
                  abs(value.translation.height) > abs(value.translation.width) * 1.25 else { return }
            focused = value.translation.height < 0
        })
        .animation(.easeOut(duration: 0.25), value: focused)
        .overlay(alignment: .bottom) {
            if pickerPresented {
                PhotosPicker(selection: $pendingSelection, maxSelectionCount: max(1, session.attachmentSlots),
                             selectionBehavior: .continuousAndOrdered, matching: .images, preferredItemEncoding: .current) { EmptyView() }
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
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        .onChange(of: pickerPresented) {
            // However the gallery closes (back button, swipe, or a touch outside it), start fresh next time.
            guard !pickerPresented else { return }
            galleryDrag = 0
            pendingSelection = []
        }
        .photosPicker(isPresented: $fullPickerPresented, selection: $selection,
                      maxSelectionCount: max(1, session.attachmentSlots), selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .task(id: selection) {
            guard !selection.isEmpty else { return }
            loadingPhotos = true
            defer { loadingPhotos = false }
            for item in selection {
                guard !Task.isCancelled else { return }
                do {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let photo = PhotoAttachment(data: data), session.attachmentSlots > 0 {
                        session.attachments.append(photo)
                    } else { photoError = true }
                } catch { photoError = true }
            }
            selection = []
        }
        .sensoryFeedback(.error, trigger: photoError) { _, new in new }
        .alert("Photo couldn’t be opened", isPresented: $photoError) {
            Button("OK", role: .cancel) { }
        } message: { Text("Try another photo or download the original from iCloud first.") }
    }
}
