//
//  TransactionHistoryFailureReasonPresentation.swift
//  VultisigApp
//

enum TransactionHistoryFailureReasonPresentation {
    private static let minimumOutputSignatures = [
        "return amount is not enough",
        "insufficient output"
    ]

    /// Converts a stored provider reason into the copy shown in transaction history.
    /// Raw reasons remain unchanged in storage so localization is resolved when rendered.
    static func displayText(for rawReason: String?) -> String? {
        guard let rawReason, !rawReason.isEmpty else { return nil }

        let normalizedReason = rawReason.lowercased()
        if minimumOutputSignatures.contains(where: normalizedReason.contains) {
            return "swapSlippageToleranceTooTight".localized
        }

        return rawReason
    }
}
