//
//  SendCryptoAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-04.
//

import SwiftUI
import SwiftData

struct SendCryptoAddressBookView: View {
    let coin: Coin
    @Binding var showSheet: Bool
    var onSelectAddress: (String) -> Void

    @State var isSavedAddressesSelected: Bool = true
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
        HStack {
            savedAddressesButton
            myVaultsButton
        }
        .animation(.easeInOut, value: isSavedAddressesSelected)
        .overlay(
            RoundedRectangle(cornerRadius: 60)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .padding(.top, 12)
    }

    var savedAddressesButton: some View {
        Button {
            isSavedAddressesSelected = true
        } label: {
            getCell(for: "savedAddresses", isSelected: isSavedAddressesSelected)
        }
        .buttonStyle(.plain)
    }

    var myVaultsButton: some View {
        Button {
            isSavedAddressesSelected = false
        } label: {
            getCell(for: "myVaults", isSelected: !isSavedAddressesSelected)
        }
        .buttonStyle(.plain)
    }

    var list: some View {
        ScrollView {
            if isSavedAddressesSelected {
                if !savedAddresses.isEmpty {
                    savedAddressesList
                } else {
                    errorMessage
                }
            } else {
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
        .onAppear {
            filterVaults()
        }
    }

    var errorMessage: some View {
        Text(NSLocalizedString("noSavedAddresses", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textSecondary)
            .padding(.top, 32)
    }

    private func getCell(for title: String, isSelected: Bool) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? Theme.colors.bgButtonTertiary : .clear)
            .cornerRadius(60)
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
