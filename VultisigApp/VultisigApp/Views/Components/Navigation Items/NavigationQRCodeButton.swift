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
            .font(.body18MenloBold)
            .foregroundColor(tint)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRCodeButton()
    }
}
