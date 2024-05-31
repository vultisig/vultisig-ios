//
//  JoinKeysignView.swift
//  VultisigApp

import CodeScanner
import OSLog
import SwiftUI

struct JoinKeysignView: View {
    let vault: Vault
       
    @StateObject private var serviceDelegate = ServiceDelegate()
    @StateObject var viewModel = JoinKeysignViewModel()
    @State var isGalleryPresented = false
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var appViewModel: ApplicationState
    
    let logger = Logger(subsystem: "join-keysign", category: "communication")

    var body: some View {
        ZStack {
            Background()
            states
        }
        .navigationTitle(NSLocalizedString("joinKeySign", comment: "Join Keysign"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationHelpButton()
            }
        }
        .sheet(isPresented: $viewModel.isShowingScanner, content: {
            codeScanner
        })
        .onAppear {
            setData()
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
            transferViewModel: nil,
            encryptionKeyHex: viewModel.encryptionKeyHex
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
        } else if viewModel.keysignPayload?.approvePayload != nil {
            KeysignApproveConfirmView(viewModel: viewModel)
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
    
    var codeScanner: some View {
        ZStack(alignment: .bottom) {
            CodeScannerView(codeTypes: [.qr], isGalleryPresented: $isGalleryPresented, completion: viewModel.handleScan)
            galleryButton
        }
    }
    
    var galleryButton: some View {
        Button {
            isGalleryPresented.toggle()
        } label: {
            OpenGalleryButton()
        }
        .padding(.bottom, 50)
    }
    
    private func setData() {
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
}
