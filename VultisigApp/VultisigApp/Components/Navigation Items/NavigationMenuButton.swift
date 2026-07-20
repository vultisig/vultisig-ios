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
        Image(.menu)
            .font(Theme.fonts.bodyLMedium)
            .foregroundStyle(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationMenuButton()
    }
}
