//
//  DefaultFontSystem.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

struct FontSystem: FontSystemProtocol {
    var heroDisplay: Font { FontStyle.brockmanMedium.size(72) }
    var display: Font { FontStyle.brockmanMedium.size(60) }

    var headline: Font { FontStyle.brockmanMedium.size(40) }
    var largeTitle: Font { FontStyle.brockmanMedium.size(34) }

    var title1: Font { FontStyle.brockmanMedium.size(28) }
    var title2: Font { FontStyle.brockmanMedium.size(22) }
    var title3: Font { FontStyle.brockmanMedium.size(17) }
    var subtitle: Font { FontStyle.brockmanMedium.size(15) }

    var bodyLMedium: Font { FontStyle.brockmanMedium.size(18) }
    var bodyLRegular: Font { FontStyle.brockmanRegular.size(18) }
    var bodyMMedium: Font { FontStyle.brockmanMedium.size(16) }
    var bodyMRegular: Font { FontStyle.brockmanRegular.size(16) }
    var bodySMedium: Font { FontStyle.brockmanMedium.size(14) }
    var bodySRegular: Font { FontStyle.brockmanRegular.size(14) }

    var caption12: Font { FontStyle.brockmanMedium.size(12) }
    var caption10: Font { FontStyle.brockmanMedium.size(10) }
    var footnote: Font { FontStyle.brockmanMedium.size(13) }

    var buttonRegularSemibold: Font { FontStyle.brockmanSemibold.size(16) }
    var buttonRegularMedium: Font { FontStyle.brockmanMedium.size(16) }
    var buttonSSemibold: Font { FontStyle.brockmanSemibold.size(14) }
    var buttonSMedium: Font { FontStyle.brockmanMedium.size(14) }

    var priceLargeTitle: Font { FontStyle.satoshiMedium.size(34) }
    var priceTitle1: Font { FontStyle.satoshiMedium.size(28) }
    var priceBodyS: Font { FontStyle.satoshiMedium.size(14) }
    var priceBodyL: Font { FontStyle.satoshiMedium.size(18) }
    var priceFootnote: Font { FontStyle.satoshiMedium.size(13) }
    var priceCaption: Font { FontStyle.satoshiMedium.size(12) }
}
