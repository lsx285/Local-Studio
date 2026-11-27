import SwiftUI
import UIKit

/// One persistent text input across compact and multiline layouts.
struct ComposerEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let expanded: Bool
    let overflowing: Bool
    let fullScreen: Bool
    let showsExpansionControl: Bool

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
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: ComposerNativeTextView, context: Context) {
        context.coordinator.parent = self
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
        view.typingAttributes = attributes
        view.textContainerInset = expanded ? .zero : UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        view.isScrollEnabled = overflowing || fullScreen
        if !view.isScrollEnabled { view.setContentOffset(.zero, animated: false) }
        view.reserveExpansionControl(showsExpansionControl && !fullScreen, width: view.bounds.width)
        view.setNeedsLayout()
        if focused && !view.isFirstResponder && view.window != nil { view.becomeFirstResponder() }
        if !focused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerNativeTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        if fullScreen { return CGSize(width: width, height: proposal.height ?? 240) }
        uiView.reserveExpansionControl(showsExpansionControl, width: width)
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = expanded ? min(168, max(48, measured)) : 32
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

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed,
                  let view = gesture.view as? UITextView, view.selectedRange.length == 0 else { return }
            let delta = gesture.translation(in: view)
            guard abs(delta.y) >= 12, abs(delta.y) > abs(delta.x) * 1.25 else { return }
            let show = delta.y < 0
            if parent.focused != show { parent.focused = show }
            if show { view.becomeFirstResponder() } else { view.resignFirstResponder() }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view as? UITextView, view.selectedRange.length == 0 else { return false }
            let velocity = pan.velocity(in: view)
            // Upward pans in an active long draft remain native text scrolling.
            return abs(velocity.y) > abs(velocity.x) * 1.25 && (!view.isFirstResponder || velocity.y > 0)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

final class ComposerNativeTextView: UITextView {
    private let placeholder = UILabel()
    private var exclusionWidth: CGFloat?

    func reserveExpansionControl(_ reserve: Bool, width: CGFloat) {
        let target: CGFloat? = reserve ? width : nil
        guard target != exclusionWidth else { return }
        exclusionWidth = target
        textContainer.exclusionPaths = reserve
            ? [UIBezierPath(rect: CGRect(x: max(0, width - 32), y: 0, width: 32, height: 24))] : []
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
        super.layoutSubviews()
        placeholder.isHidden = !(text ?? "").isEmpty
        placeholder.frame = CGRect(x: 0, y: textContainerInset.top + (24 - UIFont.systemFont(ofSize: 17).lineHeight) / 2,
                                   width: bounds.width, height: UIFont.systemFont(ofSize: 17).lineHeight)
        if !isScrollEnabled && contentOffset != .zero { setContentOffset(.zero, animated: false) }
    }
}
