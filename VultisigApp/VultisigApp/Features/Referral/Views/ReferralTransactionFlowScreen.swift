//
//  ReferralTransactionFlowScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct ReferralTransactionFlowScreen: View {
    @ObservedObject var vaultSelectionViewModel: VaultSelectedViewModel
    let thornameDetails: THORName?
    let currentBlockHeight: UInt64

    @Environment(\.router) var router
    @EnvironmentObject var appViewModel: AppViewModel

    init(viewModel: VaultSelectedViewModel, thornameDetails: THORName?, currentBlockHeight: UInt64) {
        self.vaultSelectionViewModel = viewModel
        self.thornameDetails = thornameDetails
        self.currentBlockHeight = currentBlockHeight
    }

    private var resolvedVault: Vault? {
        vaultSelectionViewModel.selectedVault ?? appViewModel.selectedVault
    }

    var body: some View {
        Group {
            if let vault = resolvedVault,
               let nativeCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
                detailsView(vault: vault, nativeCoin: nativeCoin)
            } else {
                EmptyView()
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailsView(vault: Vault, nativeCoin: Coin) -> some View {
        if let details = thornameDetails {
            EditReferralDetailsView(
                viewModel: EditReferralDetailsViewModel(
                    nativeCoin: nativeCoin,
                    vault: vault,
                    thornameDetails: details,
                    currentBlockHeight: currentBlockHeight
                ),
                onNext: { tx in moveToNext(tx: tx, vault: vault) }
            )
        } else {
            CreateReferralDetailsView(
                viewModel: ReferralDetailsViewModel(
                    vault: vault,
                    thornameDetails: nil,
                    currentBlockheight: currentBlockHeight
                ),
                onNext: { tx in moveToNext(tx: tx, vault: vault) }
            )
        }
    }

    private func moveToNext(tx: SendTransaction, vault: Vault) {
        router.navigate(to: FunctionCallRoute.verify(tx: tx, vault: vault))
    }
}
