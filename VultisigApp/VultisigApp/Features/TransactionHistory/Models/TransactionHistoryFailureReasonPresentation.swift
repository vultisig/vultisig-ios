//
//  TransactionHistoryFailureReasonPresentation.swift
//  VultisigApp
//

enum TransactionHistoryFailureReasonPresentation {
    private static let minimumOutputSignatures = [
        "return amount is not enough",
        "insufficient output"
    ]

    /// App-authored, unlike a node's `OUT_OF_ENERGY`, so it gets localized.
    private static let expiredSignature = "expired before it was included in a block"

    /// Converts a stored provider reason into the copy shown in transaction history.
    /// Raw reasons remain unchanged in storage so localization is resolved when rendered.
    static func displayText(for rawReason: String?) -> String? {
        guard let rawReason, !rawReason.isEmpty else { return nil }

        let normalizedReason = rawReason.lowercased()
        if minimumOutputSignatures.contains(where: normalizedReason.contains) {
            return "swapSlippageToleranceTooTight".localized
        }
        if normalizedReason.contains(Self.expiredSignature) {
            return "transactionExpiredBeforeInclusion".localized
        }

        return rawReason
    }
}
