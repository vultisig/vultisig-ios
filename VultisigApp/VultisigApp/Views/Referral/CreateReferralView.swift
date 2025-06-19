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
        ReferralSendOverviewView(sendTx: sendTx, referralViewModel: referralViewModel, functionCallViewModel: functionCallViewModel)
    }
}

#Preview {
    CreateReferralView(referralViewModel: ReferralViewModel())
        .environmentObject(HomeViewModel())
}
