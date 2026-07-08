//
//  TransactionDetailsCard.swift
//  VultisigApp
//
//  Header-less, button-less transaction detail rows revealed when the
//  Done screen's "Transaction details" section is expanded in place.
//  Owns the add-to-address-book flow. The status header and the tx hash
//  row are already rendered by `DoneScreen`, so neither is duplicated
//  here.
//

import SwiftData
import SwiftUI

struct TransactionDetailsCard: View {
    @Environment(\.router) var router
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var appViewModel: AppViewModel

    let input: TransactionDonePayload

    @State private var navigateToAddressBook = false
    @State private var canShowAddressBook: Bool = false
    @State private var addressCountBeforeNavigation: Int = 0

    private var showAddressBookButton: Bool {
        input.isSend && canShowAddressBook
    }

    var body: some View {
        VStack(spacing: 18) {
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
                    description: input.toAlias ?? input.toAddress,
                    bracketValue: input.toAlias != nil ? input.toAddress : nil
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

            Group {
                if let signDirect = input.keysignPayload?.signDirect {
                    separator
                    SignDirectDisplayView(signDirect: signDirect)
                } else if let signAmino = input.keysignPayload?.signAmino {
                    separator
                    SignAminoDisplayView(signAmino: signAmino)
                }
            }
        }
        .onLoad {
            let address = input.toAddress.lowercased()
            let coinChainType = AddressBookChainType(coinMeta: input.coin.toCoinMeta())
            let allItemsDescriptor = FetchDescriptor<AddressBookItem>()
            let allItems = try? modelContext.fetch(allItemsDescriptor)
            let isInAddressBook = allItems?.contains {
                $0.address.lowercased() == address &&
                AddressBookChainType(coinMeta: $0.coinMeta) == coinChainType
            } ?? false

            // Suppress "add to address book" if destination belongs to any vault or is already in address book
            canShowAddressBook = !isInAddressBook && input.toAlias == nil
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

    private var separator: some View {
        Separator()
            .opacity(0.8)
    }

    private var addToAddressBookButton: some View {
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
}
