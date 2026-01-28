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
    let type: DeeplinkFlowType
    let sendTx: SendTransaction
    let selectedVault: Vault?

    @Query var vaults: [Vault]

    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel

    @Environment(\.router) var router

    @StateObject var cameraViewModel = MacCameraServiceViewModel()

    @State var navigateToUploadQR = false
    @State private var deeplinkError: Error?

    var body: some View {
        ZStack(alignment: .top) {
            Background()
            main
        }
        .crossPlatformToolbar(cameraViewModel.getTitle(type))
        .onChange(of: cameraViewModel.shouldJoinKeygen) { _, shouldNavigate in
            guard shouldNavigate else { return }
            router.navigate(to: OnboardingRoute.joinKeygen(
                vault: Vault(name: "Main Vault"),
                selectedVault: selectedVault
            ))
            cameraViewModel.shouldJoinKeygen = false
        }
        .onChange(of: cameraViewModel.shouldKeysignTransaction) { _, shouldNavigate in
            guard shouldNavigate, let vault = appViewModel.selectedVault else { return }
            router.navigate(to: KeygenRoute.joinKeysign(vault: vault))
            cameraViewModel.shouldKeysignTransaction = false
        }
        .onChange(of: navigateToUploadQR) { _, shouldNavigate in
            guard shouldNavigate else { return }
            router.navigate(to: KeygenRoute.generalQRImport(
                type: type,
                selectedVault: selectedVault,
                sendTx: sendTx
            ))
            navigateToUploadQR = false
        }
        .withError(error: $deeplinkError, errorType: .warning) {
            // Retry action - clear error to allow user to try again
            deeplinkError = nil
        }
    }

    var main: some View {
        VStack(spacing: 0) {
            view
        }
        .onChange(of: cameraViewModel.detectedQRCode) { _, newValue in
            if let newValue = newValue, !newValue.isEmpty {
                cameraViewModel.handleScan(
                    vaults: vaults,
                    deeplinkViewModel: deeplinkViewModel,
                    error: $deeplinkError
                )
            }
        }
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
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundColor(Theme.colors.textPrimary)

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
        PrimaryButton(title: "uploadQRCodeImage") {
            navigateToUploadQR = true
        }
    }

    var tryAgainButton: some View {
        PrimaryButton(title: "tryAgain", type: .secondary) {
            cameraViewModel.setupSession()
        }
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

            overlay

            uploadQRCodeButton
                .padding(40)
        }
    }
}

#Preview {
    MacScannerView(type: .NewVault, sendTx: SendTransaction(), selectedVault: nil)
        .environmentObject(AppViewModel())
        .environmentObject(DeeplinkViewModel())
        .environmentObject(VaultDetailViewModel())
        .environmentObject(CoinSelectionViewModel())
}
#endif
