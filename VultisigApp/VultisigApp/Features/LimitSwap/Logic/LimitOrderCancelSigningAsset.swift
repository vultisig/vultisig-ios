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

/// Whether this device can sign a given order's cancel — and, when it cannot,
/// whether we actually KNOW why.
///
/// ⚠️ The three-way split exists because two of these look identical from a
/// `nil` coin and mean opposite things to a user. "Your vault does not hold
/// RUNE" is actionable advice; giving it when the vault could not be READ sends
/// someone to acquire an asset they may already own. Fail closed on the unknown
/// instead — the same rule `limitOrderCancelEligibility` applies to every other
/// thing this feature cannot prove.
enum LimitOrderCancelSigningAvailability: Equatable {
    /// The vault was read and holds the coin that signs this cancel.
    case available(Coin)
    /// The vault was read and demonstrably does NOT hold it. Only this case
    /// earns the "add %@ to this vault" copy.
    case missing(LimitOrderCancelSigningAsset)
    /// The vault could not be read, so nothing can be said about what it holds.
    case unknown
}

/// What `vault` can tell us about signing `details`' cancel.
///
/// - Parameter vault: `nil` means the vault could not be read — a lookup that
///   threw, or one that found nothing. It does NOT mean an empty vault, and the
///   distinction is the whole point of this function.
///
/// Pure, and separated from the lookup that can fail, so the branch that matters
/// is testable without SwiftData.
@MainActor
func limitOrderCancelSigningAvailability(
    for details: LimitOrderDetails,
    in vault: Vault?
) -> LimitOrderCancelSigningAvailability {
    guard let rawValue = details.sourceChainRawValue,
          let sourceChain = Chain(rawValue: rawValue) else {
        // No recorded source chain, so there is no asset to name. The order is
        // uncancellable for a better reason and `limitOrderCancelEligibility`
        // has already said so; adding a second, vaguer message would only
        // compete with it.
        return .unknown
    }
    guard let vault else { return .unknown }
    if let coin = limitOrderCancelSigningCoin(in: vault, sourceChain: sourceChain) {
        return .available(coin)
    }
    return .missing(limitOrderCancelSigningAsset(for: sourceChain))
}

/// The coin in `vault` that signs a cancel for an order funded on `sourceChain`.
///
/// A THORChain-sourced order cancels via `MsgDeposit` paid in RUNE. Everything
/// else cancels by sending the memo from the chain that funded it, so it needs
/// that chain's NATIVE gas coin — never the order's own asset, since a cancel
/// moves no tokens.
///
/// `isRune` rather than `chain == .thorChain && isNativeToken` for the THOR case:
/// the latter admits any THORChain coin flagged native, so duplicated or
/// malformed persisted coin data could hand the flow a coin that isn't RUNE.
@MainActor
func limitOrderCancelSigningCoin(in vault: Vault, sourceChain: Chain) -> Coin? {
    if sourceChain == .thorChain {
        return vault.coins.first(where: { $0.isRune })
    }
    return vault.coins.first(where: { $0.chain == sourceChain && $0.isNativeToken })
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
