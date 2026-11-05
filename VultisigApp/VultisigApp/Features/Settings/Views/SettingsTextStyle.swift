//
//  SettingsTextStyle.swift
//  VultisigApp
//

import SwiftUI

/// The settings lists' type ramp: a theme font plus the tracking and line box
/// the design sets for it.
enum SettingsTextStyle {
    /// Main settings row title and trailing value.
    case bodyS
    /// Vault Settings row title.
    case footnote
    /// Advanced row title.
    case subtitle
    /// Section captions, row subtitles and tile labels.
    case caption
    /// Selection and toggle row titles.
    case bodyM
    /// Empty and update state titles.
    case buttonRegular
    /// Empty and update state subtitles.
    case buttonS
    /// Big left titles and warning titles on the vault sub-screens.
    case title2
    /// Low-emphasis sheet actions.
    case captionSmall
    /// Tier requirement and balance lines.
    case priceFootnote
    /// Switch state labels.
    case bodyMRegular

    var font: Font {
        switch self {
        case .bodyS: Theme.fonts.bodySMedium
        case .footnote: Theme.fonts.footnote
        case .subtitle: Theme.fonts.subtitle
        case .caption: Theme.fonts.caption12
        case .bodyM: Theme.fonts.bodyMMedium
        case .buttonRegular: Theme.fonts.buttonRegularMedium
        case .buttonS: Theme.fonts.buttonSMedium
        case .title2: Theme.fonts.title2
        case .captionSmall: Theme.fonts.caption10
        case .priceFootnote: Theme.fonts.priceFootnote
        case .bodyMRegular: Theme.fonts.bodyMRegular
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .bodyS: 14
        case .footnote: 13
        case .subtitle: 15
        case .caption: 12
        case .bodyM, .buttonRegular, .bodyMRegular: 16
        case .buttonS: 14
        case .title2: 22
        case .captionSmall: 10
        case .priceFootnote: 13
        }
    }

    var tracking: CGFloat {
        switch self {
        case .bodyS, .bodyM, .buttonRegular, .buttonS, .bodyMRegular: 0
        case .footnote: 0.06
        case .subtitle: -0.18
        case .caption, .captionSmall: 0.12
        case .title2: -0.36
        case .priceFootnote: 0.2
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .bodyS: 20
        case .footnote: 18
        case .subtitle: 17
        case .caption: 16
        case .bodyM, .title2, .bodyMRegular: 24
        case .buttonRegular: 20
        case .buttonS, .priceFootnote: 18
        case .captionSmall: 14
        }
    }

    /// Brockmann's ascent plus descent is 1.2 times its point size, Satoshi's 1.25.
    var unroundedLineHeight: CGFloat {
        pointSize * (self == .priceFootnote ? 1.25 : 1.2)
    }
}

extension View {
    /// Sets the style's font and tracking, and pads each line out to the
    /// design's line box so rows keep the design's height.
    func settingsText(_ style: SettingsTextStyle) -> some View {
        modifier(SettingsTextModifier(style: style))
    }
}

private struct SettingsTextModifier: ViewModifier {
    let style: SettingsTextStyle
    @Environment(\.displayScale) private var displayScale

    /// SwiftUI rounds a line up to a whole device pixel, so the padding has to
    /// be worked out from the rounded height or every row drifts by a fraction.
    private var naturalLineHeight: CGFloat {
        (style.unroundedLineHeight * displayScale).rounded(.up) / displayScale
    }

    func body(content: Content) -> some View {
        let extra = style.lineHeight - naturalLineHeight
        content
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(max(extra, 0))
            .padding(.vertical, extra / 2)
    }
}
