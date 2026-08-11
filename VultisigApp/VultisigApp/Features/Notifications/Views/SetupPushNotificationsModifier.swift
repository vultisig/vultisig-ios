//
//  SetupPushNotificationsModifier.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct SetupPushNotificationsModifier: ViewModifier {
    let vault: Vault
    /// Deliberately not a `@Query`. This modifier is applied to the home screen,
    /// so a live query here reinstates on the home tree the whole-window
    /// invalidation that ``ContentView`` gave up — and `checkIfNeeded()` is the
    /// only reader, from an event handler.
    /// See ``SwiftData/ModelContext/fetchAllVaults()``.
    @Environment(\.modelContext) private var modelContext
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
            // Held while the passcode gate is up. `checkIfNeeded` marks the
            // prompt as seen before it raises anything, so running it behind the
            // lock screen would spend the one chance this sheet gets on a screen
            // nobody can see.
            .presentsWhenUnlocked(on: vault) {
                checkIfNeeded()
            }
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch activeSheetType {
        case .intro:
            NotificationsIntroSheet(isPresented: $shouldShow)
        case .vaultOptIn:
            NotificationsIntroSheet(
                isPresented: $shouldShow,
                targetVault: vault
            )
        case nil:
            EmptyView()
        }
    }

    private func checkIfNeeded() {
        guard !shouldShow else { return }

        // Case 1: First app opening with existing vaults — show intro
        if !pushNotificationManager.hasSeenNotificationPrompt
            && pushNotificationManager.hadVaultsOnStartup {

            let vaults = modelContext.fetchAllVaults()
            if !vaults.isEmpty {
                pushNotificationManager.hasSeenNotificationPrompt = true
                for vault in vaults {
                    pushNotificationManager.markVaultNotificationPrompted(vault)
                }

                activeSheetType = .intro
                shouldShow = true
                return
            }
        }

        // Case 2: New/imported vault — show single vault opt-in
        guard !pushNotificationManager.hasPromptedVaultNotification(vault) else { return }

        pushNotificationManager.hasSeenNotificationPrompt = true
        pushNotificationManager.markVaultNotificationPrompted(vault)
        activeSheetType = .vaultOptIn
        shouldShow = true
    }

    private func handleDismiss() {
        activeSheetType = nil
    }
}

extension View {
    func withSetupPushNotifications(vault: Vault) -> some View {
        modifier(SetupPushNotificationsModifier(vault: vault))
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

#endif
