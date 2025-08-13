//
//  NavigationEditButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-17.
//

import SwiftUI

struct NavigationEditButton: View {
    var tint: Color = Theme.colors.textPrimary
    
    var body: some View {
        Image(systemName: "square.and.pencil")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(tint)
            .offset(x: 8)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationEditButton()
    }
}
