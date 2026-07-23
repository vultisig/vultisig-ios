//
//  SettingsAdvancedViewModel.swift
//  VultisigApp
//
//  Drives the destructive "Reset Transaction History" action on the Advanced
//  settings screen. The view only shows the row + the confirmation; the wipe
//  itself lives in `TransactionHistoryResetService`.
//

import Foundation

@MainActor
final class SettingsAdvancedViewModel: ObservableObject {
    /// Whether the mandatory reset confirmation is showing. Tapping the row
    /// flips this on via `requestReset()`; the wipe runs ONLY from
    /// `confirmReset()`, so dismissing/cancelling the confirmation deletes
    /// nothing.
    @Published var isConfirmingReset = false

    private let resetService: TransactionHistoryResetting

    init(resetService: TransactionHistoryResetting = TransactionHistoryResetService.shared) {
        self.resetService = resetService
    }

    /// Ask for confirmation. Deliberately does not delete anything.
    func requestReset() {
        isConfirmingReset = true
    }

    /// Confirmed by the user — perform the irreversible wipe + teardown.
    func confirmReset() {
        isConfirmingReset = false
        resetService.resetAll()
    }
}
