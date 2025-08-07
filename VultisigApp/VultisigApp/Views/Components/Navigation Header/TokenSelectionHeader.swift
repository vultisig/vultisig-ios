//
//  TokenSelectionHeader.swift
//  VultisigApp
//

import SwiftUI

struct TokenSelectionHeader: View {
    let title: String
    let chainDetailView: ChainDetailView
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        Button(action: {
            self.chainDetailView.sheetType = nil
            dismiss()
        }) {
            Image(systemName: "chevron.backward")
                .font(Theme.fonts.bodyLMedium)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }
}

#Preview {
    TokenSelectionHeader(
        title: "choose",
        chainDetailView: ChainDetailView(group: GroupedChain.example, vault: Vault.example)
    )
}
