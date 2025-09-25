//
//  MonthlyBackupWarningViewModifier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 25/09/2025.
//

import SwiftUI

struct MonthlyBackupWarningViewModifier: ViewModifier {
    let vault: Vault
    
    @State var shouldShow: Bool = false
    @State var isBackupLinkActive: Bool = false
    @AppStorage("monthlyReminderDate") var monthlyReminderDate: Date = Date()
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $shouldShow) {
                MonthlyBackupView(isPresented: $shouldShow, isBackupPresented: $isBackupLinkActive)
                    .presentationDetents([.height(224)])
            }
            .navigationDestination(isPresented: $isBackupLinkActive) {
                VaultBackupNowScreen(tssType: .Keygen, backupType: .single(vault: vault))
            }
            .onLoad {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkIfNeeded()
                }
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
