//
//  AddressTextField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//
import SwiftUI
import Foundation
import OSLog
import UniformTypeIdentifiers
import WalletCore

#if os(iOS)
import CodeScanner
#endif

struct TransactionMemoAddressTextField<MemoType: TransactionMemoAddressable>: View {
    @ObservedObject var memo: MemoType
    var addressKey: String
    var isOptional: Bool = false
    
    @Binding var isAddressValid: Bool
    @State var showScanner = false
    @State var showImagePicker = false
    @State var selectedImage: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack{
                Text("\(addressKey.toFormattedTitleCase())\(optionalMessage)")
                    .font(.body14MontserratMedium)
                    .foregroundColor(.neutral0)
                
                if !isAddressValid {
                    Text("*")
                        .font(.body14MontserratMedium)
                        .foregroundColor(.red)
                }
            }
            
            ZStack(alignment: .trailing) {
                if memo.addressFields[addressKey]?.isEmpty ?? true {
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
        .onChange(of: memo.addressFields[addressKey]) { oldValue,newValue in
            validateAddress(newValue ?? "")
        }
    }
    
    var placeholder: some View {
        Text(addressKey.toFormattedTitleCase())
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
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
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.default)
            .textContentType(.oneTimeCode)
#endif
            
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
    
    var optionalMessage: String {
        if isOptional {
            return " (optional)"
        }
        return .empty
    }
    
    private func processImage() {
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
            // Log the error using the depositViewModel.logger or handle it appropriately
            print("Failed to scan QR code, error: \(err.localizedDescription)")
        }
    }
    
    private func validateAddress(_ newValue: String) {
        
        if isOptional, newValue.isEmpty {
            isAddressValid = true
            return
        }
        
        isAddressValid = CoinType.thorchain.validate(address: newValue) ||
        AnyAddress.isValidBech32(string: newValue, coin: .thorchain, hrp: "maya")
    }
    
    private func pasteAddress() {
#if os(iOS)
        if let clipboardContent = UIPasteboard.general.string {
            memo.addressFields[addressKey] = clipboardContent
            validateAddress(memo.addressFields[addressKey] ?? "")
        }
#endif
    }
    
    private func handleImageQrCode(image: UIImage) {
        let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image)
        let address = String(data: qrCodeFromImage, encoding: .utf8) ?? ""
        memo.addressFields[addressKey] = address
        validateAddress(memo.addressFields[addressKey] ?? "")
    }
}
