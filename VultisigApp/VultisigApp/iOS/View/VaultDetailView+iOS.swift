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
        let sortedGroups = viewModel.coinsGroupedByChains.sorted(by: {
            $0.totalBalanceInFiatDecimal > $1.totalBalanceInFiatDecimal
        })
        
        return ForEach(sortedGroups, id: \.id) { group in
            ChainNavigationCell(
                group: group,
                vault: vault,
                showAlert: $showAlert
            )
        }
        .background(Color.backgroundBlue)
    }
    
    var chooseChainButton: some View {
        Button {
            showSheet.toggle()
        } label: {
            chooseChainButtonLabel
        }
        .font(.body16MenloBold)
        .foregroundColor(.turquoise600)
    }
    
    var scanButton: some View {
        VaultDetailScanButton(showSheet: $showScanner, sendTx: sendTx)
            .opacity(showVaultsList ? 0 : 1)
            .buttonStyle(BorderlessButtonStyle())
    }
}
#endif
