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

    /// The reason a row shows for its outcome.
    ///
    /// A refunded swap stores no reason: its tracker records the outcome, and
    /// the copy is resolved here so it follows the reader's locale rather than
    /// the one in use when the refund was observed. Limit rows are left to
    /// `LimitOrderStatusDisplay`, which words their closures itself.
    static func displayText(for transaction: TransactionHistoryData) -> String? {
        if let stored = displayText(for: transaction.errorMessage) {
            return stored
        }
        guard transaction.type == .swap,
              transaction.status == .error,
              transaction.swapTrackingUiStatus == .refunded else {
            return nil
        }
        return "swapKitStatusRefundedReason".localized
    }
}
