//
//  SendCryptoVerifySummary+Presentation.swift
//  VultisigApp
//
//  What the summary shows, decided once for both of its renderings: the
//  joining co-signer's full-screen summary and the initiator's review sheet.
//

extension SendCryptoVerifySummary {
    /// Render state for a Kamino Earn transaction, derived from the KEYSIGN
    /// PAYLOAD on whichever device is rendering.
    ///
    /// Always from the payload, never from the other fields: both the
    /// initiator's review and a co-signer's Join screen render this, and the
    /// whole value of the decode is that each device derives the claim from
    /// the bytes it is about to sign rather than from anything it was told.
    ///
    /// Cheap for everything else — the guard inside is `signSolana == nil`,
    /// which every non-raw-Solana payload fails immediately.
    var kaminoState: KaminoVerifyPresentation.State {
        KaminoVerifyPresentation.state(for: keysignPayload)
    }

    /// Render state for an XRPL TrustSet.
    ///
    /// Taken from the KEYSIGN PAYLOAD whenever one is present, so a co-signer
    /// reads the transaction it is about to sign rather than anything the
    /// initiator claims about it. `rippleTrustSet` covers the initiator's
    /// review, which renders before its payload is built.
    var rippleTrustSetState: RippleTrustSetPresentation.State {
        let fromPayload = RippleTrustSetPresentation.state(for: keysignPayload)
        guard fromPayload == .notTrustSet else { return fromPayload }
        return rippleTrustSet
    }

    /// Terms to render, when they can be read at all.
    var reviewableRippleTrustSet: RippleTrustSetPresentation.Display? {
        guard case .reviewable(let display) = rippleTrustSetState else { return nil }
        return display
    }

    /// True for ANY TrustSet, readable or not — the flag that must gate every
    /// Payment-shaped row, so an unreviewable TrustSet can never borrow them.
    var isRippleTrustSet: Bool {
        rippleTrustSetState != .notTrustSet
    }

    /// True when the hero doesn't already show a resolved amount/coin, so the
    /// "amount" detail row should render with the fallback `tokenDisplay` value.
    var shouldShowAmountRow: Bool {
        // signSui carries no to_amount; the value lives in the PTB bytes.
        if keysignPayload?.signSui != nil {
            return false
        }
        // A TrustSet's amount IS the limit, rendered as its own labelled row (or
        // withheld when unreadable). Showing it as "amount" would read as a
        // transfer.
        if isRippleTrustSet {
            return false
        }
        // signRipple carries the amount inside the raw JSON (and offers have no
        // amount at all); the decoded terms render it below.
        if keysignPayload?.signRipple != nil {
            return false
        }
        switch hero {
        // Projected settlement does not replace disclosure of the signed amount.
        case nil, .title, .projected:
            return true
        case .send, .receive, .swap:
            return false
        }
    }

    var hasTransactionDetails: Bool {
        let hasSignature = !(decodedFunctionSignature?.isEmpty ?? true)
        let hasArguments = !(decodedFunctionArguments?.isEmpty ?? true)
        return hasSignature || hasArguments
    }
}
