//
//  AddressTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension AddressTextField {
    var content: some View {
        ZStack(alignment: .trailing) {
            field
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .sheet(isPresented: $showScanner) {
            codeScanner
        }
        .sheet(isPresented: $showImagePicker, onDismiss: processImage) {
            ImagePicker(selectedImage: $selectedImage)
        }
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterContractAddress", comment: "").toFormattedTitleCase(), text: $contractAddress)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
                .disableAutocorrection(true)
                .textContentType(.oneTimeCode)
                .maxLength($contractAddress)
                .onChange(of: contractAddress){oldValue,newValue in
                    validateAddress(newValue)
                }
                .borderlessTextFieldStyle()
                .textInputAutocapitalization(.never)
                .keyboardType(.default)
            
            pasteButton
            
            if showScanIcon {
                scanButton
            }

            if showAddressBookIcon {
                addressBookButton
            }
        }
    }
    
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, handleScan: handleScan)
    }
    
    private func processImage() {
        guard let selectedImage = selectedImage else { return }
        handleImageQrCode(image: selectedImage)
    }
    
    func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            contractAddress = clipboardContent
            validateAddress(clipboardContent)
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            contractAddress = qrCodeResult
            validateAddress(qrCodeResult)
            showScanner = false
        case .failure(let err):
            // Handle the error appropriately
            print("Failed to scan QR code: \(err.localizedDescription)")
        }
    }
    
    private func handleImageQrCode(image: UIImage) {
        if let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image) as Data?,
           let qrCodeString = String(data: qrCodeFromImage, encoding: .utf8) {
            contractAddress = qrCodeString
            validateAddress(qrCodeString)
        }
    }
}
#endif
