//
//  PostVaultNotificationModifier.swift
//  VultisigApp
//

import SwiftUI

struct PostVaultNotificationModifier: ViewModifier {
    let vault: Vault
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var shouldShow: Bool = false

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(isPresented: $shouldShow) {
                sheetContent
            }
            .onChange(of: shouldShow) { _, newValue in
                if !newValue {
                    pushNotificationManager.markVaultNotificationPrompted(
                        pubKeyECDSA: vault.pubKeyECDSA
                    )
                }
            }
            .onLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkIfNeeded()
                }
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if pushNotificationManager.isPermissionGranted {
            VaultNotificationOptInSheet(
                vault: vault,
                isPresented: $shouldShow
            )
        } else {
            NotificationSetupSheet(
                vault: vault,
                isPresented: $shouldShow
            )
        }
    }

    private func checkIfNeeded() {
        guard !vault.isFastVault else { return }
        guard !pushNotificationManager.hasPromptedVaultNotification(
            pubKeyECDSA: vault.pubKeyECDSA
        ) else { return }
        shouldShow = true
    }
}

extension View {
    func withPostVaultNotificationPrompt(vault: Vault) -> some View {
        modifier(PostVaultNotificationModifier(vault: vault))
    }
}

#if DEBUG
#Preview("Permission Granted") {
    let mock: PushNotificationManager = MockPushNotificationManager(
        permissionGranted: true
    )

    Screen {
        Color.clear
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        VaultNotificationOptInSheet(
            vault: Vault.example,
            isPresented: .constant(true)
        )
        .environmentObject(mock)
    }
    .environmentObject(mock)
}

#Preview("Permission Not Granted") {
    let mock: PushNotificationManager = MockPushNotificationManager(
        permissionGranted: false
    )

    Screen {
        Color.clear
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        NotificationSetupSheet(
            vault: Vault.example,
            isPresented: .constant(true)
        )
        .environmentObject(mock)
    }
    .environmentObject(mock)
}
#endif
