//
//  AddressBookCell.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import VultisigUIResources
import SwiftData

struct AddressBookCell: View {
    @Environment(\.router) var router
    let address: AddressBookItem
    let shouldReturnAddress: Bool
    let isEditing: Bool
    @Binding var returnAddress: String

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    private static let rowHeight: CGFloat = 66
    private static let gripToRow: CGFloat = 5.5

    var body: some View {
        HStack(spacing: Self.gripToRow) {
            rearrangeIcon
                .showIf(isEditing)
            content
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
    }

    var content: some View {
        HStack(spacing: 0) {
            Button {
                handleSelection()
            } label: {
                HStack(spacing: 12) {
                    logo
                    text
                }
                Spacer(minLength: 20)
            }
            .disabled(isEditing)
            deleteIcon
                .showIf(isEditing)
        }
        .padding(.leading, 16)
        .padding(.trailing, isEditing ? 20 : 16)
        .frame(minHeight: Self.rowHeight)
        .background(
            (isEditing ? Theme.radius.pill : Theme.radius.xl).shape
                .fill(Theme.colors.bgSurface1)
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
    }

    var logo: some View {
        VultisigImage(address.coinMeta.logo)
            .resizable()
            .frame(width: 32, height: 32)
            .cornerRadius(Theme.radius.pill)
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
            .foregroundStyle(Theme.colors.textPrimary)
            .settingsText(.bodyS)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    var addressContent: some View {
        Text(address.address)
            .foregroundStyle(Theme.colors.textSecondary)
            .settingsText(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    var rearrangeIcon: some View {
        Icon(.gripDotsVertical, color: Theme.colors.textPrimary, size: 24)
            .scaleEffect(isEditing ? 1 : 0)
            .frame(width: isEditing ? nil : 0)
    }

    var deleteIcon: some View {
        Button {
            modelContext.delete(address)
            try? modelContext.save()
        } label: {
            deleteIconLabel
        }
        .contentShape(Rectangle())
    }

    var deleteIconLabel: some View {
        Icon(.trashFilled, color: Theme.colors.textTertiary, size: 20)
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
