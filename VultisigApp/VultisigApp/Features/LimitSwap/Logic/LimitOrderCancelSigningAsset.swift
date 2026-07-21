//
//  LimitOrderCancelSigningAsset.swift
//  VultisigApp
//
//  Which asset this device must hold to send a given order's cancel.
//
//  NOT the order's own asset — a cancel moves no tokens. It is the gas asset of
//  the chain the cancel is SENT FROM, and that chain depends on how the order
//  was funded: a THORChain-sourced order cancels via a `MsgDeposit` paid in
//  RUNE, while every other order cancels by sending a memo-bearing dust transfer
//  from the chain that funded it.
//
//  Split out as a value because the disabled-button copy has to name it. A
//  single "add RUNE" line was correct while cancelling was THORChain-only and
//  became wrong the moment the L1 route landed: it tells the owner of a
//  BTC-funded order to fund a chain their cancel will never touch.
//

import Foundation

/// The asset a cancel must be signed with, named for a user.
struct LimitOrderCancelSigningAsset: Equatable, Sendable {
    /// Ticker as the wallet shows it — `RUNE`, `BTC`, `ATOM`.
    let ticker: String
    /// Chain as the wallet names it — `THORChain`, `Bitcoin`, `Cosmos`.
    let chainName: String
}

/// The asset `details` needs to be cancelled, or `nil` when the source chain is
/// unknown or unrecorded — in which case the order is not cancellable at all and
/// `limitOrderCancelEligibility` has already said so for a better reason.
func limitOrderCancelSigningAsset(for details: LimitOrderDetails) -> LimitOrderCancelSigningAsset? {
    guard let rawValue = details.sourceChainRawValue,
          let chain = Chain(rawValue: rawValue) else {
        return nil
    }
    return limitOrderCancelSigningAsset(for: chain)
}

func limitOrderCancelSigningAsset(for chain: Chain) -> LimitOrderCancelSigningAsset {
    LimitOrderCancelSigningAsset(
        ticker: cancelSigningTicker(for: chain),
        chainName: chain.name
    )
}

/// The chain's native ticker as a HUMAN reads it.
///
/// `Chain.ticker` is not that everywhere: it carries the base-denom spelling for
/// the Cosmos chains (`UATOM`, `UOSMO`), which is correct on the wire and
/// nonsense in a sentence telling someone what to add to their wallet. The
/// wallet's own token metadata is the display source, with `Chain.ticker` as the
/// fallback for anything not in it.
private func cancelSigningTicker(for chain: Chain) -> String {
    TokensStore.findTokenMeta(chain: chain, contractAddress: "")?.ticker ?? chain.ticker
}
