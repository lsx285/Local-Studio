import SwiftUI

/// Explicit reference-sized artwork; never substitutes an SF Symbol.
enum StudioGlyph: String {
    case plus, newChat, moreHeader, temporary, temporaryChecked
    case copy, edit, selectText, share, save, close
    case copyAction, speaker, shareAction, moreAction
    case upArrow, downArrow, expand, collapse, back, stop
    case retry, settings

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

    init(_ glyph: StudioGlyph) {
        self.glyph = glyph
    }

    var body: some View {
        Image("Icon-\(glyph.rawValue)")
            .renderingMode(glyph == .retry || glyph == .settings ? .original : .template)
            .resizable()
            .frame(width: glyph.size, height: glyph.size)
            .accessibilityHidden(true)
    }
}
