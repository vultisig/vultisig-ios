//
//  EditAddressBookScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-27.
//

import SwiftUI
import WalletCore

struct EditAddressBookScreen: View {
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel

    let addressBookItem: AddressBookItem

    @State var title = ""
    @State var address = ""
    @State var selectedChain: AddressBookChainType = .evm

    @State var alertTitle = ""
    @State var alertMessage = ""
    @State var showAlert = false
    @State var presentSelector = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    var body: some View {
        Screen {
            VStack {
                fields
                Spacer()
                button
            }
        }
        .screenTitle("editAddress".localized)
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
        AddressBookTextField(title: "title", text: $title)
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
        PrimaryButton(title: "saveAddress") {
            saveAddress()
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
        selectedChain = .init(coinMeta: addressBookItem.coinMeta)
    }

    private func saveAddress() {
        guard !title.isEmpty && !address.isEmpty else {
            toggleAlert()
            return
        }

        guard AddressService.validateAddress(address: address, chain: selectedChain.chain) else {
            toggleAlertInvalidAddress()
            return
        }

        let coin = coinSelectionViewModel.groupedAssets[selectedChain.chain]?.first
        guard let coin else { return }

        addressBookItem.title = title
        addressBookItem.address = address
        addressBookItem.coinMeta = coin
        try? modelContext.save()

        dismiss()
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
    EditAddressBookScreen(addressBookItem: AddressBookItem.example)
}
