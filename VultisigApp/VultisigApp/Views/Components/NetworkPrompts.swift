//
//  NetworkPrompts.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct NetworkPrompts: View {
    @Binding var selectedNetwork: NetworkPromptType

    var body: some View {
        HStack(spacing: 12) {
            cells
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    var cells: some View {
        ForEach(NetworkPromptType.allCases, id: \.self) { network in
            getButton(network, isSelected: network==selectedNetwork)
        }
    }

    private func getButton(_ network: NetworkPromptType, isSelected: Bool) -> some View {
        Button {
            handleSelection(for: network)
        } label: {
            NetworkPromptCell(network: network, isSelected: isSelected)
        }
    }

    private func handleSelection(for network: NetworkPromptType) {
        selectedNetwork = network

        if network == .Internet {
            VultisigRelay.IsRelayEnabled = true
        } else {
            VultisigRelay.IsRelayEnabled = false
        }
    }
}

#Preview {
    ZStack {
        Background()
        NetworkPrompts(selectedNetwork: .constant(.Internet))
    }
}
