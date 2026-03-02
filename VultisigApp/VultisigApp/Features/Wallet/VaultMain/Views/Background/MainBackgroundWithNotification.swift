//
//  MainBackgroundWithNotification.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 02/03/2026.
//

import SwiftUI

struct MainBackgroundWithNotification: View {
    @EnvironmentObject var pushNotificationManager: PushNotificationManager
    @State var showingNotification: Bool = false

    var body: some View {
        Group {
            if showingNotification {
                Theme.colors.bgPrimary.ignoresSafeArea()
            } else {
                VaultMainScreenBackground()
            }
        }
        .transition(.opacity)
        .onChange(of: pushNotificationManager.foregroundNotification) { _, newValue in
            withAnimation(.interpolatingSpring) {
                showingNotification = newValue != nil
            }
        }
    }
}
