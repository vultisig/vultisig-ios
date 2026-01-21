//
//  PeerDiscoveryHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct PeerDiscoveryHeader: View {
    let title: String
    let vault: Vault
    let hideBackButton: Bool

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
            .opacity(hideBackButton ? 0 : 1)
    }

    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }

    var trailingAction: some View {
        ZStack {
            if viewModel.status == .WaitingForDevices {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Keygen,
                    viewModel: shareSheetViewModel
                )
            }
        }
    }
}

#Preview {
    PeerDiscoveryHeader(
        title: "Keygen",
        vault: Vault.example,
        hideBackButton: false,
        viewModel: KeygenPeerDiscoveryViewModel(),
        shareSheetViewModel: ShareSheetViewModel()
    )
    .environmentObject(ShareSheetViewModel())
}
