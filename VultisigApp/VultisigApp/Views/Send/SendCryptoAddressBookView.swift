//
//  SendCryptoAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-04.
//

import SwiftUI
import SwiftData

struct SendCryptoAddressBookView: View {
    @State var isSavedAddressesSelected: Bool = true
    
    @Query var savedAddresses: [AddressBookItem]
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .presentationDetents([.medium, .large])
    }
    
    var content: some View {
        VStack(spacing: 12) {
            title
            listSelector
            list
        }
        .padding(16)
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
                savedAddressesList
            } else {
                
            }
        }
    }
    
    var savedAddressesList: some View {
        ForEach(savedAddresses) { address in
            SendCryptoAddressBookCell(
                title: address.title,
                description: address.address,
                icon: address.coinMeta.logo
            )
        }
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
}

#Preview {
    SendCryptoAddressBookView()
}
