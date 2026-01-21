//
//  SendDetailsTabEditTools.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-24.
//

import SwiftUI

struct SendDetailsTabEditTools: View {
    let forTab: SendDetailsFocusedTab
    @ObservedObject var viewModel: SendDetailsViewModel

    var body: some View {
        HStack(spacing: 12) {
            checkmark
            editButton
        }
        .font(Theme.fonts.bodyMMedium)
    }

    var checkmark: some View {
        Image(systemName: "checkmark.circle")
            .foregroundColor(Theme.colors.alertSuccess)
    }

    var editButton: some View {
        Button {
            viewModel.onSelect(tab: forTab)
        } label: {
            editLabel
        }
    }

    var editLabel: some View {
        Image(systemName: "pencil")
            .foregroundColor(Theme.colors.textPrimary)
    }
}

#Preview {
    SendDetailsTabEditTools(forTab: .asset, viewModel: SendDetailsViewModel())
}
