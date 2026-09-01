import SwiftUI
import VultisigUIResources

struct FontSystem: FontSystemProtocol {
    var heroDisplay: Font { VultisigFont.brockmannMedium.font(size: 72) }
    var display: Font { VultisigFont.brockmannMedium.font(size: 60) }

    var headline: Font { VultisigFont.brockmannMedium.font(size: 40) }
    var largeTitle: Font { VultisigFont.brockmannMedium.font(size: 34) }

    var title1: Font { VultisigFont.brockmannMedium.font(size: 28) }
    var title2: Font { VultisigFont.brockmannMedium.font(size: 22) }
    var title3: Font { VultisigFont.brockmannMedium.font(size: 17) }
    var subtitle: Font { VultisigFont.brockmannMedium.font(size: 15) }

    var bodyLMedium: Font { VultisigFont.brockmannMedium.font(size: 18) }
    var bodyLRegular: Font { VultisigFont.brockmannRegular.font(size: 18) }
    var bodyMMedium: Font { VultisigFont.brockmannMedium.font(size: 16) }
    var bodyMRegular: Font { VultisigFont.brockmannRegular.font(size: 16) }
    var bodySMedium: Font { VultisigFont.brockmannMedium.font(size: 14) }
    var bodySRegular: Font { VultisigFont.brockmannRegular.font(size: 14) }

    var caption12: Font { VultisigFont.brockmannMedium.font(size: 12) }
    var caption10: Font { VultisigFont.brockmannMedium.font(size: 10) }
    var footnote: Font { VultisigFont.brockmannMedium.font(size: 13) }

    var buttonRegularSemibold: Font { VultisigFont.brockmannSemibold.font(size: 16) }
    var buttonRegularMedium: Font { VultisigFont.brockmannMedium.font(size: 16) }
    var buttonSSemibold: Font { VultisigFont.brockmannSemibold.font(size: 14) }
    var buttonSMedium: Font { VultisigFont.brockmannMedium.font(size: 14) }

    var priceLargeTitle: Font { VultisigFont.satoshiMedium.font(size: 34) }
    var priceTitle1: Font { VultisigFont.satoshiMedium.font(size: 28) }
    var priceTitle2: Font { VultisigFont.satoshiMedium.font(size: 22) }
    var priceBodyS: Font { VultisigFont.satoshiMedium.font(size: 14) }
    var priceBodyL: Font { VultisigFont.satoshiMedium.font(size: 18) }
    var priceFootnote: Font { VultisigFont.satoshiMedium.font(size: 13) }
    var priceCaption: Font { VultisigFont.satoshiMedium.font(size: 12) }

    var keypadDigit: Font { .system(size: 32, weight: .regular, design: .rounded) }
    var keypadGlyph: Font { .system(size: 24, weight: .regular) }
    var lockKeypadDigit: Font { .system(size: 24, weight: .regular) }
    var lockKeypadLetters: Font { .system(size: 10, weight: .medium) }
}
