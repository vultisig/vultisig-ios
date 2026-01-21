//
//  FunctionCallAddressTextField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//
import SwiftUI
import Foundation
import OSLog
import UniformTypeIdentifiers
import WalletCore

struct FunctionCallAddressTextField<MemoType: FunctionCallAddressable>: View {
    
    @ObservedObject var memo: MemoType
    var addressKey: String
    var isOptional: Bool = false
        
    @Binding var isAddressValid: Bool
    @State var showScanner = false
    @State var showImagePicker = false
    @State var isUploading: Bool = false
    @State var showAddressBookSheet: Bool = false

    @State var chain: Chain? = nil
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("nodeAddressLabel", comment: "Node Address placeholder") + optionalMessage)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                
                if !isAddressValid {
                    Text("*")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(.red)
                }
            }
            
            container
        }
        .onChange(of: memo.addressFields[addressKey]) { _, newValue in
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
            Theme.colors.bgButtonPrimary.opacity(0.2)
                .frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(10)
            
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.colors.bgButtonPrimary, style: StrokeStyle(lineWidth: 1, dash: [10]))
                .padding(5)
            
            Text(NSLocalizedString("dropFileHere", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }
    
    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            Image(systemName: "camera")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }
    
    var fileButton: some View {
        Button {
            showImagePicker.toggle()
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }
    
    var addressBookButton: some View {
        Button {
            showAddressBookSheet.toggle()
        } label: {
            Image(systemName: "text.book.closed")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }
    
    var optionalMessage: String {
        if isOptional {
            return " " + NSLocalizedString("optional", comment: "Optional field indicator")
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
        
        if let chain = chain, chain.chainType == .Cosmos {
            isAddressValid = AddressService.validateAddress(address: newValue, chain: chain)
        }
    }
}
