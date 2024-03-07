//
//  FontStyle.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import SwiftUI

extension Font {
    /// BODY
    // Light
    static let body15SystemLight = Font.system(size: 15, weight: .light)
    
    // Regular
    static let body12Menlo = Font.custom("Menlo", size: 12)
    static let body13Menlo = Font.custom("Menlo", size: 13)
    static let body15Menlo = Font.custom("Menlo", size: 15)
    static let body18Menlo = Font.custom("Menlo", size: 18)
    static let body20Menlo = Font.custom("Menlo", size: 20)
    
    static let body12Montserrat = Font.custom("Montserrat", size: 12)
    
    // Medium
    static let body13MontserratMedium = Font.custom("Montserrat", size: 13).weight(.medium)
    static let body18MontserratMedium = Font.custom("Montserrat", size: 18).weight(.medium)
    static let body24MontserratMedium = Font.custom("Montserrat", size: 24).weight(.medium)
    
    // Semi-bold
    static let body12MontserratSemiBold = Font.custom("Montserrat", size: 12).weight(.semibold)
    static let body20MontserratSemiBold = Font.custom("Montserrat", size: 20).weight(.semibold)
    
    // Bold
    static let body13MenloBold = Font.custom("Menlo", size: 13).bold()
    static let body15MenloBold = Font.custom("Menlo", size: 15).bold()
    static let body18MenloBold = Font.custom("Menlo", size: 18).bold()
    static let body20MenloBold = Font.custom("Menlo", size: 20).bold()
    
    static let body16MontserratBold = Font.custom("Montserrat", size: 16).bold()
    
    /// TITLE
    // Ultra-Light
    static let title30MenloUltraLight = Font.custom("Menlo", size: 30).weight(.ultraLight)
    
    // Light
    static let title40MontserratLight = Font.custom("Montserrat", size: 40).weight(.light)
    static let title80MontserratLight = Font.custom("Montserrat", size: 80).weight(.light)
    
    // Semi-bold
    static let title40MontserratSemiBold = Font.custom("Montserrat", size: 40).weight(.semibold)
    
    // Bold
    static let title30MenloBold = Font.custom("Menlo", size: 30).bold()
    static let title35MenloBold = Font.custom("Menlo", size: 35).bold()
    static let title40MenloBold = Font.custom("Menlo", size: 40).bold()
    
    // Black
    static let title30MenloBlack = Font.custom("Menlo", size: 30).weight(.black)
    static let title40MenloBlack = Font.custom("Menlo", size: 40).weight(.black)
    
    /// DYNAMIC
    static func dynamicMenlo(_ fontsize: CGFloat) -> Font {
        Font.custom("Menlo", size: fontsize)
    }
    
    static func dynamicAmericanTypewriter(_ fontsize: CGFloat) -> Font {
        Font.custom("AmericanTypewriter", size: fontsize)
    }
}
