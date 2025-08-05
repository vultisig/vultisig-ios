//
//  ColorStyle.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import SwiftUI

extension Color {
    static let gray500 = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let gray400 = Color(red: 0.92, green: 0.92, blue: 0.93)
    
    static let neutral100 = Color(hex: "F3F4F5")
    
    static let blue800 = Color(hex: "02122B")
    
    static let persianBlue200 = Color(hex: "4879FD")
    static let persianBlue400 = Color(hex: "2155DF")
    
    static let turquoise400 = Color(hex: "81F8DE")
    static let turquoise600 = Color(hex: "33E6BF")
    static let turquoise800 = Color(hex: "0FBF93")
    
    static let mediumPurple = Color(hex: "9563FF")
    
    static let destructive = Color(hex: "E45944")
    
    static let loadingBlue = Color(hex: "1DA7FA")
    static let loadingGreen = Color(hex: "24D7A6")
    
    static let alertRed = Color(hex: "FF4040")
    static let alertYellow = Color(hex: "FFC25C")
    static let alertYellowBackground = Color(hex: "362B17")
    static let alertTurquoise = Color(hex: "13C89D")
    static let warningYellow = Color(hex: "F7961B")
    
    static let logoBlue = Color(hex: "0D86BB")
    static let invalidRed = Color(hex: "FF5C5C")
    static let checkboxBlue = Color(hex: "042436")
    
    static let miamiMarmalade = Color(hex: "F7961B")
    static let infoBlue = Color(hex: "5CA7FF")
    
    static let reshareCellGreen = Color(hex: "15D7AC")
    static let reshareCellRed = Color(hex: "DA2E2E")
    
    static let extraLightGray = Color(hex: "8295AE")
    static let textDisabled = Color(hex: "4D5F75")
    static let buttonDisabled = Color(hex: "0F1E36")
    static let lightText = Color(hex: "C9D6E8")
    static let borderBlue = Color(hex: "1B3F73")
    static let disabledText = Color(hex: "718096")
    static let iconLightBlue = Color(hex: "467FF8")
    static let disabledButtonBackground = Color(hex: "0B1A3A")
    
    // Background
    static let backgroundBlue = Color(hex: "02122B")
}

extension LinearGradient {
    static let primaryGradient = LinearGradient(colors: [Color(hex: "33E6BF"), Color(hex: "0439C7")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let primaryGradientLinear = LinearGradient(colors: [Color(hex: "33E6BF"), Color(hex: "0439C7")], startPoint: .top, endPoint: .bottom)
    static let primaryGradientHorizontal = LinearGradient(colors: [Color(hex: "33E6BF"), Color(hex: "0439C7")], startPoint: .leading, endPoint: .trailing)
    static let progressGradient = LinearGradient(colors: [Color(hex: "0439C7"), Color(hex: "33E6BF")], startPoint: .leading, endPoint: .trailing)
    static let cancelRed = LinearGradient(colors: [Color.red], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let solidBlue = LinearGradient(colors: [Color.persianBlue400], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let solidWhite = LinearGradient(colors: [Theme.colors.textPrimary], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let solidGray = LinearGradient(colors: [Color.lightText], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let borderGreen = LinearGradient(colors: [Color(hex: "0FBF93"), Color(hex: "0FBF93").opacity(0)], startPoint: .top, endPoint: .bottom)
}

extension AngularGradient {
    static let progressGradient = AngularGradient(
        gradient: Gradient(colors: [Color(hex: "0439C7"), Color(hex: "33E6BF")]),
        center: .center,
        startAngle: .degrees(360),
        endAngle: .degrees(-5)
    )
}
