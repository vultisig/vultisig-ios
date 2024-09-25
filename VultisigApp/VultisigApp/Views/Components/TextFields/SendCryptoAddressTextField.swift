//
//  AddressTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-15.
//

import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct SendCryptoAddressTextField: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var sendCryptoViewModel: SendCryptoViewModel
    
    @State var showScanner = false
    @State var showImagePicker = false
    @State var isUploading: Bool = false
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        container
    }
    
    var content: some View {
        field
            .overlay {
                ZStack {
                    if isUploading {
                        overlay
                    }
                }
            }
    }
    
    var overlay: some View {
        ZStack {
            Color.turquoise600.opacity(0.2)
                .frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(10)
            
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 1, dash: [10]))
                .padding(5)
            
            Text(NSLocalizedString("dropFileHere", comment: ""))
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
        }
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
    
    var addressBookButton: some View {
        NavigationLink {
            AddressBookView(returnAddress: $tx.toAddress, coin: tx.coin).onDisappear {
                DebounceHelper.shared.debounce {
                    validateAddress(tx.toAddress)
                }
            }
        } label: {
            Image(systemName: "text.book.closed")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
}

#Preview {
    SendCryptoAddressTextField(tx: SendTransaction(), sendCryptoViewModel: SendCryptoViewModel())
}

