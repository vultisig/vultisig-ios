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
    @State var showCameraScanView = false
    @State var showAddressBookSheet: Bool = false
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        VStack {
            container
            
            if sendCryptoViewModel.showAddressAlert {
                errorText
            }
            
            buttons
        }
        .sheet(isPresented: $showAddressBookSheet) {
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
            .font(.body12MontserratSemiBold)
            .foregroundColor(.alertYellow)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    func validateAddress(_ newValue: String) {
        sendCryptoViewModel.validateAddress(tx: tx, address: newValue)
    }
    
    func getButton(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.body18BrockmannMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue400, lineWidth: 1)
            )
            .padding(1)
    }
}

#Preview {
    SendCryptoAddressTextField(tx: SendTransaction(), sendCryptoViewModel: SendCryptoViewModel())
}

