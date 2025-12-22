//
//  SendCryptoSecondaryDoneView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-09.
//

import SwiftUI
import SwiftData

struct SendCryptoSecondaryDoneView: View {
    @Environment(\.router) var router
    let input: SendCryptoContent

    @State var navigateToAddressBook = false
    @Environment(\.openURL) var openURL
    @State var canShowAddressBook: Bool = false
    @State var addressCountBeforeNavigation: Int = 0

    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var appViewModel: AppViewModel
    
    var showAddressBookButton: Bool {
        input.isSend && canShowAddressBook
    }
    
    var body: some View {
        Screen(title: "transactionDetails".localized) {
            VStack {
                ScrollView {
                    VStack {
                        header
                        summary
                    }
                    .padding(.vertical, 24)
                }
                
                continueButton
            }
        }
        .onLoad {
            let address = input.toAddress
            let addressItemsDescriptor = FetchDescriptor<AddressBookItem>(
                predicate: #Predicate { $0.address == address }
            )
            let addressItems = try? modelContext.fetch(addressItemsDescriptor)

            canShowAddressBook = addressItems?.isEmpty ?? false && !(appViewModel.selectedVault?.coins.map(\.address).contains(input.toAddress) ?? true)
        }
        .onChange(of: navigateToAddressBook) { _, shouldNavigate in
            if shouldNavigate {
                // Store address count before navigation
                let allAddressesDescriptor = FetchDescriptor<AddressBookItem>()
                addressCountBeforeNavigation = (try? modelContext.fetch(allAddressesDescriptor).count) ?? 0

                router.navigate(to: SettingsRoute.addAddressBook(
                    address: input.toAddress,
                    chain: .init(coinMeta: input.coin.toCoinMeta())
                ))
                navigateToAddressBook = false
            } else if addressCountBeforeNavigation > 0 {
                // Check if address was added when returning from navigation
                let allAddressesDescriptor = FetchDescriptor<AddressBookItem>()
                let currentCount = (try? modelContext.fetch(allAddressesDescriptor).count) ?? 0
                if currentCount > addressCountBeforeNavigation {
                    appViewModel.restart()
                    addressCountBeforeNavigation = 0
                }
            }
        }
    }
    
    var header: some View {
        SendCryptoDoneHeaderView(
            coin: input.coin,
            cryptoAmount: input.amountCrypto,
            fiatAmount: input.amountFiat.formatToFiat(includeCurrencySymbol: true)
        )
    }
    
    var summary: some View {
        VStack(spacing: 18) {
            SendCryptoTransactionHashRowView(
                hash: input.hash,
                explorerLink: input.explorerLink,
                showCopy: false,
                showAlert: .constant(false)
            )
            .showIf(input.hash.isNotEmpty)
            
            separator
            
            if let vaultName = appViewModel.selectedVault?.name, vaultName.isNotEmpty {
                SendCryptoTransactionDetailsRow(
                    title: "from",
                    description: vaultName,
                    bracketValue: input.fromAddress
                )
                separator
            }
            
            Group {
                SendCryptoTransactionDetailsRow(
                    title: "to",
                    description: input.toAddress
                ) {
                    addToAddressBookButton
                        .showIf(showAddressBookButton)
                }
                separator
            }
            .showIf(input.toAddress.isNotEmpty)
            
            Group {
                SendCryptoTransactionDetailsRow(
                    title: "memo",
                    description: input.memo
                )
                separator
            }
            .showIf(input.memo.isNotEmpty)
            
            
            SendCryptoTransactionDetailsRow(
                title: "network",
                description: input.coin.chain.name,
                icon: input.coin.chain.logo
            )
            
            separator
            
            SendCryptoTransactionDetailsRow(
                title: "estNetworkFee",
                description: input.fee.crypto,
                secondaryDescription: input.fee.fiat
            )
        }
        .padding(24)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
    
    var separator: some View {
        Separator()
            .opacity(0.8)
    }
    
    var continueButton: some View {
        PrimaryButton(title: "done") {
            appViewModel.restart()
        }
    }
    
    var addToAddressBookButton: some View {
        Button {
            navigateToAddressBook = true
        } label: {
            HStack(spacing: 6) {
                Icon(named: "plus", color: Theme.colors.alertSuccess, size: 16)
                
                Text("addToAddressBook".localized)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.alertSuccess)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 99).stroke(Theme.colors.alertSuccess, lineWidth: 0.5))
            .fixedSize()
        }
    }
    
    func openLink() {
        if let url = URL(string: input.explorerLink) {
            openURL(url)
        }
    }
}

#Preview {
    SendCryptoSecondaryDoneView(
        input: .init(
            coin: .example,
            amountCrypto: "30 RUNE",
            amountFiat: "US$ 200",
            hash: "44B447A6A8BCABCCEC6E3EE9DE366EA4E0CDFC2C0BFB59D51E1A12D27B0C51AB",
            explorerLink: "https://thorchain.net/tx/44B447A6A8BCABCCEC6E3EE9DE366EA4E0CDFC2C0BFB59D51E1A12D27B0C51AB",
            memo: "test",
            isSend: true,
            fromAddress: "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z",
            toAddress: "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z",
            fee: FeeDisplay(crypto: "0.001 RUNE", fiat: "US$ 0.00")
        )
    ).environmentObject(HomeViewModel())
}
