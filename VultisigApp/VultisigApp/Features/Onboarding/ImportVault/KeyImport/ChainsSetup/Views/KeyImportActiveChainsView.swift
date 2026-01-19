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
    let onImport: () -> Void
    let onCustomize: () -> Void
    @ObservedObject var viewModel: KeyImportChainsSetupViewModel

    @State private var showDerivationSheet = false
    
    var minutes: Int {
        activeChains.count * 2
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            CircleIcon(
                icon: "active-chain",
                color: Theme.colors.alertSuccess
            )
            VStack(spacing: 12) {
                Text(String(format: "foundActiveChainsTitle".localized, activeChains.count))
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text("foundActiveChainsSubtitle".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .frame(maxWidth: 330)
                    .multilineTextAlignment(.center)
            }
            
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
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
                                    .fill(Theme.colors.bgSurface1.opacity(0.7))
                            )
                        }
                    }
                }
                .contentMargins(.bottom, 150)
                
                LinearGradient(colors: [Theme.colors.bgPrimary, .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: 150)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "importTheseChains", action: {
                        if activeChains.contains(where: { $0.chain == .solana }) &&
                           viewModel.hasMultipleDerivations(for: .solana) {
                            showDerivationSheet = true
                        } else {
                            onImport()
                        }
                    })
                    Button(action: onCustomize) {
                        HStack(spacing: 8) {
                            Icon(
                                named: "magic-pen",
                                color: Theme.colors.textPrimary,
                                size: 16
                            )
                            Text("customizeChains".localized)
                        }
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.buttonSMedium)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
        .crossPlatformSheet(isPresented: $showDerivationSheet) {
            DerivationPathSelectionSheet(
                chain: .solana,
                selectedPath: $viewModel.selectedDerivationPath,
                isPresented: $showDerivationSheet,
                onSelect: { path in
                    viewModel.selectDerivationPath(path, for: .solana)
                    onImport()
                }
            )
        }
    }
}

#Preview {
    KeyImportActiveChainsView(
        activeChains: [],
        onImport: {},
        onCustomize: {},
        viewModel: KeyImportChainsSetupViewModel()
    )
}
