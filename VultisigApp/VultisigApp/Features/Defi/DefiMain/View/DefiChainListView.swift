//
//  DefiChainListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct DefiChainListView: View {
    @ObservedObject var vault: Vault
    @ObservedObject var viewModel: DefiMainViewModel

    @Environment(\.router) var router

    var onCustomizeChains: () -> Void

    var body: some View {
        Group {
            if !viewModel.filteredGroups.isEmpty {
                chainList
            } else {
                CustomizeChainsActionBanner(onCustomizeChains: onCustomizeChains)
            }
        }
    }
    
    var chainList: some View {
        ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.element.id) { index, group in
            Button {
                if group.name == "Circle" {
                    router.navigate(to: CircleRoute.main(vault: vault))
                } else {
                    switch group.chain {
                    case .thorChain, .mayaChain:
                        router.navigate(to: VaultRoute.defiChain(group: group, vault: vault))
                    case .tron:
                        router.navigate(to: TronRoute.main(vault: vault))
                    default:
                        break
                    }
                }
            } label: {
                DefiChainCellView(group: group, vault: vault)
                    .commonListItemContainer(
                        index: index,
                        itemsCount: viewModel.filteredGroups.count
                    )
            }
          }
    }
}

#Preview {
    DefiChainListView(
        vault: .example,
        viewModel: DefiMainViewModel()
    ) {}
        .environmentObject(VaultDetailViewModel())
}
