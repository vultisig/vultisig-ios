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

    /// What the summary should render for this transaction.
    ///
    /// The distinction between `.unreviewable` and "not a TrustSet" is the whole
    /// point: whether an operation IS a TrustSet is decided by the discriminator
    /// alone, never by whether we managed to render it. Keying the UI off a
    /// successful render would drop an unrenderable TrustSet into the ordinary
    /// Payment rows — showing `toAddress` as a recipient and the LIMIT as a
    /// transfer — which is exactly the false review a co-signer must never be
    /// given.
    enum State: Equatable {
        /// Not an XRPL TrustSet — render the transaction normally.
        case notTrustSet
        /// A TrustSet whose terms can be shown.
        case reviewable(Display)
        /// A TrustSet whose token id, currency or amount cannot be read, so its
        /// real terms cannot be shown. The signer refuses these payloads too, so
        /// nothing can be signed from here — but the review surface has to say so
        /// rather than fall back to describing a payment.
        case unreviewable
    }

    /// Whether `payload` is an XRPL TrustSet, decided by the wire discriminator
    /// alone.
    static func isTrustSet(payload: KeysignPayload?) -> Bool {
        guard let payload, payload.coin.chain == .ripple else { return false }
        guard case .Ripple(_, _, _, _, let transactionType) = payload.chainSpecific else { return false }
        return transactionType == VSTransactionType.rippleTrustSet.rawValue
    }

    /// Render state for a co-signer, from the payload it holds.
    static func state(for payload: KeysignPayload?) -> State {
        guard isTrustSet(payload: payload) else { return .notTrustSet }
        return display(for: payload).map(State.reviewable) ?? .unreviewable
    }

    /// Render state for the initiator, from the transaction it is about to turn
    /// into a payload.
    static func state(for tx: SendTransaction) -> State {
        guard tx.coin.chain == .ripple, tx.transactionType == .rippleTrustSet else { return .notTrustSet }
        return display(for: tx).map(State.reviewable) ?? .unreviewable
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

    // MARK: - Done screen

    /// Done-screen hero for a TrustSet, from a CO-SIGNER's payload.
    ///
    /// A TrustSet's `toAmount` is the trust-line LIMIT, not a transfer. The
    /// default done slot renders `toAmountWithTickerString`, so without a hero
    /// the screen announces a quadrillion-token payment that never happened —
    /// and prices it in fiat. Supplying a hero replaces that block outright
    /// (`DoneTokenContent` prefers `hero` over the coin amount), which is the
    /// same escape hatch the limit-order cancel uses for the same reason: the
    /// transaction is not a transfer and must not be described as one.
    ///
    /// The limit is deliberately NOT the caption. It belongs on the screens
    /// where the user is deciding whether to sign it — the reserve sheet and the
    /// verify summary — not on the receipt for a decision already made. The
    /// issuer is what identifies WHICH line was opened.
    static func hero(for payload: KeysignPayload?) -> HeroContent? {
        display(for: payload).map(heroContent)
    }

    /// The same hero for the INITIATOR, whose done screen is driven by the
    /// transaction rather than by a payload.
    static func hero(for tx: SendTransaction) -> HeroContent? {
        display(for: tx).map(heroContent)
    }

    private static func heroContent(for display: Display) -> HeroContent {
        .title(
            text: String(format: "rippleTrustLineHeroTitle".localized, display.ticker),
            caption: display.issuer
        )
    }
}
