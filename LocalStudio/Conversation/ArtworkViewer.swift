import SwiftUI
import UIKit
import ImageIO

struct ViewerPhoto: Identifiable {
    let photo: PhotoAttachment
    let date: Date
    let thumbnail: UIImage
    init(photo: PhotoAttachment, date: Date) {
        self.photo = photo; self.date = date
        if let source = CGImageSourceCreateWithData(photo.data as CFData, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 96
           ] as CFDictionary) {
            thumbnail = UIImage(cgImage: image)
        } else { thumbnail = photo.image }
    }
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
    @State private var info = false
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
        withAnimation(motion, completionCriteria: .removed) { expanded = false } completion: {
            dismiss(); after?()
        }
    }

    private func toggleInfo() { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { info.toggle() } }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let windowInsets = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
            let top = max(geometry.safeAreaInsets.top, windowInsets.top)
            let bottom = max(12, max(geometry.safeAreaInsets.bottom, windowInsets.bottom))
            let origin = geometry.frame(in: .global).origin
            let source = transitionSource?.offsetBy(dx: -origin.x, dy: -origin.y)
            let area = chrome
                ? CGRect(x: 0, y: info ? 0 : top + 54, width: size.width,
                         height: max(100, info ? size.height - bottom - 360 : size.height - top - bottom - 154))
                : CGRect(origin: .zero, size: size)
            let ratio = current.photo.image.size.width / max(1, current.photo.image.size.height)
            let width = max(1, min(area.width, area.height * ratio))
            let target = CGRect(x: area.midX - width / 2, y: area.midY - width / ratio / 2,
                                width: width, height: width / ratio)
            let frame = expanded ? target : (source ?? target)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(expanded ? 1 : 0).ignoresSafeArea()
                TabView(selection: $selected) {
                    ForEach(request.photos) { item in
                        ZoomArtwork(image: item.photo.image, area: area, reduceMotion: reduceMotion, zoomed: $zoomed) {
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
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                        if !zoomed && !info && abs(value.translation.height) > 90 && abs(value.translation.height) > abs(value.translation.width) * 1.5 { close() }
                    })
                    .opacity(ready ? 1 : 0)
                    .allowsHitTesting(ready && !closing)
                    .accessibilityHidden(!ready)
                // Keep a constant backing size: only its composited transform moves.
                // The native pager stays mounted, avoiding setup/teardown at the handoff.
                Image(uiImage: current.photo.image).resizable().scaledToFit()
                    .frame(width: target.width, height: target.height)
                    .clipShape(.rect(cornerRadius: expanded ? 0 : 16 / max(0.001, frame.width / target.width)))
                    .scaleEffect(x: frame.width / target.width, y: frame.height / target.height)
                    .position(x: frame.midX, y: frame.midY)
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
                            Button { UIPasteboard.general.image = current.photo.image } label: {
                                Label { Text("Copy") } icon: { StudioIcon(.copy) }
                            }
                            if !request.limited {
                                Button { let photo = current.photo; close { edit(photo) } } label: {
                                    Label { Text("Edit") } icon: { StudioIcon(.edit) }
                                }
                            }
                        } label: { StudioIcon(.moreHeader) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .tint(.white)
                    }
                    .padding(.horizontal, 20).padding(.top, top)
                    .opacity(expanded && !info ? 1 : 0)
                    .allowsHitTesting(!info)

                    if !request.limited {
                        RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.1))
                            .frame(height: 260)
                            .padding(.horizontal, 28)
                            .padding(.bottom, max(12, bottom - 6) + 62)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .offset(y: info ? 0 : 290)
                            .opacity(info && expanded ? 1 : 0)
                            .allowsHitTesting(info)
                    }
                    VStack(spacing: 14) {
                        GeometryReader { rail in
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal) {
                                    HStack(spacing: 3) {
                                        ForEach(request.photos) { item in
                                            Button { withAnimation(motion) { selected = item.id } } label: {
                                                Image(uiImage: item.thumbnail).resizable().scaledToFill()
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
                        .opacity(info ? 0 : 1)
                        .allowsHitTesting(!info)
                        HStack {
                            ShareLink(item: Image(uiImage: current.photo.image), preview: SharePreview("Artwork", image: Image(uiImage: current.photo.image))) {
                                StudioIcon(.viewerShare).frame(width: 48, height: 48)
                            }.glassEffect(.regular.interactive(), in: .circle)
                            Spacer()
                            if !request.limited {
                                HStack(spacing: 8) {
                                    Button { toggleInfo() } label: { StudioIcon(.viewerInfo).frame(width: 44, height: 48) }
                                        .accessibilityLabel("Info")
                                    Button { let photo = current.photo; close { edit(photo) } } label: {
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
            .foregroundStyle(.white).tint(.white)
            .onAppear {
                withAnimation(motion, completionCriteria: .removed) { expanded = true } completion: { if !closing { ready = true } }
            }
            .onChange(of: selected) { zoomed = false }
            .confirmationDialog("Delete image?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { let id = selected; close { remove(id) } }
            }
        }
        .ignoresSafeArea()
    }
}

private struct ZoomArtwork: UIViewRepresentable {
    let image: UIImage
    let area: CGRect
    let reduceMotion: Bool
    @Binding var zoomed: Bool
    let tap: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ArtworkScrollView {
        let view = ArtworkScrollView()
        view.delegate = context.coordinator
        view.minimumZoomScale = 1; view.maximumZoomScale = 6
        view.showsVerticalScrollIndicator = false; view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.addSubview(view.contentImage)
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2; view.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        single.require(toFail: double); view.addGestureRecognizer(single)
        return view
    }
    func updateUIView(_ view: ArtworkScrollView, context: Context) {
        context.coordinator.parent = self
        view.configure(image: image, area: area, animated: !reduceMotion)
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
        else { UIView.performWithoutAnimation(layout) }
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
