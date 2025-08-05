//
//  VaultDetailView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension VaultDetailView {
    var view: some View {
        list
            .blur(radius: getBackgroundOpacity()*2)
            .opacity(showVaultsList ? 0 : 1)
            .sheet(isPresented: $showScanner, content: {
                GeneralCodeScannerView(
                    showSheet: $showScanner,
                    shouldJoinKeygen: $shouldJoinKeygen,
                    shouldKeysignTransaction: $shouldKeysignTransaction,
                    shouldSendCrypto: $shouldSendCrypto,
                    selectedChain: $selectedChain,
                    sendTX: sendTx
                )
            })
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
        .background(Theme.colors.bgPrimary)
    }
    
    var chooseChainButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            chooseChainButtonLabel
        }
        .font(Theme.fonts.bodyMMedium)
        .foregroundColor(Theme.colors.bgButtonPrimary)
    }
    
    var scanButton: some View {
        VaultDetailScanButton(showSheet: $showScanner, vault: vault, sendTx: sendTx)
            .opacity(showVaultsList ? 0 : 1)
            .buttonStyle(BorderlessButtonStyle())
    }
    
    var list: some View {
        List {
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
        .listStyle(PlainListStyle())
        .buttonStyle(BorderlessButtonStyle())
        .refreshable {
            if let vault = homeViewModel.selectedVault {
                viewModel.updateBalance(vault: vault)
            }
        }
        .colorScheme(.dark)
        .scrollContentBackground(.hidden)
        .background(Theme.colors.bgPrimary)
    }
}
#endif
