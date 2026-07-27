//
//  RippleTrustSetPresentation.swift
//  VultisigApp
//

import Foundation
import VultisigCommonData

/// What a co-signer is shown for an XRPL `TrustSet`.
///
/// A TrustSet has no destination and no transfer amount, so the Payment rows are
/// all wrong for it: the "to" row would show an address the transaction never
/// pays, and the "amount" row would present a trust-line LIMIT as if funds were
/// moving. It gets its own row set instead — issuer, currency, and the limit
/// being signed.
///
/// Everything here is derived from the KEYSIGN PAYLOAD alone, deliberately. A
/// Secure Vault co-signer holds nothing else: these rows are the only thing
/// between a peer device and a blind signature, so they cannot depend on state
/// only the initiator has.
enum RippleTrustSetPresentation {

    struct Display: Equatable {
        /// Human-readable ticker of the currency being trusted.
        let ticker: String
        /// On-ledger currency code as it will be signed.
        let currencyCode: String
        /// Account whose currency is being trusted.
        let issuer: String
        /// Trust-line limit, as the XRPL value string that goes on the wire.
        let limitValue: String
    }

    /// Whether `payload` is an XRPL TrustSet.
    static func isTrustSet(payload: KeysignPayload?) -> Bool {
        guard let payload, payload.coin.chain == .ripple else { return false }
        guard case .Ripple(_, _, _, _, let transactionType) = payload.chainSpecific else { return false }
        return transactionType == VSTransactionType.rippleTrustSet.rawValue
    }

    /// The rows to show for a TrustSet, or `nil` when the payload is not one (or
    /// carries a token id / amount that cannot be rendered — in which case the
    /// signer will refuse it anyway, and showing nothing is better than showing a
    /// guess).
    static func display(for payload: KeysignPayload?) -> Display? {
        guard isTrustSet(payload: payload), let payload else { return nil }

        guard let (currency, issuer) = try? RippleIssuedCurrency.parseRippleTokenId(payload.coin.contractAddress),
              let currencyCode = try? RippleIssuedCurrency.toXrplCurrencyCode(currency),
              let limitValue = try? RippleIssuedCurrency.formatIssuedCurrencyValue(
                  amount: payload.toAmount,
                  decimals: payload.coin.decimals
              ) else {
            return nil
        }

        return Display(
            ticker: RippleIssuedCurrency.toIssuedCurrencyTicker(currencyCode),
            currencyCode: currencyCode,
            issuer: issuer,
            limitValue: limitValue
        )
    }

    /// The same rows for the INITIATOR, whose Verify screen renders before any
    /// keysign payload exists (it is built on confirm). Reads the identical
    /// fields off the transaction that will produce that payload, so the two
    /// surfaces cannot present different numbers.
    static func display(for tx: SendTransaction) -> Display? {
        guard tx.coin.chain == .ripple, tx.transactionType == .rippleTrustSet else { return nil }

        guard let (currency, issuer) = try? RippleIssuedCurrency.parseRippleTokenId(tx.coin.contractAddress),
              let currencyCode = try? RippleIssuedCurrency.toXrplCurrencyCode(currency),
              let limitValue = try? RippleIssuedCurrency.formatIssuedCurrencyValue(
                  amount: tx.amountInRaw,
                  decimals: tx.coin.decimals
              ) else {
            return nil
        }

        return Display(
            ticker: RippleIssuedCurrency.toIssuedCurrencyTicker(currencyCode),
            currencyCode: currencyCode,
            issuer: issuer,
            limitValue: limitValue
        )
    }
}
