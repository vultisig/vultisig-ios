//
//  KeyImportActiveChainsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/12/2025.
//

import SwiftUI

struct KeyImportChain: Identifiable, Hashable {
    var id: String { chain.name }
    let chain: Chain
    let balance: String
}

struct KeyImportActiveChainsView: View {
    let activeChains: [KeyImportChain]
    let maxChains: Int
    let onImport: () -> Void
    let onCustomize: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Text("foundActiveChainsTitle")
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(String(format: "foundActiveChainsSubtitle".localized, maxChains))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textExtraLight)
                    .frame(maxWidth: 330)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                ForEach(activeChains) { chain in
                    HStack(spacing: 12) {
                        AsyncImageView(
                            logo: chain.chain.logo,
                            size: .init(width: 32, height: 32),
                            ticker: "",
                            tokenChainLogo: nil
                        )
                        Text(chain.chain.name)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodySMedium)
                        Spacer()
                        Text(chain.balance)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.priceBodyS)
                    }
                    .padding(12)
                    .padding(.trailing, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .inset(by: 0.5)
                            .stroke(Theme.colors.borderLight, lineWidth: 1)
                            .fill(Theme.colors.bgSecondary.opacity(0.7))
                    )
                }
            }
            
            VStack(spacing: 12) {
                PrimaryButton(title: "importTheseChains", action: onImport)
                PrimaryButton(title: "customizeChains", type: .secondary, action: onCustomize)
            }
        }
    }
}

#Preview {
    KeyImportActiveChainsView(
        activeChains: [],
        maxChains: 4,
        onImport: {},
        onCustomize: {}
    )
}
