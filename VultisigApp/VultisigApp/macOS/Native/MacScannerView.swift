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
    let selectedVault: Vault?
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    
    @StateObject var cameraViewModel = MacCameraServiceViewModel()
    
    var body: some View {
        ZStack(alignment: .top) {
            Background()
            main
            headerMac
        }
        .navigationDestination(isPresented: $cameraViewModel.shouldJoinKeygen) {
            JoinKeygenView(vault: Vault(name: "Main Vault"), selectedVault: selectedVault)
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
                    coin: nil,
                    selectedChain: cameraViewModel.selectedChain
                )
            }
        }
        .alert(isPresented: $cameraViewModel.showAlert) {
            alert
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
                deeplinkViewModel: deeplinkViewModel,
                vaultDetailViewModel: vaultDetailViewModel,
                coinSelectionViewModel: coinSelectionViewModel
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
        PrimaryNavigationButton(title: "uploadQRCodeImage") {
            GeneralQRImportMacView(type: type, sendTx: sendTx, selectedVault: selectedVault)
        }
    }
    
    var tryAgainButton: some View {
        PrimaryButton(title: "tryAgain", type: .secondary) {
            cameraViewModel.setupSession()
        }
    }
    
    var alert: Alert {
        let message = NSLocalizedString("addNewChainToVault1", comment: "") + (cameraViewModel.newCoinMeta?.chain.name ?? "") + NSLocalizedString("addNewChainToVault2", comment: "")
        
        return Alert(
            title: Text(NSLocalizedString("newChainDetected", comment: "")),
            message: Text(message),
            primaryButton: Alert.Button.default(
                Text(NSLocalizedString("addChain", comment: "")),
                action: {
                    cameraViewModel.addNewChain(
                        coinSelectionViewModel: coinSelectionViewModel,
                        homeViewModel: homeViewModel
                    )
                }
            ),
            secondaryButton: Alert.Button.default(
                Text(NSLocalizedString("cancel", comment: "")),
                action: {
                    cameraViewModel.handleCancel()
                }
            )
        )
    }
    
    var background: some View {
        Image("QRScannerBackgroundImage")
            .resizable()
            .scaledToFill()
            .opacity(0.2)
    }
    
    var overlay: some View {
        VStack {
            Spacer()
            Image("QRScannerOutline")
            Spacer()
        }
        .allowsHitTesting(false)
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
                .overlay {
                    background
                }
            
            overlay
            
            uploadQRCodeButton
                .padding(40)
        }
    }
}

#Preview {
    MacScannerView(vault: .example, type: .NewVault, sendTx: SendTransaction(), selectedVault: nil)
        .environmentObject(HomeViewModel())
        .environmentObject(DeeplinkViewModel())
        .environmentObject(VaultDetailViewModel())
        .environmentObject(CoinSelectionViewModel())
}
#endif
