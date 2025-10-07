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
    var onDismiss: (() -> Void)?
    
    @Query var savedAddresses: [AddressBookItem]
    
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State var title = ""
    @State var address: String
    @State var selectedChain: AddressBookChainType
    
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    @State var presentSelector = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
    init(address: String? = nil, chain: AddressBookChainType? = nil, onDismiss: (() -> Void)? = nil) {
        self.address = address ?? ""
        self.selectedChain = chain ?? .evm
        self.onDismiss = onDismiss
    }
    
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
        .crossPlatformSheet(isPresented: $presentSelector) {
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
        
        // Check for duplicates
        let fetchDescriptor = FetchDescriptor<AddressBookItem>(
            predicate: #Predicate { $0.address == address}
        )
        let existingItems = try? modelContext.fetch(fetchDescriptor)
        let filteredItems = existingItems?.filter { item in
            item.coinMeta.chain == selectedChain.chain
        }
        if let items = filteredItems, !items.isEmpty {
            toggleAlertAddressAlreadyExists()
            return
        }
        guard let coin = coinSelectionViewModel.groupedAssets[selectedChain.chain]?.first else {
            return
        }
        
        let data = AddressBookItem(
            title: title,
            address: address,
            coinMeta: coin,
            order: savedAddresses.count
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            modelContext.insert(data)
            if let onDismiss {
                onDismiss()
            } else {
                dismiss()
            }
        }
    }
    
    private func toggleAlert() {
        alertTitle = "emptyField"
        alertMessage = "checkEmptyField"
        showAlert = true
    }
    
    private func toggleAlertAddressAlreadyExists() {
        alertTitle = "error"
        alertMessage = "addressBookDuplicate"
        showAlert = true
    }
    
    private func toggleAlertInvalidAddress() {
        alertTitle = "error"
        alertMessage = "invalidAddressChain"
        showAlert = true
    }
}

#Preview {
    AddAddressBookScreen()
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
