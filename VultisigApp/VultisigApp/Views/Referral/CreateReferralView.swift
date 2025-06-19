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
        ZStack {
            switch functionCallViewModel.currentIndex {
            case 1:
                detailsView
            case 2:
                verifyView
//            case 3:
//                pairView
//            case 4:
//                keysign
//            case 5:
//                doneView
            default:
                EmptyView()
            }
        }
        .frame(maxHeight: .infinity)
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
}

#Preview {
    CreateReferralView(referralViewModel: ReferralViewModel())
        .environmentObject(HomeViewModel())
}
