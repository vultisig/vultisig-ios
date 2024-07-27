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
    @State var showAlert = false
    @State var showAlertInvalidAddress = false
    @State var coin: CoinMeta? = nil
    
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
        .alert(isPresented: $showAlertInvalidAddress) {
            alertInvalidAddress
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
            title: Text(NSLocalizedString("emptyField", comment: "")),
            message: Text(NSLocalizedString("checkEmptyField", comment: "")),
            dismissButton: .default(Text(NSLocalizedString("ok", comment: "")))
        )
    }
    
    var alertInvalidAddress: Alert {
        Alert(
            title: Text(NSLocalizedString("error", comment: "")),
            message: Text(NSLocalizedString("invalidAddress", comment: "")),
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
        
        guard validateAddress(coin: coin, address: address) else {
            toggleAlertInvalidAddress()
            return
        }
        
        addressBookItem.title = title
        addressBookItem.address = address
        addressBookItem.coinMeta = coin
        
        dismiss()
    }
    
    private func validateAddress(coin: CoinMeta, address: String) -> Bool {
        if coin.chain == .mayaChain {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        }
        return coin.coinType.validate(address: address)
    }
    
    private func toggleAlert() {
        showAlert = true
    }
    
    private func toggleAlertInvalidAddress() {
        showAlertInvalidAddress = true
    }
}

#Preview {
    EditAddressBookView(addressBookItem: AddressBookItem.example)
}
