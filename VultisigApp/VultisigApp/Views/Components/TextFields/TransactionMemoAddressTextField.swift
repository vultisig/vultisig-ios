//
//  TransactionMemoAddressTextField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//
import SwiftUI
import Foundation
import OSLog
import UniformTypeIdentifiers
import WalletCore

struct TransactionMemoAddressTextField<MemoType: TransactionMemoAddressable>: View {
    @ObservedObject var memo: MemoType
    var addressKey: String
    var isOptional: Bool = false
        
    @Binding var isAddressValid: Bool
    @State var showScanner = false
    @State var showImagePicker = false
    @State var isUploading: Bool = false
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(addressKey.toFormattedTitleCase())\(optionalMessage)")
                    .font(.body14MontserratMedium)
                    .foregroundColor(.neutral0)
                
                if !isAddressValid {
                    Text("*")
                        .font(.body14MontserratMedium)
                        .foregroundColor(.red)
                }
            }
            
            container
        }
        .onChange(of: memo.addressFields[addressKey]) { oldValue, newValue in
            validateAddress(newValue ?? "")
        }
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
            AddressBookView(returnAddress: Binding<String>(
                get: { memo.addressFields[addressKey] ?? "" },
                set: { newValue in
                    memo.addressFields[addressKey] = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
        } label: {
            Image(systemName: "text.book.closed")
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
    
    func validateAddress(_ newValue: String) {
        
        if isOptional, newValue.isEmpty {
            isAddressValid = true
            return
        }
        
        isAddressValid = AddressService.validateAddress(address: newValue, chain: .thorChain) ||
        AddressService.validateAddress(address: newValue, chain: .mayaChain) ||
        AddressService.validateAddress(address: newValue, chain: .ton)
    }
}
