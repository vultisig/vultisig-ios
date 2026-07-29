//
//  PasscodeViewModel.swift
//  VultisigApp
//

import Foundation
import SwiftUI

/// Drives every passcode flow: unlock, set, change, disable.
///
/// The screens are declarative shells over this — none of them talk to
/// `PasscodeService` directly, so there is one place where a failure decides what
/// the user is told and whether the entry field resets.
@MainActor
final class PasscodeViewModel: ObservableObject {

    /// Which entry a multi-step flow is currently collecting.
    enum Stage {
        case current
        case new
        case confirm
    }

    @Published var entry: String = ""
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false
    @Published private(set) var stage: Stage
    @Published var didFinish: Bool = false

    private let service: PasscodeService
    private var firstEntry: String?

    init(service: PasscodeService = .shared, stage: Stage = .current) {
        self.service = service
        self.stage = stage
    }

    // MARK: - Biometric shortcut

    @Published var isBiometricUnlockAvailable = false

    func refreshBiometricAvailability() async {
        isBiometricUnlockAvailable = await service.isBiometricUnlockEnabled
    }

    /// Attempts the shortcut. Silent on failure by design: the passcode field is
    /// already on screen, and telling the user "Face ID failed" adds nothing they
    /// cannot see. Cancelling must leave them exactly where they were.
    func unlockWithBiometrics(reason: String) async {
        do {
            _ = try await service.unlockWithBiometrics(reason: reason)
            // A lock can land between adopting the key and dismissing the lock
            // screen. Confirming the session still holds the key means a later
            // lock always wins rather than being cleared by an unlock that had
            // already been overtaken.
            didFinish = service.isSessionUnlocked
        } catch {
            errorMessage = nil
        }
    }

    // MARK: - Unlock

    func unlock() async {
        await perform {
            try await self.service.unlock(with: self.entry)
        }
        // Same reasoning as the biometric path: a lock that landed during
        // verification must not be undone by the unlock finishing.
        if didFinish, !service.isSessionUnlocked {
            didFinish = false
            entry = ""
        }
    }

    // MARK: - Set (enter, then confirm)

    func submitForSet() async {
        switch stage {
        case .new, .current:
            firstEntry = entry
            advance(to: .confirm)
        case .confirm:
            guard entry == firstEntry else {
                return failWithMismatch()
            }
            let passcode = entry
            await perform { try await self.service.setPasscode(passcode) }
        }
    }

    // MARK: - Change (current, then new, then confirm)

    func submitForChange() async {
        switch stage {
        case .current:
            let current = entry
            // Verified before asking for a replacement, so the user is not made
            // to invent and confirm a new passcode only to be told at the end
            // that the old one was wrong.
            await perform(advanceTo: .new) {
                _ = try await self.service.unlock(with: current)
                self.verifiedCurrent = current
            }
        case .new:
            firstEntry = entry
            advance(to: .confirm)
        case .confirm:
            guard entry == firstEntry else {
                return failWithMismatch()
            }
            guard let current = verifiedCurrent else {
                return fail(with: "passcodeGenericError".localized)
            }
            let new = entry
            await perform { try await self.service.changePasscode(current: current, new: new) }
        }
    }

    // MARK: - Disable

    func submitForDisable() async {
        let current = entry
        await perform { try await self.service.disablePasscode(current: current) }
    }

    // MARK: - Helpers

    private var verifiedCurrent: String?

    private func advance(to next: Stage) {
        stage = next
        entry = ""
        errorMessage = nil
    }

    private func failWithMismatch() {
        firstEntry = nil
        stage = .new
        entry = ""
        errorMessage = "passcodeMismatch".localized
    }

    private func fail(with message: String) {
        entry = ""
        errorMessage = message
    }

    /// Runs an operation, clearing the field on failure so the next attempt
    /// starts from empty rather than from a half-typed value.
    private func perform(advanceTo next: Stage? = nil, _ operation: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await operation()
            if let next {
                advance(to: next)
            } else {
                didFinish = true
            }
        } catch PasscodeError.cancelledByLock {
            // The app locked mid-verification. Not a failed attempt: clear the
            // field and show nothing, since the lock screen is about to be
            // presented again anyway.
            entry = ""
            errorMessage = nil
        } catch {
            fail(with: Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        guard let passcodeError = error as? PasscodeError else {
            return "passcodeGenericError".localized
        }

        switch passcodeError {
        case .wrongPasscode:
            return "passcodeIncorrect".localized
        case .lockedOut(let remaining):
            let minutes = Int(ceil(remaining / 60))
            return minutes > 1
                ? String(format: "passcodeLockedOutMinutes".localized, minutes)
                : "passcodeLockedOutShortly".localized
        case .invalidLength:
            return "passcodeInvalidLength".localized
        case .notSet, .alreadySet, .noDataKey:
            return "passcodeGenericError".localized
        case .storageFailure, .inconsistentState:
            return "passcodeStorageError".localized
        case .cancelledByLock:
            // Handled before it reaches here, but the switch must stay
            // exhaustive; nothing user-facing is appropriate for a cancellation.
            return ""
        }
    }
}
