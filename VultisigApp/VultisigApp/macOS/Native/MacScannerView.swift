//
//  MacScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//

#if os(macOS)
import SwiftUI
import SwiftData
import AVFoundation

struct MacScannerView: View {
    let vault: Vault
    let type: DeeplinkFlowType
    let sendTx: SendTransaction
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var cameraViewModel: MacCameraServiceViewModel
    @EnvironmentObject var settingsDefaultChainViewModel: SettingsDefaultChainViewModel
    
    var body: some View {
        ZStack(alignment: .top) {
            Background()
            main
            headerMac
        }
        .navigationDestination(isPresented: $cameraViewModel.shouldJoinKeygen) {
            JoinKeygenView(vault: vault)
        }
        .navigationDestination(isPresented: $cameraViewModel.shouldKeysignTransaction) {
            if let vault = homeViewModel.selectedVault {
                JoinKeysignView(vault: vault)
            }
        }
        .navigationDestination(isPresented: $cameraViewModel.shouldSendCrypto) {
            if let vault = homeViewModel.selectedVault {
                SendCryptoView(
                    tx: sendTx,
                    vault: vault,
                    selectedChain: cameraViewModel.selectedChain
                )
            }
        }
    }
    
    var main: some View {
        VStack(spacing: 0) {
            view
        }
        .onChange(of: cameraViewModel.detectedQRCode) { oldValue, newValue in
            cameraViewModel.handleScan(
                vaults: vaults,
                sendTx: sendTx,
                cameraViewModel: cameraViewModel,
                deeplinkViewModel: deeplinkViewModel,
                settingsDefaultChainViewModel: settingsDefaultChainViewModel
            )
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: cameraViewModel.getTitle(type))
            .padding(.bottom, 8)
    }
    
    var view: some View {
        ZStack {
            if cameraViewModel.showPlaceholderError {
                fallbackErrorView
            }
            
            if !cameraViewModel.showCamera {
                loader
            } else if cameraViewModel.isCameraUnavailable {
                errorView
            } else if let session = cameraViewModel.getSession() {
                getScanner(session)
            }
        }
    }
    
    var loader: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                Text(NSLocalizedString("initializingCamera", comment: ""))
                    .font(.body16MenloBold)
                    .foregroundColor(.neutral0)
                
                ProgressView()
                    .preferredColorScheme(.dark)
            }
            
            Spacer()
        }
    }
    
    var errorView: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noCameraFound")
            Spacer()
            buttons
        }
    }
    
    var fallbackErrorView: some View {
        VStack {
            Spacer()
            ErrorMessage(text: "noCameraFound")
            Spacer()
        }
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            uploadQRCodeButton
            tryAgainButton
        }
        .padding(40)
    }
    
    var uploadQRCodeButton: some View {
        NavigationLink {
            GeneralQRImportMacView(vault: vault, type: type)
        } label: {
            FilledButton(title: "uploadQRCodeImage")
        }
    }
    
    var tryAgainButton: some View {
        Button {
            cameraViewModel.setupSession()
        } label: {
            OutlineButton(title: "tryAgain")
        }
    }
    
    private func getScanner(_ session: AVCaptureSession) -> some View {
        ZStack(alignment: .bottom) {
            MacCameraPreview(session: session)
                .onAppear {
                    cameraViewModel.startSession()
                }
                .onDisappear {
                    cameraViewModel.stopSession()
                }
            
            uploadQRCodeButton
                .padding(40)
        }
    }
}

#Preview {
    MacScannerView(vault: .example, type: .NewVault, sendTx: SendTransaction())
        .environmentObject(HomeViewModel())
        .environmentObject(DeeplinkViewModel())
        .environmentObject(MacCameraServiceViewModel())
        .environmentObject(SettingsDefaultChainViewModel())
}
#endif
