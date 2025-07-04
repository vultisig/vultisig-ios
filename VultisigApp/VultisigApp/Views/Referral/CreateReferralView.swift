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
            case 3:
                pairView
            case 4:
                keysign
            case 5:
                doneView
            default:
                errorView
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    var detailsView: some View {
        CreateReferralDetailsView(sendTx: sendTx, referralViewModel: referralViewModel, functionCallViewModel: functionCallViewModel)
    }
    
    var verifyView: some View {
        ZStack {
            if let vault = homeViewModel.selectedVault {
                FunctionCallVerifyView(
                    keysignPayload: $keysignPayload,
                    depositViewModel: functionCallViewModel,
                    depositVerifyViewModel: functionCallVerifyViewModel,
                    tx: sendTx,
                    vault: vault,
                    isForReferral: true
                )
            } else {
                SendCryptoVaultErrorView()
            }
        }
    }
    
    var pairView: some View {
        VStack(spacing: 0) {
            pairViewHeader
            
            ZStack {
                if let keysignPayload = keysignPayload, let vault = homeViewModel.selectedVault {
                    KeysignDiscoveryView(
                        vault: vault,
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
        .navigationBarBackButtonHidden(true)
        .background(Background())
    }
    
    var pairViewHeader: some View {
        HStack {
            backButton
            Spacer()
            headerTitle
            Spacer()
            backButton
                .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    var backButton: some View {
        Button {
            functionCallViewModel.currentIndex -= 1
        } label: {
            NavigationBlankBackButton()
        }
    }
    
    var headerTitle: some View {
        getNavigationTitle("scanQrCode")
    }
    
    var keysign: some View {
        VStack {
            getNavigationTitle("signing")
            
            ZStack {
                Background()
                
                if let keysignView = keysignView {
                    keysignView
                } else {
                    errorView
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var doneView: some View {
        ZStack {
            if let hash = functionCallViewModel.hash  {
                ReferralTransactionOverviewView(hash: hash, sendTx: sendTx, referralViewModel: referralViewModel)
            } else {
                errorView
            }
        }
        .onAppear() {
            Task{
                try await Task.sleep(for: .seconds(5)) // Back off 5s
                self.functionCallViewModel.stopMediator()
            }
        }
        .navigationBarBackButtonHidden()
    }
    
    var errorView: some View {
        SendCryptoSigningErrorView()
    }
    
    private func getNavigationTitle(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(.neutral0)
            .font(.body18BrockmannMedium)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
            .background(Background())
    }
}

#Preview {
    CreateReferralView(referralViewModel: ReferralViewModel())
        .environmentObject(HomeViewModel())
}
