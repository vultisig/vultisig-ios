//
//  AddressBookCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import SwiftData

struct AddressBookCell: View {
    let address: AddressBookItem
    let shouldReturnAddress: Bool
    let isEditing: Bool
    @Binding var returnAddress: String
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        label
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)
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
        Image(address.coinMeta.logo)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(30)
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
        Text(address.coinMeta.chain.name + " " + NSLocalizedString("network", comment: ""))
            .foregroundColor(.neutral300)
            .font(.body12Menlo)
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
        guard shouldReturnAddress else {
            return
        }
        
        returnAddress = address.address
        dismiss()
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
