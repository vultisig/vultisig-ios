//
//  LimitSwapConfirmationViewModel.swift
//  VultisigApp
//

import Foundation
import Observation

/// Drives the confirmation sheet that gates Sign on the "swap amount is
/// correct" checkbox + a byte-cap pre-flight against the assembled memo.
/// View binding only; the actual TSS sign + broadcast lives outside this
/// VM (wired in §8.B alongside the KeysignPayload assembly).
@MainActor
@Observable
final class LimitSwapConfirmationViewModel {

    let draft: LimitSwapDraft
    let memo: String
    let sourceChainKind: ChainType

    var isAmountCorrectChecked: Bool = false
    var byteCapError: LimitSwapMemoError?

    init(draft: LimitSwapDraft, memo: String, sourceChainKind: ChainType) {
        self.draft = draft
        self.memo = memo
        self.sourceChainKind = sourceChainKind
    }

    /// Sign is enabled only when the user has confirmed the amount is correct
    /// AND the byte-cap pre-flight has not failed for the current memo.
    var canSign: Bool {
        isAmountCorrectChecked && byteCapError == nil
    }

    func toggleAmountCorrect() {
        isAmountCorrectChecked.toggle()
    }

    /// Run the byte-cap pre-flight ahead of the sign-flow. On success invokes
    /// `performSign()` (the caller wires the real keysign machinery there).
    /// On byte-cap failure stores the error in `byteCapError` so the UI can
    /// surface it; performSign() is **not** invoked.
    func attemptSign(performSign: () async throws -> Void) async {
        // Re-run the pre-flight even though the same check happens at memo
        // assembly. Cheap, and guards against drift if a future change to the
        // memo elsewhere lands without a fresh assertion.
        do {
            try assertMemoByteLength(memo, sourceChainKind: sourceChainKind)
        } catch let error as LimitSwapMemoError {
            byteCapError = error
            return
        } catch {
            return
        }

        byteCapError = nil
        try? await performSign()
    }
}
