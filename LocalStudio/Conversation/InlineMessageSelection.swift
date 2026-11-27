import SwiftUI
import UIKit

/// Native selection stays in the measured text rectangle inside its bubble.
struct InlineMessageSelection: UIViewRepresentable {
    let text: String
    let color: UIColor
    @Binding var active: Bool

    func makeUIView(context: Context) -> InlineSelectionTextView {
        let view = InlineSelectionTextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.contentInsetAdjustmentBehavior = .never
        view.tintColor = UIColor(red: 65 / 255, green: 166 / 255, blue: 247 / 255, alpha: 1)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        view.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 17), .foregroundColor: color, .paragraphStyle: paragraph
        ])
        return view
    }

    func updateUIView(_ view: InlineSelectionTextView, context: Context) {
        view.onSelectionEnd = { active = false }
    }
}

final class InlineSelectionTextView: UITextView {
    var onSelectionEnd: (() -> Void)?
    private var selectedInitially = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !selectedInitially else { return }
        selectedInitially = true
        // Let the context menu finish dismissing before UIKit draws its selection handles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.window != nil else { return }
            self.becomeFirstResponder()
            self.selectAll(nil)
            let menu = self.interactions.compactMap { $0 as? UIEditMenuInteraction }.first
            menu?.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil,
                sourcePoint: CGPoint(x: self.bounds.midX, y: self.bounds.maxY)))
        }
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in self?.onSelectionEnd?() }
        }
        return result
    }
}
