//
//  CustomMemoAssets.swift
//  VultisigApp
//
//  Which of a vault's coins the raw-memo `MsgDeposit` form can deposit
//  against, per chain. The single source of truth for that question.
//
//  It is single deliberately. The legacy form answered it with an exact ticker
//  allowlist while the legacy dropdown's default answered a *different*
//  question with a different relation — any THORChain ticker containing "TCY"
//  opened this form — so a holder of `sTCY` or `yTCY` was routed to a form
//  whose picker could not offer the coin they were routed there for. One
//  predicate, expressed once, is what stops the two from drifting again.
//

import Foundation

enum CustomMemoAssets {

    /// The vault's coins on `chain` that this form can deposit with, in the
    /// order the vault holds them.
    ///
    /// A `Coin` list rather than a ticker list: the picked coin *is* the coin
    /// the deposit is built against. Legacy listed ticker strings and appended
    /// a fallback ticker the vault did not hold, which satisfied its
    /// "token selected" gate while resolving to no coin at all — the deposit
    /// was then built against whatever coin the screen happened to hold while
    /// the dropdown named another one.
    static func depositableCoins(in vault: Vault, on chain: Chain) -> [Coin] {
        vault.coins.filter { $0.chain == chain && supports(ticker: $0.ticker, on: chain) }
    }

    /// Whether `ticker` names an asset the custom form offers on `chain`.
    static func supports(ticker: String, on chain: Chain) -> Bool {
        let ticker = ticker.uppercased()
        switch chain {
        case .thorChain, .thorChainChainnet, .thorChainStagenet:
            // The test networks are listed with mainnet: they run the same
            // `MsgDeposit`, and leaving them out left the picker empty, which
            // made the form permanently unsubmittable — an operation the app
            // offered but could not send.
            return ticker == "RUNE" || ticker == "RUJI" || isTcyFamily(ticker: ticker)
        case .mayaChain:
            return ticker == "CACAO" || ticker == "MAYA" || ticker == "AZTEC"
        default:
            return false
        }
    }

    /// TCY and its wrappers, as one relation.
    ///
    /// This is the predicate the legacy dropdown default used to decide that a
    /// holder belongs on this form, and it is now also the one the form's own
    /// picker uses, so the two cannot answer differently for the same coin —
    /// which is exactly how a holder of a wrapper ended up on a form that could
    /// not offer their coin. Case-insensitive, because the original was not and
    /// a lowercase spelling split the two answers apart.
    ///
    /// Deliberately a substring rather than an enumerated set. It is loose in
    /// one direction only: an unrelated ticker that happens to contain "TCY"
    /// would be offered as a deposit asset on the operation whose entire remit
    /// is "deposit against whatever you hold, with whatever memo you like".
    /// A miss in the other direction is the dead end this predicate exists to
    /// close, and would return the next wrapper to it.
    static func isTcyFamily(ticker: String) -> Bool {
        ticker.uppercased().contains("TCY")
    }
}
