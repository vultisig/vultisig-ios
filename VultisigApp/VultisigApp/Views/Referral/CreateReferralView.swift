//
//  CreateReferralView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct CreateReferralView: View {
    @ObservedObject var referralViewModel: ReferralViewModel
    
    @StateObject var sendTx = SendTransaction()
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    @StateObject var functionCallViewModel = FunctionCallViewModel()
    @StateObject var functionCallVerifyViewModel = FunctionCallVerifyViewModel()
    
    @State var keysignPayload: KeysignPayload? = nil
    @State var keysignView: KeysignView? = nil
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
//        ZStack {
//            switch functionCallViewModel.currentIndex {
//            case 1:
//                detailsView
//            case 2:
//                verifyView
//            case 3:
//                pairView
//            case 4:
//                keysign
//            case 5:
//                doneView
//            default:
//                errorView
//            }
//        }
//        .frame(maxHeight: .infinity)
        ReferralTransactionOverviewView(hash: "", sendTx: SendTransaction(), referralViewModel: ReferralViewModel())
    }
    
    var detailsView: some View {
        CreateReferralDetailsView(sendTx: sendTx, referralViewModel: referralViewModel, functionCallViewModel: functionCallViewModel)
    }
    
    var verifyView: some View {
        FunctionCallVerifyView(
            keysignPayload: $keysignPayload,
            depositViewModel: functionCallViewModel,
            depositVerifyViewModel: functionCallVerifyViewModel,
            tx: sendTx,
            vault: homeViewModel.selectedVault ?? .example,
            isForReferral: true,
            referralViewModel: referralViewModel
        )
    }
    
    var pairView: some View {
        ZStack {
            if let keysignPayload = keysignPayload {
                KeysignDiscoveryView(
                    vault: homeViewModel.selectedVault ?? .example,
                    keysignPayload: keysignPayload,
                    customMessagePayload: nil,
                    transferViewModel: functionCallViewModel,
                    fastVaultPassword: sendTx.fastVaultPassword.nilIfEmpty,
                    keysignView: $keysignView,
                    shareSheetViewModel: shareSheetViewModel
                )
            } else {
                SendCryptoVaultErrorView()
            }
        }
    }
    
    var keysign: some View {
        ZStack {
            if let keysignView = keysignView {
                keysignView
            } else {
                errorView
            }
        }
    }
    
    var doneView: some View {
        ZStack {
            if let hash = functionCallViewModel.hash  {
                ReferralTransactionOverviewView(hash: hash, sendTx: sendTx, referralViewModel: referralViewModel)
            } else {
                errorView
            }
        }.onAppear() {
            Task{
                try await Task.sleep(for: .seconds(5)) // Back off 5s
                self.functionCallViewModel.stopMediator()
            }
        }
    }
    
    var errorView: some View {
        SendCryptoSigningErrorView()
    }
}

#Preview {
    CreateReferralView(referralViewModel: ReferralViewModel())
        .environmentObject(HomeViewModel())
}
