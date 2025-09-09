//
//  AddAddressBookScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import SwiftData
import WalletCore

struct AddAddressBookScreen: View {
    let count: Int
    
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State var title = ""
    @State var address = ""
    @State var selectedChain = AddressBookChainType.evm
    
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    @State var presentSelector = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        Screen(title: "addAddress".localized) {
            VStack {
                fields
                Spacer()
                button
            }
        }
        .onLoad(perform: setData)
        .alert(isPresented: $showAlert) {
            alert
        }
        .platformSheet(isPresented: $presentSelector) {
            let coins = coinSelectionViewModel.groupedAssets.keys
                .compactMap { coinSelectionViewModel.groupedAssets[$0]?.first }
            AddressBookChainSelectionScreen(
                selectedChain: $selectedChain,
                isPresented: $presentSelector,
                vaultChains: coins
            )
        }
    }
    
    var fields: some View {
        ScrollView {
            VStack(spacing: 12) {
                tokenSelector
                titleField
                addressField
            }
        }
    }
    
    @ViewBuilder
    var tokenSelector: some View {
        AddressBookChainSelector(selectedChain: $selectedChain, presentSelector: $presentSelector)
    }
    
    var titleField: some View {
        AddressBookTextField(title: "label", text: $title)
    }
    
    var addressField: some View {
        AddressBookTextField(
            title: "address",
            text: $address,
            showActions: true,
            isScrollable: true
        )
    }
    
    var button: some View {
        PrimaryButton(title: "save") {
            addAddress()
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
        guard let vault = homeViewModel.selectedVault else {
            return
        }
        
        coinSelectionViewModel.setData(for: vault)
    }
    
    private func addAddress() {
        guard !title.isEmpty && !address.isEmpty else {
            toggleAlert()
            return
        }
        
        guard AddressService.validateAddress(address: address, chain: selectedChain.chain) else {
            toggleAlertInvalidAddress()
            return
        }
        
        guard let coin = coinSelectionViewModel.groupedAssets[selectedChain.chain]?.first else {
            return
        }
                
        let data = AddressBookItem(
            title: title,
            address: address,
            coinMeta: coin,
            order: count
        )

        DispatchQueue.main.asyncAfter(deadline: .now()) {
            modelContext.insert(data)
            dismiss()
        }
    }
    
    private func toggleAlert() {
        alertTitle = "emptyField"
        alertMessage = "checkEmptyField"
        showAlert = true
    }
    
    private func toggleAlertInvalidAddress() {
        alertTitle = "error"
        alertMessage = "invalidAddressChain"
        showAlert = true
    }
}

#Preview {
    AddAddressBookScreen(count: 0)
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
