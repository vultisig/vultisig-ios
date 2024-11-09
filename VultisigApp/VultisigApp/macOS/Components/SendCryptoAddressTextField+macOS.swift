//
//  SendCryptoAddressTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

extension SendCryptoAddressTextField {
    var container: some View {
        content
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue600)
            .cornerRadius(10)
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
            .font(.body12MenloBold)
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
            
            pasteButton
            fileButton
            addressBookButton
        }
        .padding(.horizontal, 12)
    }
    
    func pasteAddress() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            tx.toAddress = clipboardContent
            
            DebounceHelper.shared.debounce {
                validateAddress(clipboardContent)
            }
        }
    }
    
    private func handleImageQrCode(data: Data) {
        let (address, amount, message) = Utils.parseCryptoURI(String(data: data, encoding: .utf8) ?? .empty)
        
        tx.toAddress = address
        tx.amount = amount
        tx.memo = message
        
        DebounceHelper.shared.debounce {
            validateAddress(address)
        }
        
        Task{
            if !amount.isEmpty {
                await sendCryptoViewModel.convertToFiat(newValue: amount, tx: tx)
            }
        }
    }
}
#endif
