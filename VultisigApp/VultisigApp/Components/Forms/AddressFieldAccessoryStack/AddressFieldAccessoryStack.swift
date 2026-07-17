//
//  AddressFieldAccessoryStack.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import CodeScanner
#endif

struct AddressFieldAccessoryStack: View {
    @Environment(\.router) var router
    let coin: Coin
    var onResult: (AddressResult?) -> Void

    @State var showScanner = false
    @State var isUploading: Bool = false
    @State var showAddressBookSheet: Bool = false
    @State var scannerResultId: UUID? = nil

#if os(iOS)
    @State var showImagePicker = false
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @ObservedObject var scannerResultManager = ScannerResultManager.shared
#endif

    var body: some View {
        HStack(spacing: 8) {
            AddressFieldAccessoryButton(icon: .copies3Filled) {
                pasteAddress()
            }
            AddressFieldAccessoryButton(icon: .cameraFilled) {
                showScanner.toggle()
            }
            AddressFieldAccessoryButton(icon: .bookmarks) {
                showAddressBookSheet.toggle()
            }
        }
        .crossPlatformSheet(isPresented: $showAddressBookSheet) {
            SendCryptoAddressBookView(coin: coin, showSheet: $showAddressBookSheet) {
                onResult(.init(address: $0))
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showImagePicker, onDismiss: processImage) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .crossPlatformSheet(isPresented: $showScanner) {
            AddressQRCodeScannerView(
                showScanner: $showScanner,
                onAddress: { handleScan(result: $0) }
            )
        }
        #else
        .onDrop(of: [.image], isTargeted: $isUploading) { providers -> Bool in
            OnDropQRUtils.handleOnDrop(providers: providers, handleImageQrCode: handleImageQrCode)
        }
        .onChange(of: showScanner) { _, shouldNavigate in
            guard shouldNavigate else { return }
            presentScanner()
        }
        .onChange(of: scannedAddress) { _, _ in
            deliverScannedResult()
        }
        #endif
    }

    func pasteAddress() {
        if let clipboardContent = ClipboardManager.pasteFromClipboard() {
            onResult(AddressResult(address: clipboardContent))
        }
    }
}

#if os(iOS)
private extension AddressFieldAccessoryStack {
    func handleScan(result: String) {
        onResult(.fromURI(result))
        showScanner = false
    }

    func processImage() {
        guard let selectedImage = selectedImage else { return }
        handleImageQrCode(image: selectedImage)
    }

    func handleImageQrCode(image: UIImage) {
        let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image)
        onResult(.fromURI(String(data: qrCodeFromImage, encoding: .utf8) ?? .empty))
    }
}
#else
private extension AddressFieldAccessoryStack {
    /// The address of the scan result currently pending delivery, if any. Observing
    /// `scannerResultManager` re-renders this view when the pushed scanner stores a
    /// result, letting `onChange(of: scannedAddress)` deliver it after we return.
    var scannedAddress: String? {
        guard let scannerResultId else { return nil }
        return scannerResultManager.getResult(for: scannerResultId)?.address
    }

    func presentScanner() {
        let resultId = UUID()
        scannerResultId = resultId
        router.navigate(to: KeygenRoute.macAddressScanner(
            selectedVault: nil,
            resultId: resultId
        ))
        showScanner = false
    }

    func deliverScannedResult() {
        guard let scannerResultId,
              let result = scannerResultManager.getResult(for: scannerResultId) else { return }
        onResult(result)
        scannerResultManager.clearResult(for: scannerResultId)
        self.scannerResultId = nil
    }

    func handleImageQrCode(data: Data) {
        onResult(.fromURI(String(data: data, encoding: .utf8) ?? .empty))
    }
}
#endif

#Preview {
    AddressFieldAccessoryStack(coin: .example) { _ in }
}
