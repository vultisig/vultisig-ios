//
//  BiweeklyPasswordVerificationViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/09/2025.
//

import SwiftUI

struct BiweeklyPasswordVerificationViewModifier: ViewModifier {
    let vault: Vault

    @State var shouldShow: Bool = false
    @AppStorage("biweeklyPasswordVerifyDate") private var biweeklyPasswordVerifyDate: Double?

    private let keychain = DefaultKeychainService.shared

    private var hasHint: Bool {
        // Only decides the sheet's height, so an unreadable Keychain sizes it as
        // if no hint were stored.
        let saved = keychain.getFastHint(pubKeyECDSA: vault.pubKeyECDSA)
        guard let hint = saved.valueTreatingUnavailableAsAbsent else { return false }
        return !hint.isEmpty
    }

    private var sheetHeight: CGFloat {
        hasHint ? 420 : 360
    }

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(isPresented: $shouldShow) {
                PasswordVerifyReminderView(vault: vault, isSheetPresented: $shouldShow)
                    .presentationDetents([.height(sheetHeight)])
                #if os(macOS)
                    .frame(width: 400, height: sheetHeight)
                #endif
            }
            // Gated rather than merely delayed. This raises a *credential* sheet
            // — the fast-vault server password — from the view's own load, so on
            // a cold start behind the passcode gate it would appear over the lock
            // screen and take input, in a layer the gate cannot reach.
            //
            // The whole second of delay lives here, and the check raises the
            // sheet the moment it decides to. Split across two waits, the second
            // one ran ungated: a relock landing inside it put the sheet up
            // anyway.
            .presentsWhenUnlocked(after: .seconds(1)) {
                checkIfNeeded()
            }
    }

    func checkIfNeeded() {
        guard vault.isFastVault else { return }

        guard let lastVerifyTimestamp = biweeklyPasswordVerifyDate else {
            return
        }

        let lastVerifyDate = Date(timeIntervalSince1970: lastVerifyTimestamp)
        let currentDate = Date()

        let calendar = Calendar.current
        let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastVerifyDate), to: calendar.startOfDay(for: currentDate))

        if let days = difference.day, days >= 15 {
            shouldShow = true
        }
    }
}

extension View {
    func withBiweeklyPasswordVerification(vault: Vault) -> some View {
        modifier(BiweeklyPasswordVerificationViewModifier(vault: vault))
    }
}
