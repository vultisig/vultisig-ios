//
//  KeygenQRImportMacView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI
import SwiftData

struct GeneralQRImportMacView: View {
    let type: DeeplinkFlowType
    let selectedVault: Vault?
    var onParsedAddress: (String) -> Void

    @State var fileName: String? = nil
    @State var importResult: Result<[URL], Error>? = nil
    @State var isButtonEnabled = false
    @State private var deeplinkError: Error?

#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif

    @Query var vaults: [Vault]

    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel

    var body: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
        .crossPlatformToolbar(getTitle())
        .withError(error: $deeplinkError, errorType: .warning) {}
        .onChange(of: deeplinkError == nil) {
            if deeplinkError == nil {
                resetData()
            }
        }
    }

    var main: some View {
        content
    }

    var content: some View {
        VStack(spacing: 32) {
            title
            uploadSection
            Spacer()
            button
        }
        .padding(40)
    }

    var title: some View {
        Text(getDescription())
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var uploadSection: some View {
        FileQRCodeImporterMac(
            fileName: fileName,
            resetData: resetData,
            handleFileImport: handleFileImport,
            selectedImage: selectedImage
        )
    }

    var button: some View {
        PrimaryButton(title: "continue") {
            handleTap()
        }
        .disabled(!isButtonEnabled)
    }

    private func getTitle() -> String {
        let text: String

        switch type {
        case .NewVault:
            text = "pair"
        case .SignTransaction:
            text = "keysign"
        case .Send:
            text = "scanQRCode"
        case .Unknown:
            text = "scanQRCode"
        }

        return NSLocalizedString(text, comment: "")
    }

    private func getDescription() -> String {
        let text: String

        switch type {
        case .NewVault:
            text = "uploadQRCodeImageKeygen"
        case .SignTransaction:
            text = "uploadQRCodeImageKeysign"
        case .Send:
            text = "uploadFileWithQRCode"
        case .Unknown:
            text = "uploadFileWithQRCode"
        }

        return NSLocalizedString(text, comment: "")
    }

    private func resetData() {
        fileName = nil
        selectedImage = nil
        isButtonEnabled = false
        importResult = nil
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            setValues(urls)
            importResult = result
        case .failure(let error):
            print("Error importing file: \(error.localizedDescription)")
        }
    }

    private func handleTap() {
        guard let importResult else {
            return
        }

        do {
            let qrCode = try Utils.handleQrCodeFromImage(result: importResult)
            let result = String(data: qrCode, encoding: .utf8)

            guard let result, let url = URL(string: result) else {
                return
            }

            try deeplinkViewModel.extractParameters(url, vaults: vaults, isInternal: true)
        } catch {
            deeplinkError = error
        }
    }
}

#Preview {
    GeneralQRImportMacView(type: .NewVault, selectedVault: Vault.example) { _ in }
}
