//
//  AddressBookCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import SwiftData

// Helper struct for safe decoding
private struct SafeCoinMeta: Decodable {
    let chain: String
    let logo: String
}

struct AddressBookCell: View {
    let address: AddressBookItem
    let shouldReturnAddress: Bool
    let isEditing: Bool
    @Binding var returnAddress: String
    
    @State var isNavigationEnabled = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        label
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)
            .navigationDestination(isPresented: $isNavigationEnabled) {
                EditAddressBookView(addressBookItem: address)
            }
    }
    
    var label: some View {
        HStack(spacing: 8) {
            if isEditing {
                rearrangeIcon
            }
            
            Button {
                handleSelection()
            } label: {
                content
            }
            .disabled(isEditing)
            
            if isEditing {
                deleteIcon
            }
        }
    }
    
    var content: some View {
        HStack(spacing: 12) {
            logo
            text
        }
        .padding(12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    var logo: some View {
        Group {
            if let logoName = getCoinLogo() {
                Image(logoName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(30)
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 32, height: 32)
            }
        }
    }
    
    private func getCoinLogo() -> String? {
        do {
            // Encode and decode to ensure we can access the logo
            let data = try JSONEncoder().encode(address.coinMeta)
            let safeMeta = try JSONDecoder().decode(SafeCoinMeta.self, from: data)
            return safeMeta.logo
        } catch {
            print("Error getting logo for address '\(address.title)': \(error)")
            return nil
        }
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            topContent
            addressContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var topContent: some View {
        HStack {
            titleContent
            Spacer()
            networkContent
        }
    }
    
    var titleContent: some View {
        Text(address.title)
            .foregroundColor(.neutral0)
            .font(.body14MontserratSemiBold)
            .lineLimit(1)
            .truncationMode(.tail)
    }
    
    var networkContent: some View {
        Group {
            if let chainName = getChainName() {
                Text(chainName + " " + NSLocalizedString("network", comment: ""))
                    .foregroundColor(.neutral300)
                    .font(.body12Menlo)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Unknown " + NSLocalizedString("network", comment: ""))
                    .foregroundColor(.neutral300)
                    .font(.body12Menlo)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
    
    private func getChainName() -> String? {
        do {
            // Encode and decode to ensure we can access the chain
            let data = try JSONEncoder().encode(address.coinMeta)
            let safeMeta = try JSONDecoder().decode(SafeCoinMeta.self, from: data)
            if let chain = Chain(rawValue: safeMeta.chain) {
                return chain.name
            }
        } catch {
            print("Error getting chain name for address '\(address.title)': \(error)")
        }
        return nil
    }
    
    var addressContent: some View {
        Text(address.address)
            .foregroundColor(.neutral0)
            .font(.body12Menlo)
            .lineLimit(1)
            .truncationMode(.middle)
    }
    
    var rearrangeIcon: some View {
        Image(systemName: "square.grid.4x3.fill")
            .font(.body24MontserratMedium)
            .rotationEffect(.degrees(90))
            .foregroundColor(.neutral300)
            .scaleEffect(isEditing ? 1 : 0)
            .frame(width: isEditing ? nil : 0)
    }
    
    var deleteIcon: some View {
        Button {
            modelContext.delete(address)
        } label: {
            deleteIconLabel
        }
    }
    
    var deleteIconLabel: some View {
        Image(systemName: "trash")
            .font(.body24MontserratMedium)
            .foregroundColor(.neutral0)
            .scaleEffect(isEditing ? 1 : 0)
            .frame(width: isEditing ? nil : 0)
    }
    
    private func handleSelection() {
        if shouldReturnAddress {
            returnAddress = address.address
            dismiss()
        } else {
            isNavigationEnabled = true
        }
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            AddressBookCell(address: AddressBookItem.example, shouldReturnAddress: true, isEditing: false, returnAddress: .constant(""))
            AddressBookCell(address: AddressBookItem.example, shouldReturnAddress: false,  isEditing: false, returnAddress: .constant(""))
        }
    }
}
