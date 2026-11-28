import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One persistent text input across compact and multiline layouts.
struct ComposerEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let expanded: Bool
    let overflowing: Bool
    let fullScreen: Bool
    let transitioning: Bool
    let showsExpansionControl: Bool
    let pasteImageLimit: Int
    let pasteImages: ([Data]) -> Void

    func makeUIView(context: Context) -> ComposerNativeTextView {
        let view = ComposerNativeTextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.receiveImages = pasteImages
        view.pasteImageLimit = pasteImageLimit
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 17)
        view.textColor = .white
        view.tintColor = UIColor(StudioPalette.accent)
        view.textContainer.lineFragmentPadding = 0
        view.contentInsetAdjustmentBehavior = .never
        view.alwaysBounceVertical = false
        view.bounces = false
        view.showsVerticalScrollIndicator = false
        // Selection-handle autoscrolling must not interactively dismiss the keyboard.
        // The explicit selection-aware pan handles intentional dismissal instead.
        view.keyboardDismissMode = .none

        view.accessibilityLabel = "Ask Local Studio"
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: ComposerNativeTextView, context: Context) {
        context.coordinator.parent = self
        view.receiveImages = pasteImages
        view.pasteImageLimit = pasteImageLimit
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.white, .paragraphStyle: paragraph
        ]
        if view.text != text {
            view.attributedText = NSAttributedString(string: text, attributes: attributes)
            view.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        let existingParagraph = view.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        if existingParagraph?.minimumLineHeight != 24 || existingParagraph?.maximumLineHeight != 24 {
            view.typingAttributes = attributes
        }
        let inset = expanded ? UIEdgeInsets.zero : UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        if view.textContainerInset != inset { view.textContainerInset = inset }
        let scrolling = overflowing || fullScreen
        if view.isScrollEnabled != scrolling { view.isScrollEnabled = scrolling }
        if !view.isScrollEnabled && view.contentOffset != .zero { view.setContentOffset(.zero, animated: false) }
        view.reserveExpansionControl(showsExpansionControl && !fullScreen)
        if view.placeholderNeedsUpdate { view.setNeedsLayout() }
        if focused && !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
        if !transitioning && !focused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerNativeTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: max(1, proposal.height ?? 32))
    }

    // A separate TextKit layout measures the target before the live editor animates.
    @MainActor static func measuredHeight(text: String, width: CGFloat, reserve: Bool) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        let storage = NSTextStorage(string: text + "\u{200B}", attributes: [
            .font: UIFont.systemFont(ofSize: 17), .paragraphStyle: paragraph
        ])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: 168))
        container.maximumNumberOfLines = 7
        container.lineFragmentPadding = 0
        if reserve {
            container.exclusionPaths = [UIBezierPath(rect: CGRect(x: max(0, width - 32), y: 0, width: 32, height: 24))]
        }
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return min(168, max(48, ceil(layout.usedRect(for: container).height)))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ComposerEditor
        init(_ parent: ComposerEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            let value = textView.text ?? ""
            if parent.text != value { parent.text = value }
        }
        func textViewDidBeginEditing(_ textView: UITextView) { if !parent.focused { parent.focused = true } }
        func textViewDidEndEditing(_ textView: UITextView) {
            if !parent.transitioning && parent.focused { parent.focused = false }
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            guard !parent.transitioning, gesture.state == .changed,
                  let view = gesture.view as? UITextView, view.selectedRange.length == 0 else { return }
            let delta = gesture.translation(in: view)
            guard abs(delta.y) >= 12, abs(delta.y) > abs(delta.x) * 1.25 else { return }
            let show = delta.y < 0
            if parent.focused != show { parent.focused = show }
            if show { view.becomeFirstResponder() } else { view.resignFirstResponder() }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard !parent.transitioning, let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view as? UITextView, view.selectedRange.length == 0 else { return false }
            let velocity = pan.velocity(in: view)
            // Upward pans in an active long draft remain native text scrolling.
            return abs(velocity.y) > abs(velocity.x) * 1.25 && (!view.isFirstResponder || velocity.y > 0)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // A caret/selection long press owns its following drag, even before
            // UIKit changes selectedRange into a nonempty selection.
            otherGestureRecognizer is UILongPressGestureRecognizer
        }
    }
}

final class ComposerNativeTextView: UITextView {
    var receiveImages: (([Data]) -> Void)?
    var pasteImageLimit = 0
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let nativeAllowed = super.canPerformAction(action, withSender: sender)
        let imagePaste = action == #selector(paste(_:)) && pasteImageLimit > 0 && receiveImages != nil && UIPasteboard.general.hasImages
        let allowed = nativeAllowed || imagePaste
        return allowed
    }

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if board.hasImages {
            guard pasteImageLimit > 0, let receiveImages else {
                return
            }
            // Prefer the clipboard's original encoded representation; only encode
            // when another app supplies a UIImage without original file data.
            let originals: [Data] = board.items.prefix(pasteImageLimit).compactMap { item in
                for (type, value) in item where UTType(type)?.conforms(to: .image) == true {
                    if let data = value as? Data { return data }
                }
                if let image = item.values.compactMap({ $0 as? UIImage }).first { return image.pngData() }
                return nil
            }
            let data: [Data]
            if !originals.isEmpty { data = originals }
            else {
                let images = board.images ?? board.image.map { [$0] } ?? []
                data = images.prefix(pasteImageLimit).compactMap { $0.pngData() }
            }
            if !data.isEmpty { receiveImages(data) }
            return
        }
        super.paste(sender)
    }

    private let placeholder = UILabel()
    private var exclusionWidth: CGFloat?
    private var reservesExpansionControl = false
    var placeholderNeedsUpdate: Bool { placeholder.isHidden != !(text ?? "").isEmpty }

    func reserveExpansionControl(_ reserve: Bool) {
        guard reservesExpansionControl != reserve else { return }
        reservesExpansionControl = reserve
        setNeedsLayout()
    }

    private func updateExclusionPath() {
        let target: CGFloat? = reservesExpansionControl ? bounds.width : nil
        guard target != exclusionWidth else { return }
        exclusionWidth = target
        textContainer.exclusionPaths = reservesExpansionControl
            ? [UIBezierPath(rect: CGRect(x: max(0, bounds.width - 32), y: 0, width: 32, height: 24))] : []
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholder.text = "Ask Local Studio"
        placeholder.font = .systemFont(ofSize: 17)
        placeholder.textColor = UIColor(white: 0.5, alpha: 1)
        placeholder.isUserInteractionEnabled = false
        placeholder.isAccessibilityElement = false
        addSubview(placeholder)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        updateExclusionPath()
        super.layoutSubviews()
        placeholder.isHidden = !(text ?? "").isEmpty
        placeholder.frame = CGRect(x: 0, y: textContainerInset.top + (24 - UIFont.systemFont(ofSize: 17).lineHeight) / 2,
                                   width: bounds.width, height: UIFont.systemFont(ofSize: 17).lineHeight)
        if !isScrollEnabled && contentOffset != .zero { setContentOffset(.zero, animated: false) }
    }
}
