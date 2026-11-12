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
        // Leaving the address step on an unresolved recipient is a definitive failure: show the inline reason.
        await viewModel.recheckRecipient(clearingSetupFirst: false)
    }
}
