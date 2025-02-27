//
//  SwitchToLocalLink.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-27.
//

import SwiftUI

struct SwitchToLocalLink: View {
    @ObservedObject var viewModel: KeygenPeerDiscoveryViewModel
    
    var body: some View {
        Button {
            toggleNetwork()
        } label: {
            label
        }
    }
    
    var label: some View {
        ZStack {
            if viewModel.selectedNetwork == .Internet {
                switchToLocalLabel
            } else {
                switchToInternetLabel
            }
        }
        .font(.body12BrockmannMedium)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    var switchToLocalLabel: some View {
        HStack {
            Text(NSLocalizedString("createVaultPrivately", comment: ""))
            
            Text(NSLocalizedString("switchToLocalMode", comment: ""))
            .underline()
        }
    }
    
    var switchToInternetLabel: some View {
        Text(NSLocalizedString("switchBackToInternetMode", comment: ""))
        .underline()
        .font(.body12BrockmannMedium)
    }
    
    private func toggleNetwork() {
        withAnimation {
            if viewModel.selectedNetwork == .Internet {
                viewModel.selectedNetwork = .Local
            } else {
                viewModel.selectedNetwork = .Internet
            }
        }
    }
}

#Preview {
    SwitchToLocalLink(viewModel: KeygenPeerDiscoveryViewModel())
}
