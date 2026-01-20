//
//  ColorSystem.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

public protocol ColorSystemProtocol {
    var bgButtonPrimary: Color { get }
    var bgButtonSecondary: Color { get }
    var bgButtonTertiary: Color { get }
    
    // Hover on Figma
    var bgButtonPrimaryPressed: Color { get }
    var bgButtonSecondaryPressed: Color { get }
    var bgButtonTertiaryPressed: Color { get }
    
    var bgButtonDisabled: Color { get }
    
    var textButtonDark: Color { get }
    var textButtonLight: Color { get }
    var textButtonDisabled: Color { get }
    
    var bgPrimary: Color { get }
    var bgSurface1: Color { get }
    var bgSurface2: Color { get }

    var bgSuccess: Color { get }
    var bgAlert: Color { get }
    var bgError: Color { get }
    var bgNeutral: Color { get }
    
    var primaryAccent1: Color { get }
    var primaryAccent2: Color { get }
    var primaryAccent3: Color { get }
    var primaryAccent4: Color { get }
    
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }
    var textDark: Color { get }
    
    var border: Color { get }
    var borderLight: Color { get }
    var borderExtraLight: Color { get }
    
    var alertSuccess: Color { get }
    var alertError: Color { get }
    var alertWarning: Color { get }
    var alertInfo: Color { get }
    
    var turquoise: Color { get }
}
