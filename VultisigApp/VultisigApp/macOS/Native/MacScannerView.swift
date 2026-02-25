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
    @StateObject var screenCaptureService = MacScreenCaptureService()

    @State private var scannerMode: ScannerMode = .camera
    @State private var deeplinkError: Error?

    private let scanSize: CGFloat = 400

    var body: some View {
        ZStack(alignment: .top) {
            Background()
                .showIf(scannerMode == .camera)
            main
        }
        .crossPlatformToolbar(cameraViewModel.getTitle(type)) {
            CustomToolbarItem(placement: .trailing) {
                FilledSegmentedControl(
                    selection: $scannerMode,
                    options: ScannerMode.allCases,
                    size: .small
                ).frame(maxWidth: 200)
            }
        }
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
        .withError(error: $deeplinkError, errorType: .warning) {
            deeplinkError = nil
        }
        .onChange(of: scannerMode) { _, newMode in
            handleModeChange(newMode)
        }
        .onNavigationStackChange { isVisible in
            if isVisible {
                handleModeVisible()
            } else {
                handleModeHidden()
            }
        }
    }

    var main: some View {
        scannerContent
            .onChange(of: cameraViewModel.detectedQRCode) { _, newValue in
                if let newValue = newValue, !newValue.isEmpty {
                    cameraViewModel.handleScan(
                        vaults: vaults,
                        deeplinkViewModel: deeplinkViewModel,
                        error: $deeplinkError
                    )
                }
            }
            .onChange(of: screenCaptureService.detectedQRCode) { _, newValue in
                guard let newValue = newValue, !newValue.isEmpty else { return }
                screenCaptureService.stopCapture()
                cameraViewModel.detectedQRCode = newValue
            }
    }

    @ViewBuilder
    var scannerContent: some View {
        switch scannerMode {
        case .camera:
            cameraView
        case .screen:
            screenCaptureView
        }
    }

    var cameraView: some View {
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

    var screenCaptureView: some View {
        ZStack {
            if screenCaptureService.isPermissionDenied {
                VStack {
                    Spacer()
                    screenPermissionDeniedView
                    Spacer()
                }
            } else {
                screenPreviewView
            }
        }
    }

    @ViewBuilder
    var screenPreviewView: some View {
        let padding: CGFloat = 40
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                MacScreenCapturePreview(scanRegion: screenCaptureService.scanRegion)
                    .frame(width: scanSize, height: scanSize)
                qrCodeOutline
            }
            Spacer()
            uploadQRCodeButton
        }
        .frame(maxHeight: .infinity)
        .padding(padding)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 36)
                    .offset(y: -30)
                    .frame(width: scanSize - 16, height: scanSize - 16)
                    .blendMode(.destinationOut)
            }.compositingGroup()
        )
    }

    var screenPermissionDeniedView: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("screenRecordingPermissionDenied", comment: ""))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            PrimaryButton(title: "openSystemSettings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(.horizontal, 40)
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
            router.navigate(to: KeygenRoute.generalQRImport(
                type: type,
                selectedVault: selectedVault,
                sendTx: sendTx
            ))
        }
    }

    var tryAgainButton: some View {
        PrimaryButton(title: "tryAgain", type: .secondary) {
            cameraViewModel.setupSession()
        }
    }

    var qrCodeOutline: some View {
        Image("QRScannerOutline")
            .resizable()
            .frame(width: scanSize, height: scanSize)
    }

    private func handleModeChange(_ newMode: ScannerMode) {
        switch newMode {
        case .camera:
            screenCaptureService.stopCapture()
            startCamera()
        case .screen:
            stopCamera()
            Task {
                await screenCaptureService.startCapture()
            }
        }
    }

    private func handleModeVisible() {
        switch scannerMode {
        case .camera:
            startCamera()
        case .screen:
            Task {
                await screenCaptureService.startCapture()
            }
        }
    }

    private func handleModeHidden() {
        stopCamera()
        screenCaptureService.stopCapture()
    }

    private func startCamera() {
        cameraViewModel.setupSession()
        cameraViewModel.startSession()
    }

    private func stopCamera() {
        cameraViewModel.stopSession()
        cameraViewModel.resetData()
    }

    private func getScanner(_ session: AVCaptureSession) -> some View {
        VStack(spacing: 0) {
            Spacer()
            qrCodeOutline
            Spacer()
            uploadQRCodeButton
        }
        .frame(maxHeight: .infinity)
        .padding(40)
        .background(MacCameraPreview(session: session))
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
