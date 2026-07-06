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
        guard let quote = transaction.quote else {
            // An external recipient with no quote (e.g. a limit order, which
            // never sets one) has no verifiable output target — fail closed.
            logger.error("[recipient-verify] external recipient set but no quote to verify against")
            throw SwapError.recipientVerificationFailed
        }
        try verify(quote: quote, recipient: recipient)
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
            // field; that memo is signed verbatim. Parse DESTADDR explicitly (the
            // 3rd colon-delimited field of `=:ASSET:DESTADDR:LIM/...`) and assert
            // it equals the recipient — a substring check could false-pass on a
            // recipient that merely appears elsewhere in the memo.
            guard let destination = memoDestination(from: thorQuote.memo),
                  addressesMatch(destination, recipient) else {
                logger.error("[recipient-verify] THOR/Maya memo destination does not match the recipient")
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

        case .oneinch, .kyberswap, .lifi, .jupiter:
            // These providers bury the recipient inside opaque router calldata
            // with no verifiable echo, so they are never eligible when an
            // external recipient is set (`SwapProvider.honorsExternalRecipient`).
            // Reaching here means the recipient gate let one through — fail
            // closed rather than sign an unverifiable output target.
            logger.error("[recipient-verify] provider cannot expose a verifiable output target for an external recipient")
            throw SwapError.recipientVerificationFailed
        }
    }

    /// Extract DESTADDR from a THOR/Maya swap memo (`=:ASSET:DESTADDR:LIM/...`):
    /// the 3rd colon-delimited field. The ASSET field never contains a colon, so
    /// splitting on `:` isolates the destination cleanly. Returns nil when the
    /// memo is malformed or the field is empty.
    private static func memoDestination(from memo: String) -> String? {
        let parts = memo.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let destination = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        return destination.isEmpty ? nil : destination
    }

    /// Whitespace-trimmed address equality. Hex/EVM addresses differ only by
    /// checksum casing, so they compare case-insensitively; every other encoding
    /// (bech32, base58, …) is case-sensitive and must match exactly — a blanket
    /// case-insensitive compare there could false-pass two distinct addresses.
    private static func addressesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let l = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.isEmpty, !r.isEmpty else { return false }
        if isHexAddress(l), isHexAddress(r) {
            return l.compare(r, options: .caseInsensitive) == .orderedSame
        }
        return l == r
    }

    /// A 20-byte hex address (optional `0x` prefix + 40 hex digits) — the EVM
    /// address shape whose casing is checksum-only and therefore safe to ignore.
    private static func isHexAddress(_ value: String) -> Bool {
        let raw = value.hasPrefix("0x") || value.hasPrefix("0X") ? String(value.dropFirst(2)) : value
        return raw.count == 40 && raw.allSatisfy(\.isHexDigit)
    }
}
