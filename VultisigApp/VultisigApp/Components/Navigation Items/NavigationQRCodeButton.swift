//
//  NavigationQRCodeButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

struct NavigationQRCodeButton: View {
    var body: some View {
        Icon(
            named: "qr-code",
            color: Theme.colors.textPrimary,
            size: 16
        ).padding(8)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationQRCodeButton()
    }
}
