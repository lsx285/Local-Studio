import SwiftUI
import UIKit

struct ViewerPhoto: Identifiable {
    let photo: PhotoAttachment
    let date: Date
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(request: ViewerRequest, sourceFrames: [UUID: CGRect], edit: @escaping (PhotoAttachment) -> Void,
         remove: @escaping (UUID) -> Void, dismiss: @escaping () -> Void) {
        self.request = request; self.sourceFrames = sourceFrames
        self.edit = edit; self.remove = remove; self.dismiss = dismiss
        _selected = State(initialValue: request.selectedID)
    }

    private var current: ViewerPhoto { request.photos.first { $0.id == selected } ?? request.photos[0] }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.9) }

    private func close(after: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true; ready = false
        withAnimation(motion, completionCriteria: .removed) { expanded = false } completion: {
            dismiss(); after?()
        }
    }

    private func toggleInfo() { withAnimation(motion) { info.toggle() } }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let windowInsets = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
            let top = max(geometry.safeAreaInsets.top, windowInsets.top)
            let bottom = max(12, max(geometry.safeAreaInsets.bottom, windowInsets.bottom))
            let origin = geometry.frame(in: .global).origin
            let source = sourceFrames[selected]?.offsetBy(dx: -origin.x, dy: -origin.y)
            let area = chrome
                ? CGRect(x: 0, y: info ? 0 : top + 54, width: size.width,
                         height: max(100, info ? size.height - bottom - 360 : size.height - top - bottom - 154))
                : CGRect(origin: .zero, size: size)
            let ratio = current.photo.image.size.width / max(1, current.photo.image.size.height)
            let width = min(area.width, area.height * ratio)
            let target = CGRect(x: area.midX - width / 2, y: area.midY - width / ratio / 2,
                                width: width, height: width / ratio)
            let frame = expanded ? target : (source ?? target)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(expanded ? 1 : 0).ignoresSafeArea()
                if ready {
                    TabView(selection: $selected) {
                        ForEach(request.photos) { item in
                            ZoomArtwork(image: item.photo.image, zoomed: $zoomed) {
                                withAnimation(motion) { chrome.toggle() }
                            }
                            .tag(item.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: area.width, height: area.height)
                    .position(x: area.midX, y: area.midY)
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                        if !zoomed && !info && abs(value.translation.height) > 90 && abs(value.translation.height) > abs(value.translation.width) * 1.5 { close() }
                    })
                } else {
                    Image(uiImage: current.photo.image).resizable().scaledToFit()
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(.rect(cornerRadius: expanded ? 0 : 16))
                        .position(x: frame.midX, y: frame.midY)
                        .opacity(expanded || source != nil ? 1 : 0)
                }
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

                    VStack(spacing: 14) {
                        if info && !request.limited {
                            RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.1))
                                .frame(height: 260)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal) {
                                    HStack(spacing: 3) {
                                        ForEach(request.photos) { item in
                                            Button { withAnimation(motion) { selected = item.id } } label: {
                                                Image(uiImage: item.photo.image).resizable().scaledToFill()
                                                    .frame(width: item.id == selected ? 30 : 20, height: 30)
                                                    .clipShape(.rect(cornerRadius: 3))
                                            }.id(item.id)
                                            .padding(.horizontal, item.id == selected ? 8 : 0)
                                        }
                                    }.padding(.horizontal, 28)
                                }
                                .scrollIndicators(.hidden).frame(height: 34)
                                .onAppear { proxy.scrollTo(selected, anchor: .center) }
                                .onChange(of: selected) { withAnimation(motion) { proxy.scrollTo(selected, anchor: .center) } }
                            }
                        }
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
    @Binding var zoomed: Bool
    let tap: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIScrollView {
        let view = ArtworkScrollView()
        view.delegate = context.coordinator
        view.minimumZoomScale = 1; view.maximumZoomScale = 6
        view.showsVerticalScrollIndicator = false; view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        let imageView = context.coordinator.imageView
        view.contentImage = imageView
        imageView.image = image; imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2; view.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        single.require(toFail: double); view.addGestureRecognizer(single)
        return view
    }
    func updateUIView(_ view: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if view.zoomScale == 1 {
            context.coordinator.imageView.frame = view.bounds
            view.contentSize = view.bounds.size
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1, height: proposal.height ?? 1)
    }
    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomArtwork
        let imageView = UIImageView()
        init(_ parent: ZoomArtwork) { self.parent = parent }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let value = scrollView.zoomScale > 1.01
            if parent.zoomed != value { parent.zoomed = value }
        }
        @objc func singleTap() { parent.tap() }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: true) }
            else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

private final class ArtworkScrollView: UIScrollView {
    var contentImage: UIImageView?
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1, contentImage?.bounds.size != bounds.size {
            contentImage?.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
}
