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
        .font(.body16BrockmannMedium)
    }
    
    var checkmark: some View {
        Image(systemName: "checkmark.circle")
            .foregroundColor(.alertTurquoise)
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
            .foregroundColor(.neutral0)
    }
}

#Preview {
    SendDetailsTabEditTools(forTab: .asset, viewModel: SendDetailsViewModel())
}
