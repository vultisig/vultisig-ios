//
//  SwapRecipientVerifier.swift
//  VultisigApp
//
//  On-device output-target verification for swaps that deliver to an external
//  recipient (HIGH security tier, safety net). After the swap quote/tx is built
//  but BEFORE it is signed, we re-derive the actual on-chain output target from
//  the built artifact and assert it equals the recipient the user saw on the
//  verify screen. A mismatch means the provider dropped or misused the recipient
//  param — we fail closed (`SwapError.recipientVerificationFailed`) and never
//  sign, rather than silently misdirecting funds.
//
//  This only runs when an external recipient is set. With no external recipient
//  the funds go to the user's own address and there is nothing to verify, so the
//  no-recipient path is untouched.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-recipient-verify")

enum SwapRecipientVerifier {

    /// Verify that `transaction`'s built artifact targets its external recipient.
    /// No-op when no external recipient is set. Throws
    /// `SwapError.recipientVerificationFailed` on any mismatch or when the
    /// provider can't expose a verifiable output target.
    static func verify(transaction: SwapTransaction) throws {
        guard let recipient = transaction.advancedSettings.externalRecipient else {
            // No external recipient → output goes to the user's own address.
            return
        }
        try verify(quote: transaction.quote, recipient: recipient)
    }

    /// Pure core, exposed for tests: assert the quote's built output target
    /// matches `recipient`.
    static func verify(quote: SwapQuote, recipient: String) throws {
        switch quote {
        case let .thorchain(thorQuote),
             let .thorchainChainnet(thorQuote),
             let .thorchainStagenet(thorQuote),
             let .mayachain(thorQuote):
            // THORChain/Maya bake the recipient into the swap memo's DESTADDR
            // field; that memo is signed verbatim. Assert the node-returned memo
            // actually carries the recipient. The memo is a colon-delimited
            // string (`=:ASSET:DESTADDR:LIM/...`); a containment check is robust
            // to address-case and the surrounding memo fields.
            guard memo(thorQuote.memo, contains: recipient) else {
                logger.error("[recipient-verify] THOR/Maya memo does not contain the recipient")
                throw SwapError.recipientVerificationFailed
            }

        case let .swapkit(response, _, _):
            // SwapKit echoes the `destinationAddress` we sent on `/v3/swap`.
            // Assert the echo equals the recipient — a provider that dropped the
            // param would echo the user's own address (or empty) instead.
            guard addressesMatch(response.destinationAddress, recipient) else {
                logger.error("[recipient-verify] SwapKit destinationAddress echo does not match the recipient")
                throw SwapError.recipientVerificationFailed
            }

        case .oneinch, .kyberswap, .lifi:
            // These providers bury the recipient inside opaque router calldata
            // with no verifiable echo, so they are never eligible when an
            // external recipient is set (`SwapProvider.honorsExternalRecipient`).
            // Reaching here means the recipient gate let one through — fail
            // closed rather than sign an unverifiable output target.
            logger.error("[recipient-verify] provider cannot expose a verifiable output target for an external recipient")
            throw SwapError.recipientVerificationFailed
        }
    }

    /// Case-insensitive containment of `needle` inside a THOR/Maya memo, trimmed.
    private static func memo(_ memo: String, contains needle: String) -> Bool {
        let trimmedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNeedle.isEmpty else { return false }
        return memo.range(of: trimmedNeedle, options: .caseInsensitive) != nil
    }

    /// Case-insensitive, whitespace-trimmed address equality. EVM addresses are
    /// case-insensitive (checksum-only casing); other chains echo verbatim, so a
    /// trimmed case-insensitive compare is the safe superset.
    private static func addressesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let l = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.isEmpty, !r.isEmpty else { return false }
        return l.compare(r, options: .caseInsensitive) == .orderedSame
    }
}
