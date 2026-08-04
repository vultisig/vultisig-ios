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
            await closeIfThePasscodeWasSetAnyway(after: failure)
        }
    }

    /// A thrown `setPasscode` does not mean no passcode was set.
    ///
    /// The wrapped key is made durable and the lock mode switches to `.passcode`
    /// as soon as that write verifies — deliberately, and well before the sweep
    /// that seals the shares. A failure after that point leaves a passcode that
    /// genuinely works, with its sweep unfinished; the next app unlock's resume
    /// completes it. Reporting a failure there strands the user in a retry whose
    /// only possible answer is `alreadySet`.
    ///
    /// `alreadySet` itself is excluded: it is the one failure that means the
    /// passcode on the device is somebody else's, not the one just entered.
    private func closeIfThePasscodeWasSetAnyway(after failure: Error?) async {
        guard let failure else { return }
        guard (failure as? PasscodeError) != .alreadySet else { return }
        guard await service.isSet else { return }

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
        case .notSet, .alreadySet:
            return "passcodeGenericError".localized
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
