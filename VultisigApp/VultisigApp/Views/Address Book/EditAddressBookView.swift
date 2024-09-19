//
//  EditAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-27.
//

import SwiftUI
import WalletCore

struct EditAddressBookView: View {
    let addressBookItem: AddressBookItem
    
    @State var title = ""
    @State var address = ""
    @State var coin: CoinMeta? = nil
    
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 22) {
                tokenSelector
                titleField
                addressField
            }
            .padding(.top, 30)
        }
    }
    
    var tokenSelector: some View {
        AddressBookChainSelector(selected: $coin)
    }
    
    var titleField: some View {
        AddressBookTextField(title: "title", text: $title)
    }
    
    var addressField: some View {
        AddressBookTextField(title: "address", text: $address, showActions: true)
    }
    
    var button: some View {
        Button {
            saveAddress()
        } label: {
            FilledButton(title: "saveAddress")
                .padding(.bottom, 40)
        }
    }
    
    var alert: Alert {
        Alert(
            title: Text(NSLocalizedString(alertTitle, comment: "")),
            message: Text(NSLocalizedString(alertMessage, comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    private func setData() {
        title = addressBookItem.title
        address = addressBookItem.address
        coin = addressBookItem.coinMeta
    }
    
    private func saveAddress() {
        guard let coin else {
            return
        }
        
        guard !title.isEmpty && !address.isEmpty else {
            toggleAlert()
            return
        }
        
        guard AddressService.validateAddress(address: address, chain: coin.chain) else {
            toggleAlertInvalidAddress()
            return
        }
        
        addressBookItem.title = title
        addressBookItem.address = address
        addressBookItem.coinMeta = coin
        
        dismiss()
    }
    
    private func toggleAlert() {
        alertTitle = "emptyField"
        alertMessage = "checkEmptyField"
        showAlert = true
    }
    
    private func toggleAlertInvalidAddress() {
        alertTitle = "error"
        alertMessage = "invalidAddress"
        showAlert = true
    }
}

#Preview {
    EditAddressBookView(addressBookItem: AddressBookItem.example)
}
