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
            .opacity(showVaultsList ? 0 : 1)
            .navigationDestination(isPresented: $shouldJoinKeygen) {
                JoinKeygenView(vault: Vault(name: "Main Vault"))
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
                    selectedChain: selectedChain
                )
            }
    }
    
    var cells: some View {
        return ForEach(viewModel.groups.sorted(by: {
            $0.totalBalanceInFiatDecimal > $1.totalBalanceInFiatDecimal
        }), id: \.id) { group in
            ChainNavigationCell(
                group: group,
                vault: vault,
                showAlert: $showAlert
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
        VaultDetailScanButton(showSheet: $showScanner, sendTx: sendTx)
            .opacity(showVaultsList ? 0 : 1)
            .buttonStyle(BorderlessButtonStyle())
            .padding(.bottom, 30)
    }
    
    var list: some View {
        ScrollView {
            VStack(spacing: 4) {
                if isLoading {
                    loader
                } else if viewModel.groups.count >= 1 {
                    
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
