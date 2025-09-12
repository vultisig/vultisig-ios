//
//  SendCryptoAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-04.
//

import SwiftUI
import SwiftData

struct SendCryptoAddressBookView: View {
    @ObservedObject var tx: SendTransaction
    @Binding var showSheet: Bool
    
    @State var isSavedAddressesSelected: Bool = true
    @State var myAddresses: [(id: UUID, title: String, description: String)] = []
    
    @Query var vaults: [Vault]
    @Query var savedAddresses: [AddressBookItem]
    
    var filteredSavedAddresses: [AddressBookItem] {
        savedAddresses
            .filter { $0.coinMeta.chain == tx.coin.chain  }
    }
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .buttonStyle(BorderlessButtonStyle())
        .presentationDetents([.medium, .large])
    }
    
    var title: some View {
        Text(NSLocalizedString("addressBook", comment: ""))
            .font(Theme.fonts.bodyMMedium)
            .foregroundColor(Theme.colors.textPrimary)
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
    }
    
    var myVaultsButton: some View {
        Button {
            isSavedAddressesSelected = false
        } label: {
            getCell(for: "myVaults", isSelected: !isSavedAddressesSelected)
        }
    }
    
    var list: some View {
        ScrollView {
            if isSavedAddressesSelected {
                if savedAddresses.count > 0 {
                    savedAddressesList
                } else {
                    errorMessage
                }
            } else {
                if vaults.count > 0 {
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
                    icon: logo(for: address),
                    tx: tx,
                    showSheet: $showSheet
                )
            }
        }
    }
    
    func logo(for address: AddressBookItem) -> String {
        switch address.coinMeta.chain.type {
        case .EVM:
            return tx.coin.chain.logo
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
                    icon: nil,
                    tx: tx,
                    showSheet: $showSheet
                )
            }
        }
        .onAppear {
            filterVaults()
        }
    }
    
    var errorMessage: some View {
        Text(NSLocalizedString("noSavedAddresses", comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textLight)
            .padding(.top, 32)
    }
    
    private func getCell(for title: String, isSelected: Bool) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.textLight)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? Theme.colors.bgButtonTertiary : .clear)
            .cornerRadius(60)
    }
    
    private func filterVaults() {
        myAddresses = []
        
        for vault in vaults {
            for coin in vault.coins {
                if coin.chain == tx.coin.chain {
                    let title = vault.name
                    let description = coin.address
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
    SendCryptoAddressBookView(tx: SendTransaction(), showSheet: .constant(true))
}
