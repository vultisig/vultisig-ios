//
//  NavigationBlankBackButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-06.
//

import SwiftUI

struct NavigationBlankBackButton: View {
    var tint: Color = Theme.colors.textPrimary

    var image: some View {
        Image(systemName: "chevron.backward")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationBlankBackButton()
    }
}
