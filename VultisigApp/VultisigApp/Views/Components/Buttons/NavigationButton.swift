//
//  NavigationButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-17.
//

import SwiftUI

struct NavigationButton: View {
    var font = Theme.fonts.title1
    var tint = Color.neutral200
    var isLeft: Bool = false
    
    var body: some View {
        container
            .opacity(0.5)
            .rotationEffect(.degrees(isLeft ? 180 : 0))
    }
    
    var content: some View {
        Image(systemName: "arrow.right.circle.fill")
            .font(font)
    }
}

#Preview {
    NavigationButton()
}
