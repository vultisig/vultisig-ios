//
//  ColorStyle.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import SwiftUI

extension LinearGradient {
    static let primaryGradient = LinearGradient(colors: [Color(hex: "33E6BF"), Color(hex: "0439C7")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let primaryGradientLinear = LinearGradient(colors: [Color(hex: "33E6BF"), Color(hex: "0439C7")], startPoint: .top, endPoint: .bottom)
    static let primaryGradientHorizontal = LinearGradient(colors: [Color(hex: "33E6BF"), Color(hex: "0439C7")], startPoint: .leading, endPoint: .trailing)
    static let secondaryGradientHorizontal = LinearGradient(
        stops: [.init(color: Color(hex: "33E6BF"), location: 0), .init(color: Color(hex: "0439C7"), location: 2)],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let progressGradient = LinearGradient(colors: [Color(hex: "0439C7"), Color(hex: "33E6BF")], startPoint: .leading, endPoint: .trailing)
    static let cancelRed = LinearGradient(colors: [Color.red], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let solidBlue = LinearGradient(colors: [Theme.colors.bgButtonTertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let solidWhite = LinearGradient(colors: [Theme.colors.textPrimary], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let solidGray = LinearGradient(colors: [Theme.colors.textSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let borderGreen = LinearGradient(colors: [Color(hex: "0FBF93"), Color(hex: "0FBF93").opacity(0)], startPoint: .top, endPoint: .bottom)
    static let qrBorderGradient = LinearGradient(
        colors: [Color(hex: "4879FD"), Color(hex: "0D39B1")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension AngularGradient {
    static let progressGradient = AngularGradient(
        gradient: Gradient(colors: [Color(hex: "0439C7"), Color(hex: "33E6BF")]),
        center: .center,
        startAngle: .degrees(360),
        endAngle: .degrees(-5)
    )
}
