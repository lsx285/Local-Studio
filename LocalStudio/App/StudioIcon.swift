import SwiftUI

/// Explicit reference-sized artwork; never substitutes an SF Symbol.
enum StudioGlyph: String {
    case plus, newChat, moreHeader, temporary, temporaryChecked
    case copy, edit, selectText, share, save, close
    case copyAction, speaker, shareAction, moreAction
    case upArrow, downArrow, expand, collapse, back, stop

    var size: CGFloat {
        switch self {
        case .newChat, .moreHeader, .temporary, .temporaryChecked, .back: 44
        case .plus, .upArrow, .expand, .collapse, .stop: 32
        case .downArrow: 36
        case .copyAction, .speaker, .shareAction, .moreAction: 18
        case .close: 22
        default: 24
        }
    }
}

struct StudioIcon: View {
    let glyph: StudioGlyph
    var size: CGFloat? = nil

    init(_ glyph: StudioGlyph, size: CGFloat? = nil) {
        self.glyph = glyph
        self.size = size
    }

    var body: some View {
        Image("Icon-\(glyph.rawValue)")
            .renderingMode(.template)
            .resizable()
            .frame(width: size ?? glyph.size, height: size ?? glyph.size)
            .accessibilityHidden(true)
    }
}
