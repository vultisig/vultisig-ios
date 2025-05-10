//
//  VaultDetailView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension VaultDetailView {
    var view: some View {
        list
            .blur(radius: getBackgroundOpacity()*2)
            .opacity(showVaultsList ? 0 : 1)
            .navigationDestination(isPresented: $shouldJoinKeygen) {
                JoinKeygenView(vault: Vault(name: "Main Vault"), selectedVault: vault)
            }
            .navigationDestination(isPresented: $shouldKeysignTransaction) {
                if let vault = homeViewModel.selectedVault {
                    JoinKeysignView(vault: vault)
                }
            }
            .navigationDestination(isPresented: $shouldSendCrypto) {
                SendCryptoView(
                    tx: sendTx,
                    vault: vault,
                    coin: nil,
                    selectedChain: selectedChain
                )
            }
    }
    
    var cells: some View {
        return ForEach(viewModel.groups, id: \.id) { group in
            ChainNavigationCell(
                group: group,
                vault: vault
            )
        }
        .background(Color.backgroundBlue)
        .padding(.horizontal, 16)
    }
    
    var chooseChainButton: some View {
        NavigationLink {
            ChainSelectionView(showChainSelectionSheet: $showSheet, vault: vault)
        } label: {
            chooseChainButtonLabel
        }
        .padding(.horizontal, 16)
        .frame(height: 20)
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }
    
    var scanButton: some View {
        VaultDetailScanButton(showSheet: $showScanner, vault: vault, sendTx: sendTx)
            .opacity(showVaultsList ? 0 : 1)
            .buttonStyle(BorderlessButtonStyle())
            .padding(.bottom, 30)
    }
    
    var list: some View {
        ScrollView {
            VStack(spacing: 4) {
                if viewModel.groups.count >= 1 {
                    if vault.libType == .GG20 {
                        upgradeVaultBanner
                    }
                    
                    if !vault.isBackedUp {
                        backupNowWidget
                    }
                    
                    balanceContent
                    getActions()
                    cells
                } else {
                    emptyList
                }
                
                addButton
                pad
            }
        }
    }
}
#endif
