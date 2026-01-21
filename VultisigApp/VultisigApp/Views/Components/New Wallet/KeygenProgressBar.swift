//
//  KeygenProgressBar.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-29.
//

import SwiftUI

struct KeygenProgressBar: View {
    let progress: CGFloat

    let primaryGradient = LinearGradient(colors: [Color(hex: "0439C7"), Color(hex: "33E6BF")], startPoint: .leading, endPoint: .trailing)

    let greenGlow = LinearGradient(colors: [Color(hex: "33E6BF").opacity(0), Color(hex: "33E6BF").opacity(0.5), Color(hex: "33E6BF")], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                loadingBar(
                    for: geometry.size.width,
                    gradient: greenGlow
                )
                .frame(height: 5)
                .blur(radius: 5)
                .offset(x: 5)

                loadingBar(
                    for: geometry.size.width,
                    gradient: primaryGradient
                )
                .frame(height: 2)
            }
        }
    }

    func loadingBar(for width: CGFloat, gradient: LinearGradient) -> some View {
        RoundedRectangle(cornerRadius: 30)
            .frame(width: width*progress)
            .foregroundStyle(gradient)
            .animation(.easeInOut, value: progress)
    }
}

#Preview {
    KeygenProgressBar(progress: 0)
}
