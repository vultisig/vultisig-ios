//
//  ErrorPresentation.swift
//  VultisigApp
//

import Foundation

/// Pure, testable mapping from known error conditions to the friendly copy the
/// shared `ErrorView` renders: a human title, a fix-it subtitle, a hero variant
/// (`.alert` red ✕ hard failure / `.warning` amber ⚠ recoverable), and the raw
/// technical trace (when one exists) for the "Show exact error" disclosure.
///
/// Leads with a human-readable message; the raw text is kept one tap away. Any
/// unmapped failure falls back to the generic "Transaction failed" critical case
/// with the raw text attached.
struct ErrorPresentation: Equatable {
    let title: String
    let description: String
    let type: ErrorView.ErrorType
    let rawError: String?

    /// Named error conditions catalogued from the issue. Each maps to a fixed
    /// title/subtitle/variant; `rawError` is threaded in by the caller where a
    /// technical trace is available (precondition states pass `nil`).
    enum Kind {
        case transactionFailed
        case networkUnstable
        case insufficientFunds
        case cameraPermission
        case sameVaultShare
        case vaultNotLoaded
        case vaultNameInUse
        case seedPhraseAlreadyImported
    }

    init(_ kind: Kind, rawError: String? = nil) {
        self.rawError = rawError
        switch kind {
        case .transactionFailed:
            title = "transactionFailed".localized
            description = "transactionFailedDescription".localized
            type = .alert
        case .networkUnstable:
            title = "errorNetworkUnstableTitle".localized
            description = "errorNetworkUnstableDescription".localized
            type = .warning
        case .insufficientFunds:
            title = "swapErrorInsufficientFundsTitle".localized
            description = "swapErrorInsufficientFundsDescription".localized
            type = .warning
        case .cameraPermission:
            title = "errorCameraPermissionTitle".localized
            description = "errorCameraPermissionDescription".localized
            type = .warning
        case .sameVaultShare:
            title = "sameDeviceShareError".localized
            description = "sameDeviceShareErrorDescription".localized
            type = .warning
        case .vaultNotLoaded:
            title = "errorVaultNotLoadedTitle".localized
            description = "errorVaultNotLoadedDescription".localized
            type = .warning
        case .vaultNameInUse:
            title = "vaultNameAlreadyInUse".localized
            description = "pleaseChooseDifferentVaultName".localized
            type = .warning
        case .seedPhraseAlreadyImported:
            title = "seedPhraseAlreadyImported".localized
            description = "seedPhraseAlreadyImportedDescription".localized
            type = .warning
        }
    }

    private init(title: String, description: String, type: ErrorView.ErrorType, rawError: String?) {
        self.title = title
        self.description = description
        self.type = type
        self.rawError = rawError
    }

    /// Maps a raw keysign/signing error string to a friendly presentation,
    /// classifying recoverable cases (network, insufficient funds) into the
    /// amber warning variant and everything else into the generic critical
    /// "Transaction failed" case. The raw string is always preserved.
    static func signing(rawError: String) -> ErrorPresentation {
        let lowered = rawError.lowercased()
        let raw = rawError.isEmpty ? nil : rawError

        if lowered.contains("insufficient funds") || lowered.contains("insufficient balance") {
            return ErrorPresentation(.insufficientFunds, rawError: raw)
        }

        if isNetworkError(lowered) {
            return ErrorPresentation(.networkUnstable, rawError: raw)
        }

        return ErrorPresentation(.transactionFailed, rawError: raw)
    }

    /// Generic fallback for an arbitrary error: the critical "Transaction
    /// failed" case carrying the underlying description as the raw trace.
    static func unknown(rawError: String) -> ErrorPresentation {
        ErrorPresentation(.transactionFailed, rawError: rawError.isEmpty ? nil : rawError)
    }

    /// Keygen failure: a recoverable network error surfaces the amber "Network
    /// unstable" copy; anything else keeps the keygen-specific `title` with a
    /// generic subtitle and the raw trace behind "Show exact error".
    static func keygen(title: String, rawError: String) -> ErrorPresentation {
        let raw = rawError.isEmpty ? nil : rawError
        if isNetworkError(rawError.lowercased()) {
            return ErrorPresentation(.networkUnstable, rawError: raw)
        }
        return ErrorPresentation(
            title: title,
            description: "transactionFailedDescription".localized,
            type: .alert,
            rawError: raw
        )
    }

    private static func isNetworkError(_ lowered: String) -> Bool {
        let markers = [
            "network connection was lost",
            "the internet connection",
            "could not connect",
            "timed out",
            "timeout",
            "network is unreachable",
            "offline"
        ]
        return markers.contains { lowered.contains($0) }
    }
}
