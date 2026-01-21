//
//  NavigationMenuButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct NavigationMenuButton: View {
    var tint: Color = Theme.colors.textPrimary

    var body: some View {
        Image("MenuIcon")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationMenuButton()
    }
}
