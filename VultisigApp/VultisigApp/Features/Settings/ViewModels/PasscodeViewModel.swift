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

    @Published var entry: String = "" {
        didSet {
            // Typing is the user's answer to the error, so it clears the moment
            // they start over rather than sitting there contradicting the dots
            // they are refilling.
            guard !entry.isEmpty, errorMessage != nil else { return }
            errorMessage = nil
        }
    }
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

    /// Whether the passcode field has anything to say for itself yet.
    ///
    /// Starts `false` on the lock screen so the keypad does not appear during
    /// the automatic biometric attempt. With the shortcut enabled the attempt
    /// usually succeeds, and a keypad rendered for those few hundred
    /// milliseconds is a lock screen that flashes up and dismisses itself for
    /// no reason the user can see — which is exactly what it looked like.
    @Published var shouldPresentEntry = false

    func refreshBiometricAvailability() async {
        isBiometricUnlockAvailable = await service.isBiometricUnlockEnabled
    }

    /// The lock screen's whole opening move: offer the shortcut if there is one,
    /// and reveal the keypad the moment that question is settled.
    ///
    /// `defer` rather than a line at each exit. The reveal is what stands
    /// between the user and a screen they cannot get past, so it has to happen
    /// on *every* path out of here — including a thrown error, and including
    /// cancellation when the view goes away mid-attempt. A missed reveal is a
    /// lock screen with no keypad and no way in but a force quit.
    func beginUnlock(biometricReason: String) async {
        defer { shouldPresentEntry = true }

        await refreshBiometricAvailability()
        guard isBiometricUnlockAvailable else { return }

        // Offered immediately so the common case is one glance rather than six
        // taps. Declining or failing falls through to the keypad below.
        await unlockWithBiometrics(reason: biometricReason)
    }

    /// Attempts the shortcut, and stays quiet about the failures the user just
    /// caused and can already see.
    func unlockWithBiometrics(reason: String) async {
        do {
            _ = try await service.unlockWithBiometrics(reason: reason)
            // A lock can land between adopting the key and dismissing the lock
            // screen. Confirming the session still holds the key means a later
            // lock always wins rather than being cleared by an unlock that had
            // already been overtaken.
            didFinish = service.isSessionUnlocked
        } catch {
            errorMessage = Self.biometricMessage(for: error)
        }
    }

    /// Cancelling, a face that did not match, biometry being unavailable: the
    /// user watched those happen, the passcode field is already on screen, and
    /// "Face ID failed" adds nothing. The rest are different — the *match*
    /// succeeded and nothing happened — and silence there reads as the app
    /// ignoring them.
    private static func biometricMessage(for error: Error) -> String? {
        switch error as? BiometricUnlockError {
        case .supersededCopy, .malformedCopy:
            // The match worked and the shortcut was withdrawn anyway — because
            // the stored copy belongs to a wrapper that is gone, or is not the
            // right shape to be a key. Either way the toggle in Settings now
            // reads off, and saying nothing would make a successful face look
            // like a failed one.
            return "passcodeBiometricUnavailable".localized
        default:
            break
        }

        switch error as? PasscodeError {
        case .busy, .storageFailure:
            return message(for: error)
        default:
            return nil
        }
    }

    // MARK: - Unlock

    /// The lock screen's unlock, and it must stay on ``PasscodeService/unlockApp(with:now:)``.
    ///
    /// `unlock(with:)` — which the change flow below uses correctly — takes the
    /// same argument, throws the same errors and compiles here just as well. It
    /// is passcode *verification*: no lease, and no resume sweep. Wired to it,
    /// the lock screen would look identical and silently never finish a
    /// transition an earlier crash left half done, so the shares an interrupted
    /// `setPasscode` did not reach would stay in the clear behind a live
    /// passcode for as long as the app is installed.
    func unlock() async {
        await perform {
            _ = try await self.service.unlockApp(with: self.entry)
        }

        // `unlockApp` re-checks the session generation before it returns, but a
        // `lock()` can still land in the gap between that return and this
        // assignment — it is `nonisolated` and synchronizes with nothing. An
        // unlock that has already been overtaken must not report success, or the
        // screen comes down over a session that no longer holds the key.
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
            let failure = await perform { try await self.service.setPasscode(passcode) }
            closeIfThePasscodeIsAlreadyDurable(after: failure)
        }
    }

    /// `cancelledByLock` out of `setPasscode` is the one failure that proves the
    /// passcode the user just typed is already established.
    ///
    /// It is thrown from a single place — the guard that adopts the data key —
    /// and that guard sits after the wrapped key has verified and after the lock
    /// mode has moved to `.passcode`. So the passcode is durable and the gate is
    /// up; only the key was not taken into the session, because a background
    /// lock beat it there. The lock screen is about to cover everything and the
    /// next unlock's resume finishes the sweep, so this flow has nothing left to
    /// do and closing it is the honest outcome.
    ///
    /// **Nothing else qualifies, and asking `isSet` instead was wrong.** `isSet`
    /// answers `true` for an *unreadable* wrapper as well as a present one, and
    /// it cannot tell a wrapper this call wrote from one that was already there
    /// — so a failed read-back verification, or a transition refused while
    /// somebody else's set completed, would have dismissed the screen over a
    /// passcode the user never set. A sweep that fails after the wrapper is
    /// durable does still leave a working passcode, but there is no signal here
    /// that distinguishes it from a sweep-shaped failure *before* the wrapper,
    /// so it reports the error and `alreadySet` explains the retry.
    private func closeIfThePasscodeIsAlreadyDurable(after failure: Error?) {
        guard (failure as? PasscodeError) == .cancelledByLock else { return }
        errorMessage = nil
        didFinish = true
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
    ///
    /// - Returns: the error, for the one caller that has to know whether the
    ///   operation left durable state behind despite throwing.
    @discardableResult
    private func perform(advanceTo next: Stage? = nil, _ operation: @escaping () async throws -> Void) async -> Error? {
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
            return nil
        } catch PasscodeError.cancelledByLock {
            // The app locked mid-verification. Not a failed attempt: clear the
            // field and show nothing, since the lock screen is about to be
            // presented again anyway.
            entry = ""
            errorMessage = nil
            return PasscodeError.cancelledByLock
        } catch {
            fail(with: Self.message(for: error))
            return error
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
        case .notSet:
            return "passcodeGenericError".localized
        case .alreadySet:
            // The set flow's one dead end: a passcode is already on the device,
            // and re-entering digits can only answer this again. Saying so sends
            // the user back to the screen that offers change and remove, rather
            // than leaving a generic failure they can only retry.
            return "passcodeAlreadySet".localized
        case .busy:
            // Contention is reported rather than queued, so it needs an answer.
            // Deliberately says nothing about *which* operation: from Settings
            // it is usually a keygen or an import, but on the lock screen it is
            // another unlock or a transition, and naming vault creation there
            // would point at something the user cannot even see.
            return "passcodeBusy".localized
        case .sealedSharesWithoutKey:
            // Not the same as an unreadable passcode: the vaults are provably
            // encrypted and the key that opens them is not there. Its own
            // message, because "the passcode could not be read" understates it
            // and no retry can help.
            return "passcodeSealedSharesWithoutKey".localized
        case .storageFailure, .inconsistentState:
            return "passcodeStorageError".localized
        case .cancelledByLock:
            // Handled before it reaches here, but the switch must stay
            // exhaustive; nothing user-facing is appropriate for a cancellation.
            return ""
        }
    }
}
