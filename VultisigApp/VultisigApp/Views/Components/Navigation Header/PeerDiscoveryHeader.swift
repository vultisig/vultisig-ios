//
//  PeerDiscoveryHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct PeerDiscoveryHeader: View {
    let selectedTab: SetupVaultState
    @ObservedObject var viewModel: KeygenPeerDiscoveryViewModel
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(getTitle())
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        ZStack {
            if viewModel.status == .WaitingForDevices {
                NavigationQRShareButton(title: "joinKeygen", renderedImage: shareSheetViewModel.renderedImage)
            }
        }
    }
    
    private func getTitle() -> String {
        NSLocalizedString("keygenFor", comment: "") +
        " " +
        selectedTab.getNavigationTitle() +
        " " +
        NSLocalizedString("vault", comment: "")
    }
}

#Preview {
    PeerDiscoveryHeader(
        selectedTab: .TwoOfTwoVaults,
        viewModel: KeygenPeerDiscoveryViewModel(),
        shareSheetViewModel: ShareSheetViewModel()
    )
    .environmentObject(ShareSheetViewModel())
}