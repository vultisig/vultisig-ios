//
//  KeyImportNoActiveChainsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/12/2025.
//

import SwiftUI

struct KeyImportNoActiveChainsView: View {
    let onAddCustomChains: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            CircleIcon(
                icon: "active-chain",
                color: Theme.colors.alertError
            )
            VStack(spacing: 12) {
                Text("noActiveChainsFound".localized)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("noActiveChainsFoundSubtitle".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(
                title: "addCustomChains".localized,
                action: onAddCustomChains
            ).fixedSize()
            Spacer()
        }
    }
}

#Preview {
    KeyImportNoActiveChainsView(onAddCustomChains: {})
}
