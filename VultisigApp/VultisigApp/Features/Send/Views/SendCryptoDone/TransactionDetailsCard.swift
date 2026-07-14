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
    @EnvironmentObject var appViewModel: AppViewModel

    @Query private var addressBookItems: [AddressBookItem]

    let input: TransactionDonePayload

    /// Show the "add to address book" button only for sends to a
    /// destination that isn't already a vault (`toAlias == nil`) and isn't
    /// yet in the address book. Backed by a live `@Query`, so when
    /// `AddAddressBookScreen` saves the entry into the same `modelContext`
    /// the query updates reactively and the button hides on return — no
    /// manual count polling or app restart needed.
    private var showAddressBookButton: Bool {
        guard input.isSend, input.toAlias == nil else { return false }
        let destinationChainType = AddressBookChainType(coinMeta: input.coin.toCoinMeta())
        let normalizedAddress = input.toAddress.lowercased()
        let isInAddressBook = addressBookItems.contains {
            $0.address.lowercased() == normalizedAddress &&
            AddressBookChainType(coinMeta: $0.coinMeta) == destinationChainType
        }
        return !isInAddressBook
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
    }

    private var separator: some View {
        Separator()
            .opacity(0.8)
    }

    private var addToAddressBookButton: some View {
        Button {
            router.navigate(to: SettingsRoute.addAddressBook(
                address: input.toAddress,
                chain: .init(coinMeta: input.coin.toCoinMeta())
            ))
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
