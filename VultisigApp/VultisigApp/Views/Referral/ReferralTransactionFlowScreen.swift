//
//  ReferralTransactionFlowScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-30.
//

import SwiftUI

struct ReferralTransactionFlowScreen: View {
    @ObservedObject var referralViewModel: ReferralViewModel
    let isEdit: Bool
    
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
        .onLoad {
            Task {
                if let vault {
                    await functionCallViewModel.loadFastVault(tx: sendTx, vault: vault)
                    referralViewModel.setup(tx: sendTx)
                }
            }
        }
    }
    
    var vault: Vault? {
        isEdit ? referralViewModel.thornameVault : homeViewModel.selectedVault
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
                functionCallViewModel: functionCallViewModel
            )
        } else {
            CreateReferralDetailsView(sendTx: sendTx, referralViewModel: referralViewModel, functionCallViewModel: functionCallViewModel)
        }
    }
    
    var verifyView: some View {
        ZStack {
            if let vault {
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
                if let keysignPayload = keysignPayload, let vault {
                    KeysignDiscoveryView(
                        vault: vault,
                        keysignPayload: keysignPayload,
                        customMessagePayload: nil,
                        fastVaultPassword: sendTx.fastVaultPassword.nilIfEmpty,
                        shareSheetViewModel: shareSheetViewModel
                    ){ input in
                        self.keysignView = KeysignView(
                            vault: input.vault,
                            keysignCommittee: input.keysignCommittee,
                            mediatorURL: input.mediatorURL,
                            sessionID: input.sessionID,
                            keysignType: input.keysignType,
                            messsageToSign: input.messsageToSign,
                            keysignPayload: input.keysignPayload,
                            customMessagePayload: input.customMessagePayload,
                            transferViewModel: functionCallViewModel,
                            encryptionKeyHex: input.encryptionKeyHex,
                            isInitiateDevice: input.isInitiateDevice
                        )
                        functionCallViewModel.moveToNextView()
                    }
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
                ReferralTransactionOverviewView(
                    hash: hash,
                    sendTx: sendTx,
                    isEdit: isEdit,
                    referralViewModel: referralViewModel
                )
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
        SendCryptoSigningErrorView(errorString: functionCallViewModel.errorMessage)
    }
    
    private func getNavigationTitle(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
            .background(Background())
    }
}

#Preview {
    ReferralTransactionFlowScreen(referralViewModel: ReferralViewModel(), isEdit: false)
        .environmentObject(HomeViewModel())
}
