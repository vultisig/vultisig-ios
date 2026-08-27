//
//  WidgetsSettingsScreen.swift
//  VultisigApp
//

import SwiftUI

struct WidgetsSettingsScreen: View {
    @Environment(\.router) private var router

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                Button {
                    router.navigate(to: SettingsRoute.widgetWatchlist)
                } label: {
                    SettingsCommonOptionView(
                        icon: .eye,
                        title: "watchlist".localized
                    )
                }
                .commonListContainer()
                .accessibilityIdentifier(AccessibilityID.Settings.widgetWatchlistCell)

                Spacer()
            }
        }
        .screenTitle("widgets".localized)
    }
}

#if DEBUG
#Preview {
    WidgetsSettingsScreen()
}
#endif
