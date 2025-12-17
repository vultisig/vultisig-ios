//
//  ReferralTransactionFlowScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct ReferralTransactionFlowScreen: View {
    @EnvironmentObject var referralViewModel: ReferralViewModel
    let isEdit: Bool
    
    @StateObject var sendTx = SendTransaction()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @StateObject var functionCallVerifyViewModel = FunctionCallVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    @State var isLoading = false
    @Environment(\.router) var router

    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        detailsView
            .withLoading(isLoading: $isLoading)
            .frame(maxHeight: .infinity)
            .onLoad {
                isLoading = true
                referralViewModel.setup(tx: sendTx)
                isLoading = false
                
                Task {
                    if let vault {
                        await functionCallViewModel.loadFastVault(tx: sendTx, vault: vault)
                    }
                }
            }
    }
    
    var vault: Vault? {
        referralViewModel.currentVault
    }
    
    @ViewBuilder
    var detailsView: some View {
        if isEdit,
           let details = referralViewModel.thornameDetails,
           let nativeCoin = referralViewModel.nativeCoin,
           let vault
        {
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
    ReferralTransactionFlowScreen(isEdit: false)
        .environmentObject(HomeViewModel())
}
