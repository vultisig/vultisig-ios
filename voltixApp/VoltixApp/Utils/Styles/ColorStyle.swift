//
//  ColorStyle.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import SwiftUI

extension Color {
    // Font
    static let systemFill = Color(UIColor.systemFill)
    static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let systemBackground = Color(UIColor.systemBackground)
    
    static let gray500 = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let gray400 = Color(red: 0.92, green: 0.92, blue: 0.93)
    
    static let neutral0 = Color(hex: "FFFFFF")
    static let neutral100 = Color(hex: "F3F4F5")
    static let neutral200 = Color(hex: "EBECED")
    static let neutral300 = Color(hex: "BDBDBD")
    
    static let blue200 = Color(hex: "1B3F73")
    static let blue400 = Color(hex: "11284A")
    static let blue600 = Color(hex: "061B3A")
    static let blue800 = Color(hex: "02122B")
    
    static let persianBlue200 = Color(hex: "4879FD")
    static let persianBlue400 = Color(hex: "2155DF")
    
    static let turquoise600 = Color(hex: "33E6BF")
    
    static let mediumPurple = Color(hex: "9563FF")
    
    static let destructive = Color(hex: "E45944")
    
    static let loadingBlue = Color(hex: "1DA7FA")
    static let loadingGreen = Color(hex: "24D7A6")
    
    // Background
    static let backgroundBlue = Color(hex: "02122B")
}

extension LinearGradient {
    static let primaryGradient = LinearGradient(colors: [Color(hex: "33E6BF"), Color(hex: "0439C7")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let progressGradient = LinearGradient(colors: [Color(hex: "0439C7"), Color(hex: "33E6BF")], startPoint: .leading, endPoint: .trailing)
}

extension AngularGradient {
    static let progressGradient = AngularGradient(
        gradient: Gradient(colors: [Color(hex: "0439C7"), Color(hex: "33E6BF")]),
        center: .center,
        startAngle: .degrees(360),
        endAngle: .degrees(-3)
    )
}
