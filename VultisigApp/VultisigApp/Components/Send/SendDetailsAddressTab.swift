//
//  SendDetailsAddressTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-30.
//

import SwiftUI

struct SendDetailsAddressTab: View {
    let isExpanded: Bool
    @Bindable var viewModel: SendDetailsViewModel
    @FocusState.Binding var focusedField: Field?

    var body: some View {
        content
            .onChange(of: isExpanded) { oldValue, newValue in
                Task {
                    await handleClose(oldValue, newValue)
                }
            }
    }

    var content: some View {
        SendFormExpandableSection(
            isExpanded: isExpanded,
            cornerRadius: 24,
            horizontalPadding: 16,
            verticalPadding: 20,
            backgroundColor: Theme.colors.bgPrimary
        ) {
            titleSection
        } content: {
            VStack(spacing: 16) {
                separator
                fields
            }
        }
    }

    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("address", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            if viewModel.addressSetupDone {
                selectedAddress
                Spacer()
                doneEditTools
            } else {
                Spacer()
            }
        }
        .background(Background().opacity(0.01))
        .onTapGesture {
            viewModel.onSelect(tab: .address)
        }
    }

    var separator: some View {
        Separator(color: Theme.colors.borderLight, opacity: 1)
    }

    var selectedAddress: some View {
        Text("\(viewModel.toAddress)")
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    var doneEditTools: some View {
        SendDetailsTabEditTools(forTab: .address, viewModel: viewModel)
    }

    var fields: some View {
        SendDetailsAddressFields(viewModel: viewModel, focusedField: $focusedField)
    }

    private func handleClose(_ oldValue: Bool, _ newValue: Bool) async {
        guard oldValue != newValue, !newValue else {
            return
        }
        if !viewModel.toAddress.isEmpty {
            guard await viewModel.validateToAddress() else {
                // Collapsing the address tab on an unresolved recipient is a
                // definitive failure — surface the inline reason rather than
                // just leaving Next disabled.
                viewModel.markInvalidRecipient()
                viewModel.addressSetupDone = false
                if viewModel.selectedTab == .amount {
                    viewModel.onSelect(tab: .address)
                }
                return
            }
            viewModel.addressSetupDone = true
        }
    }
}
