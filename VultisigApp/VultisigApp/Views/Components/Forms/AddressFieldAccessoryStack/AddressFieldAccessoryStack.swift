//
//  AddressFieldAccessoryStack.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/10/2025.
//

import SwiftUI
import OSLog
import UniformTypeIdentifiers
#if os(iOS)
import CodeScanner
#endif

struct AddressFieldAccessoryStack: View {
    let coin: Coin
    var onResult: (AddressResult?) -> Void
    
    @State var showScanner = false
    @State var showImagePicker = false
    @State var isUploading: Bool = false
    @State var showAddressBookSheet: Bool = false
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        HStack(spacing: 8) {
            AddressFieldAccessoryButton(icon: "copy-2") {
                pasteAddress()
            }
            AddressFieldAccessoryButton(icon: "camera") {
#if os(iOS)
                showScanner.toggle()
#else
                showImagePicker.toggle()
#endif
            }
            AddressFieldAccessoryButton(icon: "book") {
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
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                let qrCode = try Utils.handleQrCodeFromImage(result: result)
                handleImageQrCode(data: qrCode)
            } catch {
                print(error)
            }
        }
        .onDrop(of: [.image], isTargeted: $isUploading) { providers -> Bool in
            OnDropQRUtils.handleOnDrop(providers: providers, handleImageQrCode: handleImageQrCode)
        }
        .navigationDestination(isPresented: $showScanner) {
            MacAddressScannerView(
                showCameraScanView: $showScanner,
                selectedVault: nil
            ) {
               onResult($0)
            }
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
    func handleImageQrCode(data: Data) {
        onResult(.fromURI(String(data: data, encoding: .utf8) ?? .empty))
    }
}
#endif

#Preview {
    AddressFieldAccessoryStack(coin: .example) { _ in }
}
