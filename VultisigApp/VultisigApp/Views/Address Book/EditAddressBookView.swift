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
    private let addressService = AddressService.shared
    
    @State var title = ""
    @State var address = ""
    @State var coin: CoinMeta? = nil
    
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("editAddress", comment: ""))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
        .onAppear {
            setData()
        }
    }
    
    var view: some View {
        VStack(spacing: 22) {
            content
            button
        }
        .padding(.horizontal, 16)
        .alert(isPresented: $showAlert) {
            alert
        }
    }
    
    var content: some View {
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
        
        guard addressService.validateAddress(address: address, chain: coin.chain) else {
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
