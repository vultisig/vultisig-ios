//
//  KeysignReviewTextStyle.swift
//  VultisigApp
//

import SwiftUI

/// The review sheet's type ramp: a theme font plus the tracking and line box
/// the design sets for it.
enum KeysignReviewTextStyle {
    case title2
    case title3
    case bodyS
    case footnote
    case caption
    case captionSmall

    var font: Font {
        switch self {
        case .title2: Theme.fonts.title2
        case .title3: Theme.fonts.title3
        case .bodyS: Theme.fonts.bodySMedium
        case .footnote: Theme.fonts.footnote
        case .caption: Theme.fonts.caption12
        case .captionSmall: Theme.fonts.caption10
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .title2: 22
        case .title3: 17
        case .bodyS: 14
        case .footnote: 13
        case .caption: 12
        case .captionSmall: 10
        }
    }

    var tracking: CGFloat {
        switch self {
        case .title2: -0.36
        case .title3: -0.3
        case .bodyS: 0
        case .footnote: 0.06
        case .caption, .captionSmall: 0.12
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .title2: 24
        case .title3, .bodyS: 20
        case .footnote: 18
        case .caption: 16
        case .captionSmall: 14
        }
    }

    /// Brockmann's ascent plus descent is 1.2 times its point size, which is
    /// the height SwiftUI gives a line before any spacing.
    var naturalLineHeight: CGFloat {
        pointSize * 1.2
    }
}

extension View {
    /// Sets the style's font and tracking, and pads each line out to the
    /// design's line box so rows keep the design's height. A box shorter than
    /// the font's own line only tightens a single line: SwiftUI ignores
    /// negative line spacing.
    func keysignReviewText(_ style: KeysignReviewTextStyle) -> some View {
        let extra = style.lineHeight - style.naturalLineHeight
        return font(style.font)
            .tracking(style.tracking)
            .lineSpacing(max(extra, 0))
            .padding(.vertical, extra / 2)
    }
}
