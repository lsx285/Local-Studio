import SwiftUI
import UIKit

struct ViewerPhoto: Identifiable {
    let photo: PhotoAttachment
    let date: Date
    var metadata: GenerationMetadata? = nil
    var id: UUID { photo.id }
}

struct ViewerRequest: Identifiable {
    let id = UUID()
    let photos: [ViewerPhoto]
    let selectedID: UUID
    let limited: Bool
}

struct ArtworkViewer: View {
    let request: ViewerRequest
    let sourceFrames: [UUID: CGRect]
    let edit: (PhotoAttachment) -> Void
    let remove: (UUID) -> Void
    let dismiss: () -> Void
    @State private var selected: UUID
    @State private var expanded = false
    @State private var ready = false
    @State private var closing = false
    @State private var infoProgress: CGFloat = 0
    @State private var infoImageHeight: CGFloat = 0
    @State private var infoScrollOffset: CGFloat = 0
    @State private var infoDragStart: CGFloat?
    @State private var infoGestureRejected = false
    @State private var chrome = true
    @State private var zoomed = false
    @State private var confirmDelete = false
    @State private var transitionSource: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(request: ViewerRequest, sourceFrames: [UUID: CGRect], edit: @escaping (PhotoAttachment) -> Void,
         remove: @escaping (UUID) -> Void, dismiss: @escaping () -> Void) {
        self.request = request; self.sourceFrames = sourceFrames
        self.edit = edit; self.remove = remove; self.dismiss = dismiss
        _selected = State(initialValue: request.selectedID)
        _transitionSource = State(initialValue: sourceFrames[request.selectedID])
    }

    private var current: ViewerPhoto { request.photos.first { $0.id == selected } ?? request.photos[0] }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.9) }

    private func close(after: (() -> Void)? = nil) {
        guard !closing else { return }
        transitionSource = sourceFrames[selected]
        closing = true; ready = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3), completionCriteria: .logicallyComplete) { expanded = false } completion: {
            dismiss(); after?()
        }
    }

    private var info: Bool { infoProgress > 0.5 }

    private func settleInfo(_ open: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { infoProgress = open ? 1 : 0 }
    }

    private func toggleInfo() {
        UISelectionFeedbackGenerator().selectionChanged()
        settleInfo(!info)
    }

    private var infoGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard ready, !closing, !zoomed, !request.limited, !infoGestureRejected else { return }
                if infoDragStart == nil {
                    if infoProgress > 0.99 && (infoScrollOffset > 1 || value.startLocation.y > infoImageHeight + 70
                        || (value.startLocation.y >= infoImageHeight && value.translation.height < 0)) {
                        infoGestureRejected = true
                        return
                    }
                    guard abs(value.translation.height) > abs(value.translation.width) * 1.25 else {
                        infoGestureRejected = true
                        return
                    }
                    infoDragStart = infoProgress
                    chrome = true
                }
                guard let start = infoDragStart else { return }
                // Direct manipulation: no easing or queued animation while the finger moves.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    infoProgress = min(1, max(0, start - value.translation.height / 290))
                }
            }
            .onEnded { value in
                let start = infoDragStart
                let rejected = infoGestureRejected
                infoDragStart = nil
                infoGestureRejected = false
                guard !zoomed, !closing, !rejected else { return }
                if let start, start > 0 || value.translation.height < 0 {
                    let projected = start - value.predictedEndTranslation.height / 290
                    if (projected > 0.5) != (start > 0.5) { UISelectionFeedbackGenerator().selectionChanged() }
                    settleInfo(projected > 0.5)
                } else if value.translation.height > 90 && abs(value.translation.height) > abs(value.translation.width) * 1.5 {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    close()
                }
            }
    }

    var body: some View {
        GeometryReader { geometry in
            let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)
            let size = window?.bounds.size ?? geometry.size
            let windowInsets = window?.safeAreaInsets ?? .zero
            let top = max(geometry.safeAreaInsets.top, windowInsets.top)
            let bottom = max(12, max(geometry.safeAreaInsets.bottom, windowInsets.bottom))
            let origin = geometry.frame(in: .global).origin
            let source = transitionSource
            let ratio = current.photo.image.size.width / max(1, current.photo.image.size.height)
            let imageHeight = min(size.height * 0.52, size.width / ratio)
            let area = chrome
                ? CGRect(x: 0, y: (top + 54) * (1 - infoProgress), width: size.width,
                         height: max(100, (size.height - top - bottom - 154) * (1 - infoProgress)
                                     + imageHeight * infoProgress))
                : CGRect(origin: .zero, size: size)
            let width = max(1, min(area.width, area.height * ratio))
            let target = CGRect(x: area.midX - width / 2, y: area.midY - width / ratio / 2,
                                width: width, height: width / ratio)
            let frame = expanded ? target : (source ?? target)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(expanded ? 1 : 0).ignoresSafeArea()
                TabView(selection: $selected) {
                    ForEach(request.photos) { item in
                        ZoomArtwork(image: item.photo.image, area: area, reduceMotion: reduceMotion, interactiveLayout: infoDragStart != nil, zoomed: $zoomed) {
                            withAnimation(motion) { chrome.toggle() }
                        }
                        .ignoresSafeArea(.container, edges: .all)
                        .tag(item.id)
                    }
                }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea(.container, edges: .all)
                    .frame(width: size.width, height: size.height)
                    .position(x: size.width / 2, y: size.height / 2)
                    .opacity(ready ? 1 : 0)
                    .allowsHitTesting(ready && !closing)
                    .accessibilityHidden(!ready)
                ArtworkTransition(image: current.photo.image, baseSize: target.size,
                                  sourceSize: source?.size ?? target.size,
                                  sourceCorner: request.limited ? 20 : 16, frame: frame)
                    .opacity(ready ? 0 : (expanded || source != nil ? 1 : 0))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if chrome {
                    HStack {
                        Button { close() } label: { StudioIcon(.back) }
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel("Close viewer")
                        Spacer()
                        Button { if !request.limited { toggleInfo() } } label: {
                            VStack(spacing: 0) {
                                Text(Calendar.current.isDateInToday(current.date) ? "Today" : current.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 15, weight: .semibold))
                                Text(current.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 11, weight: .medium))
                            }.frame(width: 160, height: 44)
                        }.glassEffect(.regular.interactive(), in: .capsule)
                        Spacer()
                        Menu {
                            Button {
                                UIPasteboard.general.image = current.photo.image
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label { Text("Copy") } icon: { StudioIcon(.copy) }
                            }
                            if !request.limited {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    let photo = current.photo; close { edit(photo) }
                                } label: {
                                    Label { Text("Edit") } icon: { StudioIcon(.edit) }
                                }
                            }
                        } label: { StudioIcon(.moreHeader) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .tint(.white)
                    }
                    .padding(.horizontal, 20).padding(.top, top)
                    .opacity(expanded ? 1 - infoProgress : 0)
                    .allowsHitTesting(infoProgress < 0.01)

                    if !request.limited {
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: imageHeight).allowsHitTesting(false)
                                ArtworkInfoView(photo: current)
                                    .padding(.horizontal, 20).padding(.top, 20)
                                    .padding(.bottom, bottom + 90)
                                    .frame(maxWidth: .infinity)
                                    .background(.black)
                            }
                        }
                        .id(selected)
                        .scrollIndicators(.hidden)
                        .scrollDisabled(infoProgress < 0.99)
                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, value in
                            infoScrollOffset = value
                        }
                        .frame(width: size.width, height: size.height)
                        .offset(y: 290 * (1 - infoProgress))
                        .opacity(expanded ? infoProgress : 0)
                        .allowsHitTesting(infoProgress > 0.99)
                    }
                    VStack(spacing: 14) {
                        GeometryReader { rail in
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal) {
                                    HStack(spacing: 3) {
                                        ForEach(request.photos) { item in
                                            Button { withAnimation(motion) { selected = item.id } } label: {
                                                Image(uiImage: item.photo.image).resizable().scaledToFill()
                                                    .frame(width: item.id == selected ? 30 : 20, height: 30)
                                                    .clipShape(.rect(cornerRadius: 3))
                                            }
                                            .padding(.horizontal, item.id == selected ? 12 : 0)
                                            .id(item.id)
                                        }
                                    }
                                    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selected)
                                }
                                .contentMargins(.horizontal, max(0, (rail.size.width - 54) / 2), for: .scrollContent)
                                .scrollIndicators(.hidden)
                                .onAppear { proxy.scrollTo(selected, anchor: .center) }
                                .onChange(of: selected) {
                                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                                        proxy.scrollTo(selected, anchor: .center)
                                    }
                                }
                            }
                        }
                        .frame(height: 34)
                        .padding(.horizontal, -28)
                        .opacity(1 - infoProgress)
                        .allowsHitTesting(infoProgress < 0.01)
                        HStack {
                            ShareLink(item: Image(uiImage: current.photo.image), preview: SharePreview("Artwork", image: Image(uiImage: current.photo.image))) {
                                StudioIcon(.viewerShare).frame(width: 48, height: 48)
                            }.glassEffect(.regular.interactive(), in: .circle)
                            Spacer()
                            if !request.limited {
                                HStack(spacing: 8) {
                                    Button { toggleInfo() } label: {
                                        Group {
                                            if info { Image(systemName: "info.circle.fill").font(.system(size: StudioGlyph.viewerInfo.size)) }
                                            else { StudioIcon(.viewerInfo) }
                                        }
                                        .frame(width: 44, height: 48)
                                    }
                                        .accessibilityLabel("Info")
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        let photo = current.photo; close { edit(photo) }
                                    } label: {
                                        StudioIcon(.viewerEdit).frame(width: 44, height: 48)
                                    }.accessibilityLabel("Edit in chat")
                                }.padding(.horizontal, 12).glassEffect(.regular.interactive(), in: .capsule)
                                Spacer()
                            }
                            Button { confirmDelete = true } label: {
                                StudioIcon(.viewerTrash).frame(width: 48, height: 48)
                            }.glassEffect(.regular.interactive(), in: .circle)
                                .accessibilityLabel("Delete image")
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, max(12, bottom - 6))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(expanded ? 1 : 0)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .offset(x: -origin.x, y: -origin.y)
            .onChange(of: imageHeight, initial: true) { infoImageHeight = imageHeight }
            .simultaneousGesture(infoGesture)
            .foregroundStyle(.white).tint(.white)
            .onAppear {
                withAnimation(motion, completionCriteria: .logicallyComplete) { expanded = true } completion: { if !closing { ready = true } }
            }
            .onChange(of: selected) { zoomed = false; infoScrollOffset = 0 }
            .sensoryFeedback(.selection, trigger: selected)
            .sensoryFeedback(.warning, trigger: confirmDelete) { _, new in new }
            .confirmationDialog("Delete image?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    let id = selected; close { remove(id) }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// One image plane and one crop window. Uniform image scaling preserves its
// proportions while the window morphs from the rail crop into the viewer.
private struct ArtworkTransition: View, @MainActor Animatable {
    let image: UIImage
    let baseSize: CGSize
    let sourceSize: CGSize
    let sourceCorner: CGFloat
    var frame: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(frame.midX, frame.midY), AnimatablePair(frame.width, frame.height)) }
        set {
            frame = CGRect(x: newValue.first.first - newValue.second.first / 2,
                           y: newValue.first.second - newValue.second.second / 2,
                           width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        let sx = max(0.001, frame.width / max(1, baseSize.width))
        let sy = max(0.001, frame.height / max(1, baseSize.height))
        let cover = max(sx, sy)
        let sourceScale = min(sourceSize.width / max(1, baseSize.width), sourceSize.height / max(1, baseSize.height))
        let radius = sourceCorner * min(1, max(0, (1 - min(sx, sy)) / max(0.001, 1 - sourceScale)))
        Image(uiImage: image).resizable().scaledToFit()
            .frame(width: baseSize.width, height: baseSize.height)
            .scaleEffect(x: cover / sx, y: cover / sy)
            .clipShape(RoundedRectangle(cornerSize: CGSize(width: radius / sx, height: radius / sy)))
            .scaleEffect(x: sx, y: sy)
            .position(x: frame.midX, y: frame.midY)
    }
}

private struct ZoomArtwork: UIViewRepresentable {
    let image: UIImage
    let area: CGRect
    let reduceMotion: Bool
    let interactiveLayout: Bool
    @Binding var zoomed: Bool
    let tap: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ArtworkScrollView {
        let view = ArtworkScrollView()
        view.delegate = context.coordinator
        view.minimumZoomScale = 1; view.maximumZoomScale = 6
        view.showsVerticalScrollIndicator = false; view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.bounces = false
        view.addSubview(view.contentImage)
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2; view.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        single.require(toFail: double); view.addGestureRecognizer(single)
        return view
    }
    func updateUIView(_ view: ArtworkScrollView, context: Context) {
        context.coordinator.parent = self
        view.configure(image: image, area: area, animated: !reduceMotion && !interactiveLayout)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ArtworkScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1, height: proposal.height ?? 1)
    }
    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomArtwork
        init(_ parent: ZoomArtwork) { self.parent = parent }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ArtworkScrollView)?.contentImage }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ArtworkScrollView)?.centerZoomedImage()
            let value = scrollView.zoomScale > 1.01
            if parent.zoomed != value { parent.zoomed = value }
        }
        @objc func singleTap() { parent.tap() }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? ArtworkScrollView else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: true) }
            else {
                let point = gesture.location(in: scroll.contentImage)
                let size = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

private final class ArtworkScrollView: UIScrollView {
    let contentImage = UIImageView()
    private var fitArea = CGRect.zero
    private var laidOutSize = CGSize.zero
    private var configuring = false
    private var pendingFit = false

    func configure(image: UIImage, area: CGRect, animated: Bool) {
        let changedImage = contentImage.image !== image
        guard changedImage || fitArea != area else { return }
        let animate = animated && window != nil && contentImage.image != nil && laidOutSize != .zero
        contentImage.image = image
        contentImage.contentMode = .scaleAspectFit
        fitArea = area
        if !changedImage && zoomScale > 1.01 {
            pendingFit = true
            return
        }
        applyFit(animated: animate)
    }

    private func applyFit(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0, let image = contentImage.image else { return }
        configuring = true
        setZoomScale(1, animated: false)
        let ratio = image.size.width / max(1, image.size.height)
        let width = min(fitArea.width, fitArea.height * ratio)
        let height = width / ratio
        let insets = UIEdgeInsets(top: max(0, fitArea.midY - height / 2), left: max(0, fitArea.midX - width / 2),
                                  bottom: max(0, bounds.height - fitArea.midY - height / 2), right: max(0, bounds.width - fitArea.midX - width / 2))
        let layout = {
            self.contentImage.frame = CGRect(x: 0, y: 0, width: width, height: height)
            self.contentSize = CGSize(width: width, height: height)
            self.contentInset = insets
            self.contentOffset = CGPoint(x: -insets.left, y: -insets.top)
        }
        if animated { UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: layout) }
        else {
            contentImage.layer.removeAllAnimations()
            layer.removeAllAnimations()
            UIView.performWithoutAnimation(layout)
        }
        configuring = false
    }

    func centerZoomedImage() {
        guard !configuring else { return }
        if zoomScale <= 1.001 {
            if pendingFit {
                pendingFit = false
                applyFit(animated: false)
                return
            }
            // Restore the gallery fit area without resizing the full-screen viewport.
            let image = contentImage.frame
            contentInset = UIEdgeInsets(top: max(0, fitArea.midY - image.height / 2), left: max(0, fitArea.midX - image.width / 2),
                                        bottom: max(0, bounds.height - fitArea.midY - image.height / 2), right: max(0, bounds.width - fitArea.midX - image.width / 2))
        } else {
            let x = max(0, (bounds.width - contentImage.frame.width) / 2)
            let y = max(0, (bounds.height - contentImage.frame.height) / 2)
            contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        applyFit(animated: false)
    }
}
