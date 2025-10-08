//
//  VaultBannerView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultBannerView: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let bgImage: String
    let action: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textExtraLight)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(subtitle)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                
                PrimaryButton(
                    title: buttonTitle,
                    type: .primarySuccess,
                    size: .mini,
                    action: action
                )
                .frame(maxWidth: 100, alignment: .leading)
                .buttonStyle(.borderless)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            ToolbarButton(
                image: "cross-small",
                iconSize: 16,
                action: onClose
            )
        }
        .padding(8)
        .background(backgroundImage)
        .containerStyle()
    }

    var backgroundImage: some View {
        Image(bgImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}

#Preview {
    VStack {
        VaultBannerView(
            title: "signFasterThanEverBefore",
            subtitle: "upgradeYourVaultNow",
            buttonTitle: "upgradeNow",
            bgImage: "referral-banner-2"
        ) {} onClose: {}
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(Theme.colors.bgPrimary)
    
}
