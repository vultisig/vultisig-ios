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
#if os(iOS)
            .font(.body18MenloBold)
            .foregroundColor(tint)
#elseif os(macOS)
            .font(.body18Menlo)
#endif
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRCodeButton()
    }
}
