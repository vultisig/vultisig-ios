//
//  AddAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI

struct AddAddressBookView: View {
    let vault: Vault?
    
    @EnvironmentObject var addressBookViewModel: AddressBookViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    
    @State var title = ""
    @State var address = ""
    @State var selectedChain: CoinMeta? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("addAddress", comment: ""))
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
        AddressBookChainSelector(selected: $selectedChain)
    }
    
    var titleField: some View {
        AddressBookTextField(title: "title", text: $title)
    }
    
    var addressField: some View {
        AddressBookTextField(title: "address", text: $address)
    }
    
    var button: some View {
        Button {
            addAddress()
        } label: {
            FilledButton(title: "saveAddress")
                .padding(.bottom, 40)
        }
    }
    
    private func setData() {
        guard let vault else {
            return
        }
        
        coinSelectionViewModel.setData(for: vault)
        
        let chain = coinSelectionViewModel.groupedAssets.first
        selectedChain = chain?.value.first
    }
    
    private func addAddress() {
        guard let selectedChain else {
            return
        }
        
        addressBookViewModel.addNewAddress(
            title: title,
            address: address,
            coinMeta: selectedChain
        )
        
        dismiss()
    }
}

#Preview {
    AddAddressBookView(vault: Vault.example)
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(AddressBookViewModel())
}
