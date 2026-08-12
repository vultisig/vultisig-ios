//
//  MonthlyBackupWarningViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/09/2025.
//

import SwiftUI

struct MonthlyBackupWarningViewModifier: ViewModifier {
    @Environment(\.router) var router
    let vault: Vault

    @State var shouldShow: Bool = false
    @AppStorage("monthlyReminderDate") var monthlyReminderDate: Date = Date()

    func body(content: Content) -> some View {
        content
            .crossPlatformSheet(isPresented: $shouldShow) {
                MonthlyBackupView(
                    isPresented: $shouldShow,
                    onBackup: {
                        router.navigate(to: KeygenRoute.backupNow(
                            tssType: .Keygen,
                            backupType: .single(vault: vault),
                            isNewVault: false
                        ))
                    }
                ).presentationDetents([.height(224)])
            }
            // Held while the passcode gate is up: this raises itself from the
            // view's own load, so a cold start behind the lock screen would put
            // the sheet above it.
            .presentsWhenUnlocked(after: .milliseconds(500)) {
                checkIfNeeded()
            }
    }

    func checkIfNeeded() {
        let diff = Calendar.current.dateComponents([.day], from: monthlyReminderDate, to: Date())

        if let days = diff.day, days >= 30 {
            shouldShow = true
        }
    }
}

extension View {
    func withMonthlyBackupWarning(vault: Vault) -> some View {
        modifier(MonthlyBackupWarningViewModifier(vault: vault))
    }
}
