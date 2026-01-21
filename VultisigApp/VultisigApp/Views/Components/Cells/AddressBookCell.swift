//
//  AddressBookCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import SwiftData

struct AddressBookCell: View {
    @Environment(\.router) var router
    let address: AddressBookItem
    let shouldReturnAddress: Bool
    let isEditing: Bool
    @Binding var returnAddress: String

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    var body: some View {
        HStack {
            rearrangeIcon
                .showIf(isEditing)

            ContainerView {
                label
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, 8)
    }

    var label: some View {
        HStack(spacing: 8) {
            Button {
                handleSelection()
            } label: {
                content
            }
            .disabled(isEditing)
            deleteIcon
                .showIf(isEditing)
        }
    }

    var content: some View {
        HStack(spacing: 12) {
            logo
            text
        }
    }

    var logo: some View {
        Image(address.coinMeta.logo)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(30)
    }

    var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleContent
            addressContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var titleContent: some View {
        Text(address.title)
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    var addressContent: some View {
        Text(address.address)
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.caption12)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    var rearrangeIcon: some View {
        Icon(named: "grip-vertical", color: Theme.colors.textSecondary)
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
        Icon(named: "trash", color: Theme.colors.textTertiary)
            .scaleEffect(isEditing ? 1 : 0)
            .frame(width: isEditing ? nil : 0)
    }

    private func handleSelection() {
        if shouldReturnAddress {
            returnAddress = address.address
            dismiss()
        } else {
            router.navigate(to: SettingsRoute.editAddressBook(addressBookItem: address))
        }
    }
}

#Preview {
    ZStack {
        Background()
        VStack {
            AddressBookCell(address: AddressBookItem.example, shouldReturnAddress: true, isEditing: false, returnAddress: .constant(""))
            AddressBookCell(address: AddressBookItem.example, shouldReturnAddress: false, isEditing: false, returnAddress: .constant(""))
        }
    }
}
