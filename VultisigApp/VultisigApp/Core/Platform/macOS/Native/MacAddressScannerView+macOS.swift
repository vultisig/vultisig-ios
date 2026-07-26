//
//  MacAddressScannerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-16.
//

import Foundation

struct AddressResult {
    let address: String
    let memo: String?
    let amount: String?

    init(address: String, memo: String? = nil, amount: String? = nil) {
        self.address = address
        self.memo = memo
        self.amount = amount
    }

    static func fromURI(_ uri: String) -> AddressResult {
        guard URLComponents(string: uri) != nil else {
            // Validate up
            return .init(address: uri)
        }

        let (address, amount, message) = Utils.parseCryptoURI(uri)

        return AddressResult(address: address, memo: message, amount: amount)
    }
}

#if os(macOS)
import SwiftUI
import SwiftData
import AVFoundation

struct MacAddressScannerView: View {
    let selectedVault: Vault?
    @Binding var scannedResult: AddressResult?
    var onParsedResult: ((AddressResult?) -> Void)?

    @StateObject var cameraViewModel = MacCameraServiceViewModel()
    @StateObject var screenCaptureService = MacScreenCaptureService()

    @State private var scannerMode: ScannerMode = .camera
    @State private var showTooltip = false
    @State private var showImportOptions = false
    @State private var importFileName: String?
    @State private var importResult: Result<[URL], Error>?
    @State private var importSelectedImage: NSImage?
    @State private var importError: Error?

    @Environment(\.router) var router

    private let scanSize: CGFloat = 400

    private let tooltipBullets = [
        "scanQRCodeTooltipBullet1",
        "scanQRCodeTooltipBullet2",
        "scanQRCodeTooltipBullet3"
    ]

    init(
        selectedVault: Vault?,
        scannedResult: Binding<AddressResult?> = .constant(nil),
        onParsedResult: ((AddressResult?) -> Void)? = nil
    ) {
        self.selectedVault = selectedVault
        self._scannedResult = scannedResult
        self.onParsedResult = onParsedResult
    }

    var body: some View {
        ZStack(alignment: .top) {
            Background()
                .showIf(scannerMode == .camera || showImportOptions)
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
        .crossPlatformToolbar(
            navigationTitle: showImportOptions ? "scanQRCode".localized : nil,
            showsBackButton: !showImportOptions
        ) {
            if showImportOptions {
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: .chevronRight, action: closeImportOptions)
                        .rotationEffect(.radians(.pi))
                }
            } else {
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
        }
        .onChange(of: screenCaptureService.detectedQRCode) { _, newValue in
            guard let newValue = newValue, !newValue.isEmpty else { return }
            screenCaptureService.stopCapture()
            handleScan(newValue)
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

    @ViewBuilder
    var main: some View {
        if showImportOptions {
            importOption
        } else {
            scannerContent
                .onChange(of: cameraViewModel.detectedQRCode) { _, newValue in
                    guard let newValue = newValue, !newValue.isEmpty else { return }
                    handleScan(newValue)
                }
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
                    .foregroundStyle(Theme.colors.textPrimary)

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

    var importOption: some View {
        VStack(spacing: 32) {
            Text("uploadFileWithQRCode".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            FileQRCodeImporterMac(
                fileName: importFileName,
                resetData: resetImportData,
                handleFileImport: handleFileImport,
                selectedImage: importSelectedImage
            )

            Spacer()

            PrimaryButton(title: "continue") {
                handleImportContinue()
            }
            .disabled(importResult == nil)
        }
        .padding(40)
        .withError(error: $importError, errorType: .warning) {
            importError = nil
        }
    }

    var uploadQRCodeButton: some View {
        PrimaryButton(title: "uploadQRCode") {
            stopCamera()
            screenCaptureService.stopCapture()
            showImportOptions = true
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

    private func handleScan(_ qrCode: String) {
        let result = AddressResult.fromURI(qrCode)
        scannedResult = result
        onParsedResult?(result)
        goBack()
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            setImportValues(urls)
            importResult = result
        case .failure(let error):
            importError = error
        }
    }

    private func setImportValues(_ urls: [URL]) {
        guard let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        importFileName = url.lastPathComponent
        if let image = NSImage(contentsOf: url) {
            importSelectedImage = image
        }
    }

    private func resetImportData() {
        importFileName = nil
        importSelectedImage = nil
        importResult = nil
    }

    private func handleImportContinue() {
        guard let importResult else { return }
        do {
            let qrData = try Utils.handleQrCodeFromImage(result: importResult)
            guard let qrString = String(data: qrData, encoding: .utf8), !qrString.isEmpty else { return }
            handleScan(qrString)
        } catch {
            importError = error
        }
    }

    private func closeImportOptions() {
        resetImportData()
        showImportOptions = false
        handleModeVisible()
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

    private func goBack() {
        handleModeHidden()
        showImportOptions = false
        router.navigateBack()
    }
}

#Preview {
    MacAddressScannerView(selectedVault: Vault.example) { _ in }
}
#endif
