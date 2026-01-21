//
//  KeygenStatusText.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct KeygenStatusText: View {
    let gradientText: String
    let plainText: String

    var body: some View {
        Group {
            Text(NSLocalizedString(gradientText, comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString(plainText, comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
        }
        .font(Theme.fonts.title2)
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        Background()
        KeygenStatusText(
            gradientText: "preparingVaultText1",
            plainText: "preparingVaultText2"
        )
    }
}
