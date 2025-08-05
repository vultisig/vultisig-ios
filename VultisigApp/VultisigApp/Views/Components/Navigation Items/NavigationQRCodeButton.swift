//
//  NavigationQRCodeButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct NavigationQRCodeButton: View {
    var tint: Color = Color.neutral0
    
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
