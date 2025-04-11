//
//  TransactionMemoAddressTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension TransactionMemoAddressTextField {
    var container: some View {
        content
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            TextField(addressKey.toFormattedTitleCase(), text: Binding<String>(
                get: { memo.addressFields[addressKey] ?? "" },
                set: { newValue in
                    memo.addressFields[addressKey] = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .foregroundColor(.neutral0)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .maxLength(Binding<String>(
                get: { memo.addressFields[addressKey] ?? "" },
                set: { newValue in
                    memo.addressFields[addressKey] = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .textInputAutocapitalization(.never)
            .keyboardType(.default)
            .textContentType(.oneTimeCode)
            
            pasteButton
            fileButton
            addressBookButton
        }
        .padding(.horizontal, 12)
    }
    
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, address: binding(for: addressKey), handleScan: handleScan)
    }
    
    private func binding(for key: String) -> Binding<String> {
        return Binding(
            get: { self.memo.addressFields[addressKey, default: ""] },
            set: { self.memo.addressFields[addressKey] = $0 }
        )
    }
    
    func processImage() {
        guard let selectedImage = selectedImage else { return }
        handleImageQrCode(image: selectedImage)
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            memo.addressFields[addressKey] = qrCodeResult
            validateAddress(memo.addressFields[addressKey] ?? "")
            showScanner = false
        case .failure(let err):
            print("Failed to scan QR code, error: \(err.localizedDescription)")
        }
    }
    
    private func handleImageQrCode(image: UIImage) {
        let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image)
        let address = String(data: qrCodeFromImage, encoding: .utf8) ?? ""
        memo.addressFields[addressKey] = address
        validateAddress(memo.addressFields[addressKey] ?? "")
    }
    
    func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            memo.addressFields[addressKey] = clipboardContent
            DebounceHelper.shared.debounce {
                validateAddress(clipboardContent)
            }
        }
    }
}
#endif
