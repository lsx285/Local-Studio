import SwiftUI
import UIKit

/// One persistent text input across compact and multiline layouts.
struct ComposerEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let expanded: Bool
    let overflowing: Bool

    func makeUIView(context: Context) -> ComposerNativeTextView {
        let view = ComposerNativeTextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 17)
        view.textColor = .white
        view.tintColor = UIColor(StudioPalette.accent)
        view.textContainer.lineFragmentPadding = 0
        view.contentInsetAdjustmentBehavior = .never
        view.alwaysBounceVertical = false
        view.bounces = false
        view.showsVerticalScrollIndicator = false
        view.keyboardDismissMode = .interactive
        view.accessibilityIdentifier = "composer"
        view.accessibilityLabel = "Ask Local Studio"
        for direction in [UISwipeGestureRecognizer.Direction.up, .down] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped(_:)))
            swipe.direction = direction
            swipe.cancelsTouchesInView = false
            swipe.delegate = context.coordinator
            view.addGestureRecognizer(swipe)
        }
        return view
    }

    func updateUIView(_ view: ComposerNativeTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            view.text = text
            view.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        view.textContainerInset = expanded ? .zero : UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        view.isScrollEnabled = overflowing
        if !overflowing { view.setContentOffset(.zero, animated: false) }
        view.setNeedsLayout()
        if focused && !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
        if !focused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerNativeTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let lineHeight = UIFont.systemFont(ofSize: 17).lineHeight
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = expanded ? min(lineHeight * 6, max(lineHeight * 2, measured)) : 32
        return CGSize(width: width, height: ceil(height))
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
        func textViewDidEndEditing(_ textView: UITextView) { if parent.focused { parent.focused = false } }

        @objc func swiped(_ gesture: UISwipeGestureRecognizer) {
            guard let view = gesture.view as? UITextView, view.selectedRange.length == 0 else { return }
            let show = gesture.direction == .up
            parent.focused = show
            if show { view.becomeFirstResponder() } else { view.resignFirstResponder() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

final class ComposerNativeTextView: UITextView {
    private let placeholder = UILabel()

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
        super.layoutSubviews()
        placeholder.isHidden = !(text ?? "").isEmpty
        placeholder.frame = CGRect(x: 0, y: textContainerInset.top,
                                   width: bounds.width, height: UIFont.systemFont(ofSize: 17).lineHeight)
        if !isScrollEnabled && contentOffset != .zero { setContentOffset(.zero, animated: false) }
    }
}
