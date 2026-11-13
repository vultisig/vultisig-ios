//
//  PerpsRouter.swift
//  VultisigApp
//

import SwiftUI

struct PerpsRouter {
    /// Perps sheets count against their own manager, so the root's blur-and-
    /// darken backdrop stays off and only the system's quiet dim shows. The
    /// screen underneath stays recognisable.
    private static let quietSheetCounter = SheetPresentedCounterManager()

    @ViewBuilder
    func build(_ route: PerpsRoute) -> some View {
        if PerpsConfig.isFeatureEnabled {
            content(route)
                .environment(\.sheetPresentedCounterManager, Self.quietSheetCounter)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(_ route: PerpsRoute) -> some View {
        switch route {
        case .hub(let vault):
            PerpsHubScreen(vault: vault)
        case let .market(vault, coin):
            PerpsMarketScreen(vault: vault, coin: coin)
        case let .position(vault, coin):
            PerpsPositionScreen(vault: vault, coin: coin)
        case .search(let vault):
            PerpsSearchScreen(vault: vault)
        case .activity(let vault):
            PerpsActivityScreen(vault: vault)
        case .withdraw(let vault):
            PerpsWithdrawScreen(vault: vault)
        case .dryRunLog:
            PerpsDryRunLogScreen()
        }
    }
}
