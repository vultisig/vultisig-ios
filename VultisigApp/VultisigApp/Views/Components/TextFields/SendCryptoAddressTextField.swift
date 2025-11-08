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
    var sendDetailsViewModel: SendDetailsViewModel? = nil
    var vault: Vault? = nil
    
    @State var showScanner = false
    @State var showImagePicker = false
    @State var isUploading: Bool = false
    @State var showCameraScanView = false
    @State var showAddressBookSheet: Bool = false
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        VStack(spacing: 16) {
            container
            
            if sendCryptoViewModel.showAddressAlert {
                errorText
            }
            
            buttons
        }
        .crossPlatformSheet(isPresented: $showAddressBookSheet) {
            SendCryptoAddressBookView(tx: tx, showSheet: $showAddressBookSheet)
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
    
    var buttons: some View {
        HStack(spacing: 8) {
            pasteButton
            scanButton
            addressBookButton
        }
    }
    
    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            getButton("square.on.square")
        }
    }
    
   
    
    var fileButton: some View {
        Button {
            showImagePicker.toggle()
        } label: {
            getButton("photo.badge.plus")
        }
    }
    
    var addressBookButton: some View {
        Button {
            showAddressBookSheet.toggle()
        } label: {
            getButton("text.book.closed")
        }
    }
    
    var errorText: some View {
        Text(NSLocalizedString(sendCryptoViewModel.errorMessage, comment: ""))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.alertWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
    
    func getButton(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.bgTertiary, lineWidth: 1)
            )
            .padding(1)
    }
}

#Preview {
    SendCryptoAddressTextField(tx: SendTransaction(), sendCryptoViewModel: SendCryptoViewModel())
}

