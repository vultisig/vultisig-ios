//
//  TokenSelectionHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
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
                .font(.body18MenloBold)
                .foregroundColor(Color.neutral0)
        }
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
}

#Preview {
    TokenSelectionHeader(
        title: "choose",
        chainDetailView: ChainDetailView(group: GroupedChain.example, vault: Vault.example)
    )
}
