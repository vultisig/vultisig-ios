//
//  FontSystem.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

public protocol FontSystemProtocol {
    var heroDisplay: Font { get }
    var display: Font { get }

    var headline: Font { get }
    var largeTitle: Font { get }

    var title1: Font { get }
    var title2: Font { get }
    var title3: Font { get }
    var subtitle: Font { get }

    var bodyLMedium: Font { get }
    var bodyLRegular: Font { get }
    var bodyMMedium: Font { get }
    var bodyMRegular: Font { get }
    var bodySMedium: Font { get }
    var bodySRegular: Font { get }

    var caption12: Font { get }
    var caption10: Font { get }
    var footnote: Font { get }

    var buttonRegularSemibold: Font { get }
    var buttonRegularMedium: Font { get }
    var buttonSSemibold: Font { get }
    var buttonSMedium: Font { get }

    var priceLargeTitle: Font { get }
    var priceTitle1: Font { get }
    var priceTitle2: Font { get }
    var priceBodyS: Font { get }
    var priceBodyL: Font { get }
    var priceFootnote: Font { get }
    var priceCaption: Font { get }

    /// The passcode keypad, and the one place this scale leaves the brand faces
    /// on purpose.
    ///
    /// The control exists to read as *the system passcode keypad* — same
    /// numerals, same weight, same rounded face the platform uses — so that
    /// entering a passcode here feels like entering one anywhere else on the
    /// device. Brockman would be more consistent with the rest of the app and
    /// less consistent with the thing this is imitating.
    ///
    /// Named here rather than spelled at the call site so the deviation is a
    /// recorded decision in the design system instead of a magic number in a
    /// view.
    var keypadDigit: Font { get }
    /// The keypad's backspace glyph, smaller than a digit the way the platform's
    /// own keypad draws it.
    var keypadGlyph: Font { get }
}
