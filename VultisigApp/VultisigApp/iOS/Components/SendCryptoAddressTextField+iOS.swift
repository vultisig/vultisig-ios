//
//  SendCryptoAddressTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI
import CodeScanner

extension SendCryptoAddressTextField {
    var container: some View {
        content
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(10)
            .platformSheet(isPresented: $showScanner) {
                codeScanner
            }
            .sheet(isPresented: $showImagePicker, onDismiss: processImage) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(sendCryptoViewModel.showAddressAlert ? Theme.colors.alertWarning : Theme.colors.bgTertiary, lineWidth: 1)
            )
            .padding(1)
    }
    
    var field: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            TextField(NSLocalizedString("enterAddressHere", comment: "").capitalized, text: Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .onChange(of: tx.toAddress) { oldValue, newValue in
                Task {
                    await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
                }
            }
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .maxLength(Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .keyboardType(.default)
            .textInputAutocapitalization(.never)
            .textContentType(.oneTimeCode)
            .frame(minWidth: 200)
            .frame(height: 48)
        }
        .padding(.horizontal, 12)
    }
    
    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            getButton("camera")
        }
    }
    
    var codeScanner: some View {
        AddressQRCodeScannerView(showScanner: $showScanner, address: $tx.toAddress, handleScan: handleScan)
    }
    
    func processImage() {
        guard let selectedImage = selectedImage else { return }
        handleImageQrCode(image: selectedImage)
    }
    
    func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            tx.toAddress = clipboardContent
            
            DebounceHelper.shared.debounce {
                validateAddress(clipboardContent)
            }
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            tx.parseCryptoURI(qrCodeResult)
            validateAddress(tx.toAddress)
            showScanner = false
        case .failure(let err):
            sendCryptoViewModel.logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
    
    private func handleImageQrCode(image: UIImage) {
        let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image)
        let (address, amount, message) = Utils.parseCryptoURI(String(data: qrCodeFromImage, encoding: .utf8) ?? .empty)
        
        tx.toAddress = address
        tx.amount = amount
        tx.memo = message
        
        DebounceHelper.shared.debounce {
            validateAddress(address)
        }
        
        
        if !amount.isEmpty {
            sendCryptoViewModel.convertToFiat(newValue: amount, tx: tx)
        }
        
    }
}
#endif
