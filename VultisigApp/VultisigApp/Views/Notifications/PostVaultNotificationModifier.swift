//
//  PostVaultNotificationModifier.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct PostVaultNotificationModifier: ViewModifier {
    let vault: Vault
    @Query var vaults: [Vault]
    @EnvironmentObject var pushNotificationManager: PushNotificationManager

    @State private var shouldShow: Bool = false
    @State private var activeSheetType: SheetType?

    private enum SheetType {
        case intro
        case vaultOptIn
    }

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(isPresented: $shouldShow) {
                sheetContent
            }
            .onChange(of: shouldShow) { _, newValue in
                if !newValue {
                    handleDismiss()
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
        switch activeSheetType {
        case .intro:
            NotificationsIntroSheet(isPresented: $shouldShow)
        case .vaultOptIn:
            NotificationSetupSheet(
                vault: vault,
                isPresented: $shouldShow
            )
        case nil:
            EmptyView()
        }
    }

    private func checkIfNeeded() {
        // Case 1: First app opening with existing vaults — show intro
        if !pushNotificationManager.hasSeenNotificationPrompt
            && pushNotificationManager.hadVaultsOnStartup
            && !vaults.isEmpty {
            activeSheetType = .intro
            shouldShow = true
            return
        }

        // Case 2: New/imported vault — show single vault opt-in
        guard !pushNotificationManager.hasPromptedVaultNotification(vault) else { return }
        activeSheetType = .vaultOptIn
        shouldShow = true
    }

    private func handleDismiss() {
        switch activeSheetType {
        case .intro:
            pushNotificationManager.hasSeenNotificationPrompt = true
            pushNotificationManager.markVaultNotificationPrompted(vault)
        case .vaultOptIn:
            pushNotificationManager.markVaultNotificationPrompted(vault)
        case nil:
            break
        }
        activeSheetType = nil
    }
}

extension View {
    func withPostVaultNotificationPrompt(vault: Vault) -> some View {
        modifier(PostVaultNotificationModifier(vault: vault))
    }
}

#if DEBUG
#Preview("Intro Sheet") {
    let mock = PushNotificationManager()

    Screen {
        Color.clear
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        NotificationsIntroSheet(isPresented: .constant(true))
            .environmentObject(mock)
    }
    .environmentObject(mock)
}

#Preview("Notification Setup") {
    let mock = PushNotificationManager()

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
