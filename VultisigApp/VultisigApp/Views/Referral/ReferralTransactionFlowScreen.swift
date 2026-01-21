//
//  ReferralTransactionFlowScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct ReferralTransactionFlowScreen: View {
    @StateObject var referralViewModel: ReferralViewModel
    @ObservedObject var vaultSelectionViewModel: VaultSelectedViewModel
    
    @StateObject var sendTx = SendTransaction()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @StateObject var functionCallVerifyViewModel = FunctionCallVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    @State var isLoading = false
    @Environment(\.router) var router

    @EnvironmentObject var appViewModel: AppViewModel
    
    init(viewModel: VaultSelectedViewModel, thornameDetails: THORName?, currentBlockHeight: UInt64) {
        self.vaultSelectionViewModel = viewModel
        self._referralViewModel = StateObject(
            wrappedValue: ReferralViewModel(
                thornameDetails: thornameDetails,
                currentBlockheight: currentBlockHeight
            )
        )
    }
    
    var vault: Vault? {
        vaultSelectionViewModel.selectedVault ?? referralViewModel.currentVault
    }
    
    var body: some View {
        detailsView
            .withLoading(isLoading: $isLoading)
            .frame(maxHeight: .infinity)
            .onLoad {
                isLoading = true
                referralViewModel.setup(tx: sendTx, defaultVault: appViewModel.selectedVault)
                isLoading = false
                
                Task {
                    if let vault {
                        await functionCallViewModel.loadFastVault(tx: sendTx, vault: vault)
                    }
                }
            }
    }
    
    @ViewBuilder
    var detailsView: some View {
        if let details = referralViewModel.thornameDetails,
           let nativeCoin = referralViewModel.nativeCoin,
           let vault {
            EditReferralDetailsView(
                viewModel: EditReferralViewModel(
                    nativeCoin: nativeCoin,
                    vault: vault,
                    thornameDetails: details,
                    currentBlockHeight: referralViewModel.currentBlockheight
                ),
                sendTx: sendTx,
                onNext: moveToNext
            )
        } else {
            CreateReferralDetailsView(
                sendTx: sendTx,
                referralViewModel: referralViewModel,
                onNext: moveToNext
            )
        }
    }
    
    func moveToNext() {
        guard let vault else { return }
        router.navigate(to: FunctionCallRoute.verify(tx: sendTx, vault: vault))
    }
}

#Preview {
    ReferralTransactionFlowScreen(viewModel: VaultSelectedViewModel(), thornameDetails: nil, currentBlockHeight: 0)
        .environmentObject(AppViewModel())
}
