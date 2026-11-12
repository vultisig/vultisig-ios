//
//  SendDetailsAddressTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-30.
//

import SwiftUI

struct SendDetailsAddressTab: View {
    let isShown: Bool
    let transition: AnyTransition
    @Bindable var viewModel: SendDetailsViewModel
    @FocusState.Binding var focusedField: Field?

    var body: some View {
        content
            .onChange(of: isShown) { oldValue, newValue in
                Task {
                    await handleClose(oldValue, newValue)
                }
            }
    }

    var content: some View {
        VStack(spacing: 0) {
            if isShown {
                fields
                    .transition(transition)
            }
        }
    }

    var fields: some View {
        SendDetailsAddressFields(viewModel: viewModel, focusedField: $focusedField)
    }

    private func handleClose(_ oldValue: Bool, _ newValue: Bool) async {
        guard oldValue != newValue, !newValue else {
            return
        }
        if !viewModel.toAddress.isEmpty {
            guard let isValid = await viewModel.validateToAddressIfUnchanged() else { return }
            guard isValid else {
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
