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
            .font(.body16MontserratMedium)
            .foregroundColor(.neutral0)
    }
    
    var listSelector: some View {
        HStack {
            savedAddressesButton
            myVaultsButton
        }
        .animation(.easeInOut, value: isSavedAddressesSelected)
        .overlay(
            RoundedRectangle(cornerRadius: 60)
                .stroke(Color.borderBlue, lineWidth: 1)
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
            ForEach(savedAddresses) { address in
                if address.coinMeta.chain != tx.coin.chain {
                    continue
                }
                SendCryptoAddressBookCell(
                    title: address.title,
                    description: address.address,
                    icon: address.coinMeta.logo,
                    tx: tx,
                    showSheet: $showSheet
                )
            }
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
            .font(.body14BrockmannMedium)
            .foregroundColor(.lightText)
            .padding(.top, 32)
    }
    
    private func getCell(for title: String, isSelected: Bool) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body14BrockmannMedium)
            .foregroundColor(.lightText)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? Color.persianBlue400 : .clear)
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
