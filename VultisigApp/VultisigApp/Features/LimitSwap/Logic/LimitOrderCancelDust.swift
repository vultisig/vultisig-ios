//
//  LimitOrderCancelDust.swift
//  VultisigApp
//
//  How much to attach to a cancel sent FROM an L1 chain, and whether the cancel
//  memo will even fit on that chain.
//
//  Both are pure and both fail closed, because both failure modes are silent:
//  an under-funded cancel is dropped by Bifrost before it becomes a
//  `MsgObservedTxIn`, and an over-long memo is truncated into nonsense. Either
//  way the fee is spent, nothing is cancelled, and the client sees no error.
//

import BigInt
import Foundation

enum LimitOrderCancelDustError: Error, Equatable {
    /// THORChain's `inbound_addresses` row carried no `dust_threshold` for this
    /// chain, so the minimum that Bifrost will actually observe is unknown.
    ///
    /// Deliberately fatal rather than defaulted. Guessing low means the cancel
    /// is silently ignored — the exact failure this value exists to prevent —
    /// and guessing high donates more of the user's funds than necessary.
    case inboundDustThresholdUnavailable(chain: String)
    case malformedInboundDustThreshold(chain: String, value: String)
    /// The computed dust exceeded what this chain could plausibly require.
    ///
    /// `dust_threshold` is a REMOTE value that directly decides how much of the
    /// user's money is irreversibly donated — there is no refund path for
    /// anything attached to an `m=<`. A wrong or hostile value would otherwise
    /// be honoured verbatim and then doubled. Every other floor in this file is
    /// a lower bound; this is the only upper one.
    case dustAmountExceedsCeiling(chain: String, computed: String, ceiling: String)
}

/// Safety multiple applied over the larger of the two floors.
///
/// A cancel sitting exactly ON a threshold is a coin-flip: THORNode's own
/// comparisons are not uniformly `>=`, and the published threshold can move
/// between our inbound fetch and the transaction actually landing. Doubling
/// removes both without a magic absolute floor that would be wrong on some
/// chain's units (10,000 is dust on ETH and about $10 on BTC).
///
/// Matches the multiple used by Unstoppable Wallet, the only other wallet
/// shipping L1 limit-order cancellation, so this is a value observed to work in
/// production rather than one derived from the docs alone.
///
/// ⚠️ The cost is real and lands on the user: everything attached to an `m=<`
/// is `donateToPool`'d with no refund path, so doubling doubles that donation.
/// It is bounded by the dust amount itself and disclosed in the confirmation
/// UI. Worth re-tuning against a mainnet rehearsal before widening further.
let limitOrderCancelDustSafetyMultiple = BigInt(2)

/// The amount to attach to an L1-originated cancel, in the source chain's
/// smallest units.
///
/// Two independent floors have to be cleared and they are enforced by different
/// systems:
///
/// - **WalletCore's dust floor** (`CoinType.getFixedDustThreshold`) — local. A
///   UTXO output below it is refused by the signer before anything is broadcast.
/// - **THORChain's `dust_threshold`** — remote. Bifrost ignores an inbound
///   below it, so the transaction confirms on the source chain and THORChain
///   never sees it. This is the dangerous one: it looks exactly like success.
///
/// `dust_threshold` had **no readers anywhere in this codebase** before this —
/// it was decoded off `inbound_addresses` and discarded — which is why the
/// second floor could be missed entirely.
/// - Parameter ceiling: the most this chain could plausibly require, in the same
///   smallest units. See `dustAmountExceedsCeiling` — this is the guard against
///   a remote value deciding how much of the user's money to give away.
func limitOrderCancelDustAmount(
    walletCoreDustFloor: BigInt,
    inboundDustThreshold: String?,
    ceiling: BigInt,
    chainSymbol: String
) throws -> BigInt {
    guard let inboundDustThreshold else {
        throw LimitOrderCancelDustError.inboundDustThresholdUnavailable(chain: chainSymbol)
    }
    // Both floors are validated, not just the parsed one. A negative local floor
    // would silently lose to `max` and read as "no local requirement", which is
    // the kind of quiet degradation this file exists to avoid.
    guard let threshold = BigInt(inboundDustThreshold), threshold >= 0 else {
        throw LimitOrderCancelDustError.malformedInboundDustThreshold(
            chain: chainSymbol,
            value: inboundDustThreshold
        )
    }
    guard walletCoreDustFloor >= 0 else {
        throw LimitOrderCancelDustError.malformedInboundDustThreshold(
            chain: chainSymbol,
            value: "local floor \(walletCoreDustFloor)"
        )
    }
    let floor = max(walletCoreDustFloor, threshold)
    // A chain reporting 0 for both floors still needs a non-zero output — a
    // zero-value L1 transaction carries no inbound for Bifrost to observe.
    let amount = max(floor * limitOrderCancelDustSafetyMultiple, BigInt(1))
    guard amount <= ceiling else {
        throw LimitOrderCancelDustError.dustAmountExceedsCeiling(
            chain: chainSymbol,
            computed: amount.description,
            ceiling: ceiling.description
        )
    }
    return amount
}

/// The most a cancel on `chain` could plausibly need to attach, in NATURAL
/// units. Multiplied out to smallest units by the caller.
///
/// Deliberately an explicit table rather than a formula. The per-chain minima
/// are known and verified, but they live in wildly different unit systems (wei
/// vs sats vs uatom), so no single absolute number and no ratio against
/// WalletCore's floor works across all of them — `getFixedDustThreshold()`
/// returns 0 for every non-UTXO chain, which would collapse any relative bound.
///
/// Set roughly an order of magnitude above each chain's verified minimum: loose
/// enough that a legitimate threshold change does not break cancelling, tight
/// enough that a bad value cannot quietly donate a meaningful sum. If a chain
/// legitimately raises its threshold past this, cancelling fails loudly with the
/// computed and permitted values — which is the right way to find out.
func limitOrderCancelDustCeiling(for chain: Chain) -> Decimal {
    switch chain {
    case .dogecoin:
        // The outlier: a 1 DOGE minimum, so 2 DOGE is the normal attach.
        return 10
    case .bitcoin, .bitcoinCash, .litecoin, .dash, .zcash:
        return Decimal(string: "0.001") ?? 0
    case .gaiaChain, .noble:
        return Decimal(string: "0.5") ?? 0
    default:
        // EVM gas assets and anything else: the verified EVM minimum is ~1e-8
        // of the gas asset, so this is many orders of magnitude of headroom
        // while still being immaterial in fiat on every supported chain.
        return Decimal(string: "0.001") ?? 0
    }
}

// MARK: - Memo length

/// Whether the cancel memo fits the source chain's per-transaction memo budget.
///
/// ⚠️ **A cancel memo has no slack to give.** The PLACEMENT memo can be squeezed
/// by rounding its LIM up to fewer significant figures (`buildFittedLimitSwapMemo`),
/// because a higher minimum-output is still a safe order. A cancel memo carries
/// two exact `<amount><ASSET>` coins whose values must reproduce THORChain's
/// ratio bucket bit-for-bit — round either and it addresses a different bucket
/// and matches nothing. Nor can the assets be shortened: `getCoin` routes
/// through `cosmos.ParseCoins`, whose denom regex needs 3+ characters, so
/// THORChain's asset short codes are rejected here even though they work in a
/// swap memo; and `ModifyLimitSwapMemo` is the one inbound memo type that
/// `processOneTxIn` does not run through `fuzzyAssetMatch`, so a contract-suffixed
/// asset must be spelled in full.
///
/// So this is a yes/no gate, not a fitting routine. In practice gas-asset pairs
/// land around 37–44 bytes and fit anywhere; an ERC20 target from a UTXO source
/// reaches 85–91 bytes and cannot fit the 80-byte `OP_RETURN` cap. Reference
/// memos (`r:<id>`) are the real fix for that and need their own registration
/// transaction — deliberately out of scope here.
func limitOrderCancelMemoFits(_ memo: String, sourceChainKind: ChainType) -> Bool {
    memo.utf8.count <= limitMemoByteLimit(for: sourceChainKind)
}
