//
//  SettingsHomeDisplayScreen.swift
//  VultisigApp
//

import SwiftUI

/// Picks what the home header's balance shows, for every vault.
struct SettingsHomeDisplayScreen: View {
    @EnvironmentObject var homeViewModel: HomeViewModel

    private let options = HomeBalanceDisplay.allCases

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                SettingsSectionView(title: "balanceDisplay") {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        Button {
                            homeViewModel.balanceDisplay = option
                        } label: {
                            SettingSelectionCell(
                                title: option.title,
                                isSelected: homeViewModel.balanceDisplay == option,
                                description: option.description
                            )
                        }
                        .buttonStyle(.plain)
                        .commonListItemContainer(index: index, itemsCount: options.count)
                    }
                }
            }
        }
        .screenTitle("homeDisplay".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
    }
}

#Preview {
    SettingsHomeDisplayScreen()
        .environmentObject(HomeViewModel())
}
