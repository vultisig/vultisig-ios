//
//  ScannerKeysignHandoff.swift
//  VultisigApp
//

/// Keeps a decoded keysign QR pending until the scanner has actually dismissed.
/// Opening a new scan invalidates any handoff from the previous sheet.
struct ScannerKeysignHandoff {
    private var scannerIsActive = false
    private var joinIsPending = false
    private var reviewIsReady = false

    mutating func scannerOpened() {
        scannerIsActive = true
        joinIsPending = false
        reviewIsReady = false
    }

    mutating func requestJoin() {
        joinIsPending = true
        reviewIsReady = false
    }

    /// Payload preparation and sheet dismissal may finish in either order.
    mutating func reviewReady() -> Bool {
        reviewIsReady = true
        return consumeReadyJoin()
    }

    /// Returns true once, after the final scanner sheet has dismissed.
    mutating func scannerDismissed(isPresentingAgain: Bool) -> Bool {
        guard !isPresentingAgain else { return false }
        scannerIsActive = false
        return consumeReadyJoin()
    }

    private mutating func consumeReadyJoin() -> Bool {
        guard !scannerIsActive, joinIsPending, reviewIsReady else { return false }
        joinIsPending = false
        reviewIsReady = false
        return true
    }
}
