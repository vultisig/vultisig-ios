//
//  NavigationQRCodeButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct NavigationQRCodeButton: View {
    var tint: Color = Theme.colors.textPrimary
    
    var body: some View {
        Image(systemName: "qrcode")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(tint)
            .offset(x: 8)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRCodeButton()
    }
}
