//
//  VaultChainCellView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct VaultChainCellView: View {
    @ObservedObject var group: GroupedChain
    let vault: Vault
    var onCopy: () -> Void
    var onCamera: () -> Void
    @State private var showCamera: Bool = false
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        NavigationLink {
            ChainDetailScreenContainer(
                group: group,
                vault: vault,
                showCamera: $showCamera
            )
        } label: {
            GroupedChainCellView(
                group: group,
                vault: vault,
                fiatBalance: { group.totalBalanceInFiatString },
                cryptoBalance: { group.nativeCoin.balanceStringWithTicker },
                onCopy: onCopy
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: showCamera) { oldValue, newValue in
            if newValue {
                onCamera()
                showCamera = false
            }
        }
    }
}

#Preview {
    VaultChainCellView(group: .example, vault: .example) {} onCamera: {}
        .environmentObject(HomeViewModel())
}
