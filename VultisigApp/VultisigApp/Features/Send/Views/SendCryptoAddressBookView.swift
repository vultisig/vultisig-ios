//
//  SendCryptoAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-04.
//

import SwiftUI
import SwiftData

enum SendAddressBookListType: Int, CaseIterable, FilledSegmentedControlType {
    case savedAddresses
    case myVaults

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .savedAddresses:
            return "savedAddresses".localized
        case .myVaults:
            return "myVaults".localized
        }
    }
}

struct SendCryptoAddressBookView: View {
    let coin: Coin
    @Binding var showSheet: Bool
    var onSelectAddress: (String) -> Void

    @State var selectedListType: SendAddressBookListType = .savedAddresses
    @State var myAddresses: [(id: UUID, title: String, description: String)] = []

    @Query var vaults: [Vault]
    @Query var savedAddresses: [AddressBookItem]

    var filteredSavedAddresses: [AddressBookItem] {
        savedAddresses
            .filter { (AddressBookChainType(coinMeta: $0.coinMeta) == AddressBookChainType(coinMeta: coin.toCoinMeta()) || $0.coinMeta.chain == coin.chain) }
    }

    var body: some View {
        Screen {
            VStack(spacing: 12) {
                listSelector
                list
            }
        }
        .screenTitle("addressBook".localized)
        .presentationDetents([.medium, .large])
        .applySheetSize()
    }

    var listSelector: some View {
        FilledSegmentedControl(
            selection: $selectedListType,
            options: SendAddressBookListType.allCases,
            size: .small
        )
    }

    var list: some View {
        ScrollView {
            switch selectedListType {
            case .savedAddresses:
                if !savedAddresses.isEmpty {
                    savedAddressesList
                } else {
                    errorMessage
                }
            case .myVaults:
                if !vaults.isEmpty {
                    myAddressesList
                } else {
                    errorMessage
                }
            }
        }
    }

    var savedAddressesList: some View {
        VStack(spacing: 12) {
            ForEach(filteredSavedAddresses) { address in
                SendCryptoAddressBookCell(
                    title: address.title,
                    description: address.address,
                    icon: logo(for: address)
                ) {
                    onSelectAddress($0)
                    showSheet = false
                }
            }
        }
        .padding(.top, 12)
    }

    func logo(for address: AddressBookItem) -> String {
        switch address.coinMeta.chain.type {
        case .EVM:
            return coin.chain.logo
        default:
            return address.coinMeta.logo
        }
    }

    var myAddressesList: some View {
        VStack(spacing: 12) {
            ForEach(myAddresses, id: \.id) { address in
                SendCryptoAddressBookCell(
                    title: address.title,
                    description: address.description,
                    icon: nil
                ) {
                    onSelectAddress($0)
                    showSheet = false
                }
            }
        }
        .padding(.top, 12)
        .onAppear {
            filterVaults()
        }
    }

    var errorMessage: some View {
        Text(NSLocalizedString("noSavedAddresses", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundStyle(Theme.colors.textSecondary)
            .padding(.top, 32)
    }

    private func filterVaults() {
        myAddresses = []

        for vault in vaults {
            for vaultCoin in vault.coins {
                if vaultCoin.chain == coin.chain {
                    let title = vault.name
                    let description = vaultCoin.address
                    let vaultTitles = myAddresses.map { address in
                        address.title
                    }
                    let vaultSet = Set(vaultTitles)

                    if !vaultSet.contains(title) {
                        myAddresses.append(
                            (
                                id: UUID(),
                                title: title,
                                description: description
                            )
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    SendCryptoAddressBookView(coin: .example, showSheet: .constant(true)) { _ in }
}
