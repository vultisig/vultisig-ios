//
//  AddAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import SwiftData
import WalletCore

struct AddAddressBookView: View {
    let count: Int
    
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State var title = ""
    @State var address = ""
    @State var coin: CoinMeta? = nil
    
    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
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
            addAddress()
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
        guard let vault = homeViewModel.selectedVault else {
            return
        }
        
        coinSelectionViewModel.setData(for: vault)
        
        if coin == nil {
            let key = coinSelectionViewModel.groupedAssets.keys.sorted().first ?? ""
            coin = coinSelectionViewModel.groupedAssets[key]?.first
        }
    }
    
    private func addAddress() {
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
    
    private func validateAddress(coin: CoinMeta, address: String) -> Bool {
        
        if address.isNameService() {
            return true
        }
        
        
        if coin.chain == .mayaChain {
            return AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya")
        }
        return coin.coinType.validate(address: address)
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
    AddAddressBookView(count: 0)
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(HomeViewModel())
}
