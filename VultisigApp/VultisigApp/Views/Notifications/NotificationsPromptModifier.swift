//
//  NotificationsPromptModifier.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct NotificationsPromptModifier: ViewModifier {
    @Query var vaults: [Vault]
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var shouldShow: Bool = false

    private var hasSecureVaults: Bool {
        vaults.contains { !$0.isFastVault }
    }

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(isPresented: $shouldShow) {
                NotificationsIntroSheet(isPresented: $shouldShow)
            }
            .onLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    checkIfNeeded()
                }
            }
    }

    private func checkIfNeeded() {
//        guard !pushNotificationManager.hasSeenNotificationPrompt else { return }
//        guard pushNotificationManager.hadVaultsOnStartup else { return }
//        guard hasSecureVaults else { return }

        shouldShow = true
    }
}

extension View {
    func withNotificationsPrompt() -> some View {
        modifier(NotificationsPromptModifier())
    }
}

#if DEBUG
#Preview {
    let mock: PushNotificationManager = MockPushNotificationManager(
        permissionGranted: false
    )

    Screen {
        Color.clear
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        NotificationsIntroSheet(isPresented: .constant(true))
            .environmentObject(mock)
    }
    .environmentObject(mock)
}
#endif
