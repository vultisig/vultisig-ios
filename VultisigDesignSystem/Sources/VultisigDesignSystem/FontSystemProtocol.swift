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

    /// The passcode keypad deliberately uses the platform's rounded system
    /// face so it reads like a native keypad rather than branded content.
    var keypadDigit: Font { get }
    /// The keypad's backspace glyph is smaller than its digits.
    var keypadGlyph: Font { get }
    var lockKeypadDigit: Font { get }
    var lockKeypadLetters: Font { get }
}
