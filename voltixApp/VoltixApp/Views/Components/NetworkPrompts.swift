//
//  NetworkPrompts.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct NetworkPrompts: View {
    @ObservedObject var viewModel: KeygenPeerDiscoveryViewModel
    
    private let gridRows = [
            GridItem(.adaptive(minimum: 150))
    ]
    
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            phoneLayout
        } else {
            padLayout
        }
    }
    
    var phoneLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                cells
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }
    
    var padLayout: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120)), count: 3), spacing: 10){
            cells
        }
        .padding(.horizontal, 24)
    }
    
    var cells: some View {
        ForEach(NetworkPromptType.allCases, id: \.self) { network in
            getButton(network, isSelected: network==viewModel.selectedNetwork)
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
        withAnimation {
            viewModel.selectedNetwork = network
        }
        
        if network == .Cellular {
            VoltixRelay.IsRelayEnabled = true
        } else {
            VoltixRelay.IsRelayEnabled = false
        }
    }
}

#Preview {
    ZStack {
        Background()
        NetworkPrompts(viewModel: KeygenPeerDiscoveryViewModel())
    }
}
