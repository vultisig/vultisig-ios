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
    @State private var showTooltip = false

    private let scanSize: CGFloat = 400

    private let tooltipBullets = [
        "scanQRCodeTooltipBullet1",
        "scanQRCodeTooltipBullet2",
        "scanQRCodeTooltipBullet3"
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Background()
                .showIf(scannerMode == .camera)
            main
        }
        .overlay {
            if showTooltip {
                tooltipDismissLayer
            }
        }
        .overlay(alignment: .topTrailing) {
            HelpTooltip(isPresented: $showTooltip, maxWidth: 360) {
                tooltipContent
            }
            .padding(.trailing, 16)
            .padding(.top, 16)
        }
        .crossPlatformToolbar {
            CustomToolbarItem(placement: .center) {
                FilledSegmentedControl(
                    selection: $scannerMode,
                    options: ScannerMode.allCases,
                    size: .small
                )
                .frame(maxWidth: 220)
            }
            CustomToolbarItem(placement: .trailing) {
                HelpButton(isPresented: $showTooltip)
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
        ZStack {
            MacScreenCapturePreview(scanRegion: screenCaptureService.scanRegion)
                .ignoresSafeArea()
            viewportOverlay
            VStack {
                Spacer()
                uploadQRCodeButton
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
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
        PrimaryButton(title: "uploadQRCode") {
            router.navigate(to: KeygenRoute.generalQRImport(
                type: type,
                selectedVault: selectedVault,
                sendTx: sendTx
            ))
        }
        .fixedSize()
    }

    var tryAgainButton: some View {
        PrimaryButton(title: "tryAgain", type: .secondary) {
            cameraViewModel.setupSession()
        }
    }

    var viewportOverlay: some View {
        GeometryReader { proxy in
            let rect = viewportRect(in: proxy)
            ZStack {
                Path { path in
                    path.addRect(proxy.frame(in: .local))
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 24, height: 24))
                }
                .fill(Theme.colors.bgPrimary.opacity(0.55), style: FillStyle(eoFill: true))

                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.colors.primaryAccent4, lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
            }
        }
        .allowsHitTesting(false)
    }

    private func viewportRect(in proxy: GeometryProxy) -> CGRect {
        let maxSize = min(proxy.size.width, proxy.size.height) - 120
        let size = min(scanSize, max(maxSize, 0))
        let topOffset = max((proxy.size.height - size) / 2 - 30, 0)
        return CGRect(
            x: (proxy.size.width - size) / 2,
            y: topOffset,
            width: size,
            height: size
        )
    }

    private var tooltipDismissLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.interpolatingSpring) {
                    showTooltip = false
                }
            }
    }

    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("scanQRCodeTooltipTitle".localized)
                .font(Theme.fonts.bodySMedium)
            VStack(alignment: .leading, spacing: 4) {
                Text("scanQRCodeTooltipSubtitle".localized)
                    .font(Theme.fonts.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(tooltipBullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(Theme.fonts.footnote)
                        Text(bullet.localized)
                            .font(Theme.fonts.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
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
        ZStack {
            MacCameraPreview(session: session)
            viewportOverlay
            VStack {
                Spacer()
                uploadQRCodeButton
                    .padding(.bottom, 40)
            }
        }
        .clipShape(Rectangle())
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
