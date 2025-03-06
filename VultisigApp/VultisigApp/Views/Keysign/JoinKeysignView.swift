//
//  JoinKeysignView.swift
//  VultisigApp

import SwiftUI

struct JoinKeysignView: View {
    let vault: Vault
    
    @StateObject private var serviceDelegate = ServiceDelegate()
    @StateObject var viewModel = JoinKeysignViewModel()
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var appViewModel: ApplicationState
    @EnvironmentObject var globalStateViewModel: GlobalStateViewModel
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
            .task {
                do{
                    _ = try await ThorchainService.shared.getTHORChainChainID()
                } catch {
                    print("fail to get thorchain network id, \(error.localizedDescription)")
                }
            }
            .onDisappear(){
                viewModel.stopJoiningKeysign()
            }
    }
    
    var states: some View {
        ZStack {
            switch viewModel.status {
            case .DiscoverSigningMsg:
                discoveringSignMessage
            case .DiscoverService:
                discoverService
            case .JoinKeysign:
                keysignMessageConfirm
            case .WaitingForKeysignToStart:
                waitingForKeySignStart
            case .KeysignStarted:
                keysignStartedView
            case .FailedToStart:
                keysignFailedText
            case .VaultMismatch:
                KeysignVaultMismatchErrorView()
            case .KeysignSameDeviceShare:
                KeysignSameDeviceShareErrorView()
            case .KeysignNoCameraAccess:
                NoCameraPermissionView()
            }
        }
        .padding()
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    var keysignStartedView: some View {
        ZStack {
            if viewModel.serverAddress != nil && !viewModel.sessionID.isEmpty {
                keysignView
            } else {
                Text(NSLocalizedString("unableToStartKeysignProcess", comment: ""))
                    .font(.body15MenloBold)
                    .foregroundColor(.neutral0)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
    }
    
    var keysignView: some View {
        KeysignView(
            vault: vault,
            keysignCommittee: viewModel.keysignCommittee,
            mediatorURL: viewModel.serverAddress ?? "",
            sessionID: viewModel.sessionID,
            keysignType: viewModel.keysignPayload?.coin.chain.signingKeyType ?? .ECDSA,
            messsageToSign: viewModel.keysignMessages,
            keysignPayload: viewModel.keysignPayload, 
            customMessagePayload: viewModel.customMessagePayload,
            transferViewModel: nil,
            encryptionKeyHex: viewModel.encryptionKeyHex,
            isInitiateDevice: false
        )
    }
    
    var keysignFailedText: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("keysignFail", comment: "Failed to start the keysign process"))
            Text(viewModel.errorMsg)
        }
        .font(.body15MenloBold)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
    }
    
    @ViewBuilder
    var keysignMessageConfirm: some View {
        if viewModel.keysignPayload?.swapPayload != nil {
            KeysignSwapConfirmView(viewModel: viewModel)
        } else if viewModel.customMessagePayload != nil {
            KeysignCustomMessageConfirmView(viewModel: viewModel)
        } else {
            KeysignMessageConfirmView(viewModel: viewModel)
        }
    }
    
    var waitingForKeySignStart: some View {
        KeysignStartView(viewModel: viewModel)
    }
    
    var discoveringSignMessage: some View {
        Loader()
            .onAppear {
                viewModel.startScan()
            }
    }
    
    var discoverService: some View {
        KeysignDiscoverServiceView(viewModel: viewModel, serviceDelegate: serviceDelegate)
    }
    
    private func setData() {
        appViewModel.checkCameraPermission()
        
        viewModel.setData(
            vault: vault,
            serviceDelegate: serviceDelegate, 
            isCameraPermissionGranted: appViewModel.isCameraPermissionGranted
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            viewModel.isShowingScanner = false
            viewModel.handleDeeplinkScan(deeplinkViewModel.receivedUrl)
        }
    }
}

#Preview {
    JoinKeysignView(vault: Vault.example)
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
        .environmentObject(GlobalStateViewModel())
}
