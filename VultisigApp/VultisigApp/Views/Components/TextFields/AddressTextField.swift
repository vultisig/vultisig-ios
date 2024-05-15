//
//  AddressTextField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//

import Foundation
import SwiftUI
import OSLog
import CodeScanner
import UniformTypeIdentifiers
import WalletCore

struct AddressTextField: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var depositViewModel: DepositViewModel
    
    @State var showScanner = false
    @State var showImagePicker = false  // State for showing the ImagePicker
    @State var selectedImage: UIImage?  // Store the selected image
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if tx.toAddress.isEmpty {
                placeholder
            }
            
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
    
    var placeholder: some View {
        Text(NSLocalizedString("enterAddress", comment: ""))
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterAddress", comment: "").capitalized, text: Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .foregroundColor(.neutral0)
            .submitLabel(.next)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .keyboardType(.default)
            .textContentType(.oneTimeCode)
            
            pasteButton
            scanButton
            fileButton
        }
    }
    
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, handleScan: handleScan)
    }
    
    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            Image(systemName: "camera")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var fileButton: some View {
        Button {
            showImagePicker.toggle()
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    private func processImage() {
        guard let selectedImage = selectedImage else { return }
        
        
        handleImageQrCode(image: selectedImage)
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            tx.parseCryptoURI(qrCodeResult)
            validateAddress(tx.toAddress)
            showScanner = false
        case .failure(let err):
            depositViewModel.logger.error("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
    
    private func validateAddress(_ newValue: String) {
        CoinType.thorchain.validate(address: newValue)
    }
    
    private func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            tx.toAddress = clipboardContent
            
            DebounceHelper.shared.debounce {
                validateAddress(clipboardContent)
            }
        }
    }
    
    private func handleImageQrCode(image: UIImage) {
        
        let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image)
        let (address, amount, message) = Utils.parseCryptoURI(String(data: qrCodeFromImage, encoding: .utf8) ?? .empty)
        
        tx.toAddress = address
        
        DebounceHelper.shared.debounce {
            validateAddress(address)
        }
        
        
        
    }
}

#Preview {
    SendCryptoAddressTextField(tx: SendTransaction(), sendCryptoViewModel: SendCryptoViewModel())
}

