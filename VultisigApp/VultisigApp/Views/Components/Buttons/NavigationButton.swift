//
//  NavigationButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-17.
//

import SwiftUI

struct NavigationButton: View {
    var font = Font.title32MenloBold
    var tint = Color.neutral200
    var isLeft: Bool = false
    
    var body: some View {
        Image(systemName: "arrow.right.circle.fill")
            .font(font)
        #if os(iOS)
            .foregroundColor(tint)
        #endif
            .opacity(0.5)
            .rotationEffect(.degrees(isLeft ? 180 : 0))
    }
}

#Preview {
    NavigationButton()
}
