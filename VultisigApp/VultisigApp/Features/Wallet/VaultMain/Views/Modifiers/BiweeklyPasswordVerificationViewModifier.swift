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
        guard let hint = keychain.getFastHint(pubKeyECDSA: vault.pubKeyECDSA) else { return false }
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
            .onLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkIfNeeded()
                }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                shouldShow = true
            }
        }
    }
}

extension View {
    func withBiweeklyPasswordVerification(vault: Vault) -> some View {
        modifier(BiweeklyPasswordVerificationViewModifier(vault: vault))
    }
}
