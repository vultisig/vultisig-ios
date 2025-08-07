//
//  DefaultFontSystem.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

struct FontSystem: FontSystemProtocol {
    var heroDisplay: Font { FontStyle.medium.size(72) }
    var display: Font { FontStyle.medium.size(60) }
    
    var headline: Font { FontStyle.medium.size(40) }
    var largeTitle: Font { FontStyle.medium.size(34) }
    
    var title1: Font { FontStyle.medium.size(28) }
    var title2: Font { FontStyle.medium.size(22) }
    var title3: Font { FontStyle.medium.size(17) }
    var subtitle: Font { FontStyle.medium.size(15) }
    
    var bodyLMedium: Font { FontStyle.medium.size(18) }
    var bodyLRegular: Font { FontStyle.regular.size(18) }
    var bodyMMedium: Font { FontStyle.medium.size(16) }
    var bodyMRegular: Font { FontStyle.regular.size(16) }
    var bodySMedium: Font { FontStyle.medium.size(14) }
    var bodySRegular: Font { FontStyle.regular.size(14) }
    
    var caption12: Font { FontStyle.medium.size(12) }
    var caption10: Font { FontStyle.medium.size(10) }
    var footnote: Font { FontStyle.medium.size(13) }
    
    var buttonRegularSemibold: Font { FontStyle.semibold.size(16) }
    var buttonRegularMedium: Font { FontStyle.medium.size(16) }
    var buttonSSemibold: Font { FontStyle.semibold.size(14) }
    var buttonSMedium: Font { FontStyle.medium.size(14) }
}
