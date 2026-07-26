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
    /// The source coin declares a precision that cannot express THORChain's
    /// threshold at all, so there is no honest amount to attach.
    case unusableChainPrecision(chain: String, decimals: Int)
    /// The computed dust exceeded what this chain could plausibly require.
    ///
    /// `dust_threshold` is a REMOTE value that directly decides how much of the
    /// user's money is irreversibly donated — there is no refund path for
    /// anything attached to an `m=<`. A wrong or hostile value would otherwise
    /// be honoured verbatim and then doubled. Every other floor in this file is
    /// a lower bound; this is the only upper one.
    case dustAmountExceedsCeiling(chain: String, computed: String, ceiling: String)
    /// The computed dust is too small for THORChain to observe at all.
    ///
    /// ⚠️ The loud failure that the 2026-07-22 ETH rehearsal needed and did not
    /// have. That cancel was signed for **2000 wei** — the 1e8-unit threshold
    /// used verbatim as an 18-decimal chain's smallest unit — which THORChain's
    /// `ConvertAmount` truncates to zero. Bifrost never saw an inbound, the
    /// transaction confirmed on Ethereum, ~0.00016 ETH of gas was burned, and
    /// the order carried on resting. Nothing distinguished it from success.
    ///
    /// Refusing is deliberately preferred over quietly raising the amount: a
    /// value that lands here means the pipeline that produced it is wrong, and
    /// bumping it to the bare observable minimum would still be under whatever
    /// THORChain actually requires — the same silent failure, one order of
    /// magnitude up.
    case dustBelowObservableMinimum(chain: String, computed: String, minimum: String)
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
///
/// ⚠️ **The two floors are quoted in different unit systems.** WalletCore's is
/// already in the chain's own smallest units; THORChain's is in ITS 1e8 fixed
/// point, on every chain, whatever precision that chain uses. They are only
/// comparable after `chainSmallestUnits(fromThorchainBaseUnits:decimals:)` — see
/// `dustBelowObservableMinimum` for what shipping them uncompared cost.
///
/// - Parameter decimals: the SOURCE COIN's own precision. Load-bearing, not
///   cosmetic: it is the entire difference between 2e13 wei and 2000 wei.
/// - Parameter ceiling: the most this chain could plausibly require, in the same
///   smallest units. See `dustAmountExceedsCeiling` — this is the guard against
///   a remote value deciding how much of the user's money to give away.
func limitOrderCancelDustAmount(
    walletCoreDustFloor: BigInt,
    inboundDustThreshold: String?,
    decimals: Int,
    ceiling: BigInt,
    chainSymbol: String
) throws -> BigInt {
    guard let inboundDustThreshold else {
        throw LimitOrderCancelDustError.inboundDustThresholdUnavailable(chain: chainSymbol)
    }
    guard decimals >= 0 else {
        throw LimitOrderCancelDustError.unusableChainPrecision(chain: chainSymbol, decimals: decimals)
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
    // Rescaled BEFORE the comparison. Taking the larger of a 1e8 figure and a
    // native one is not a comparison at all on any chain whose precision isn't 8.
    let thresholdInChainUnits = chainSmallestUnits(fromThorchainBaseUnits: threshold, decimals: decimals)
    let floor = max(walletCoreDustFloor, thresholdInChainUnits)
    let amount = floor * limitOrderCancelDustSafetyMultiple
    // A zero-value L1 transaction carries no inbound for Bifrost to observe —
    // and neither does one whose value truncates to zero in THORChain's own 1e8
    // accounting, which is the same invisibility arrived at by arithmetic rather
    // than by a literal zero.
    let observableMinimum = minimumObservableInbound(decimals: decimals)
    guard amount >= observableMinimum else {
        throw LimitOrderCancelDustError.dustBelowObservableMinimum(
            chain: chainSymbol,
            computed: amount.description,
            minimum: observableMinimum.description
        )
    }
    guard amount <= ceiling else {
        throw LimitOrderCancelDustError.dustAmountExceedsCeiling(
            chain: chainSymbol,
            computed: amount.description,
            ceiling: ceiling.description
        )
    }
    return amount
}

/// Re-express an amount THORChain quotes in its own 1e8 fixed point as the
/// source chain's smallest units.
///
/// ⚠️ **Every amount on `inbound_addresses` is 1e8, regardless of the chain.**
/// THORNode normalises inbound values through `ConvertAmount` on the way in and
/// publishes its thresholds in that same normalised space. The 8-decimal UTXO
/// chains make the conversion the identity, which is precisely why reading the
/// threshold as if it were already native survived a whole test suite and a
/// mainnet rehearsal: BTC, LTC and DOGE cannot show the bug. An 18-decimal chain
/// can, and did — 1000 became 2000 wei instead of 2e13.
///
/// Rounds UP when the chain carries FEWER decimals than THORChain (GAIA's 6).
/// The value is a floor that has to be cleared, and truncation would land it a
/// unit short of exactly the threshold it exists to satisfy.
func chainSmallestUnits(fromThorchainBaseUnits value: BigInt, decimals: Int) -> BigInt {
    guard decimals != Coin.thorchainFixedPointExponent else { return value }
    if decimals > Coin.thorchainFixedPointExponent {
        return value * BigInt(10).power(decimals - Coin.thorchainFixedPointExponent)
    }
    let divisor = BigInt(10).power(Coin.thorchainFixedPointExponent - decimals)
    let (quotient, remainder) = value.quotientAndRemainder(dividingBy: divisor)
    return remainder == 0 ? quotient : quotient + 1
}

/// The smallest amount on a `decimals`-precision chain that THORChain can still
/// see, in that chain's smallest units.
///
/// Anything below this is truncated to zero by `ConvertAmount` on the way into
/// THORChain's 1e8 accounting, so Bifrost never raises an inbound for it: the
/// transaction confirms on the source chain, the fee is spent, and THORChain
/// never learns it happened.
///
/// On an 18-decimal chain this evaluates to 1e10 — independently the same figure
/// the protocol research recorded as the EVM minimum, derived there from
/// `ConvertAmount` truncating below it.
func minimumObservableInbound(decimals: Int) -> BigInt {
    guard decimals > Coin.thorchainFixedPointExponent else { return BigInt(1) }
    return BigInt(10).power(decimals - Coin.thorchainFixedPointExponent)
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
/// Set roughly an order of magnitude above each chain's live `dust_threshold`
/// doubled — the amount a cancel actually attaches. Loose enough that a
/// legitimate threshold change does not break cancelling, tight enough that a
/// bad value cannot quietly donate a meaningful sum. If a chain legitimately
/// raises its threshold past this, cancelling fails loudly with the computed and
/// permitted values — which is the right way to find out.
///
/// ⚠️ Sized against the thresholds `inbound_addresses` actually publishes
/// (captured 2026-07-22, natural units): DOGE 1, LTC 0.001, AVAX 0.001,
/// GAIA 0.01, BCH/BSC 0.0001, BTC/ETH 0.00001. The earlier table was sized
/// against the EVM `ConvertAmount` floor (~1e-8) rather than against these, and
/// so sat BELOW the real attach on both LTC and AVAX — a legitimate cancel on
/// either would have been refused outright by the ceiling.
func limitOrderCancelDustCeiling(for chain: Chain) -> Decimal {
    switch chain {
    case .dogecoin:
        // The outlier: a 1 DOGE threshold, so 2 DOGE is the normal attach.
        return 10
    case .litecoin, .avalanche:
        // Both publish a 0.001 threshold, so 0.002 is the normal attach — over
        // the 0.001 these two used to share with BTC.
        return Decimal(string: "0.02") ?? 0
    case .bitcoin, .bitcoinCash, .dash, .zcash:
        return Decimal(string: "0.001") ?? 0
    case .gaiaChain, .noble:
        return Decimal(string: "0.5") ?? 0
    default:
        // ETH (0.00002 attach), BSC (0.0002) and anything else. Immaterial in
        // fiat on every supported chain while still leaving room for a
        // threshold that moves by an order of magnitude.
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
/// reaches 83–91 bytes and cannot fit the 80-byte `OP_RETURN` cap. Reference
/// memos (`r:<id>`) are the real fix for that and need their own registration
/// transaction — deliberately out of scope here.
///
/// ⚠️ **Measure the memo that will actually be SIGNED.** A contract address is
/// 42 characters against the 6 the placement memo abbreviates it to, so sizing
/// the abbreviated spelling understates a cancel by 36 bytes per token leg —
/// enough to pass a UTXO source that then cannot possibly fit. The 2026-07-21
/// rehearsal sized 49 bytes for a memo that is 85; the gate said yes about a
/// string that was never going to be broadcast. `limitOrderCancelEligibility`
/// is the only caller and it builds the memo from the resolved full spellings
/// immediately before this — keep it that way.
func limitOrderCancelMemoFits(_ memo: String, sourceChainKind: ChainType) -> Bool {
    memo.utf8.count <= limitMemoByteLimit(for: sourceChainKind)
}

// MARK: - Exact base-units → natural-units string

/// Render `value` in the coin's natural units EXACTLY, as a plain decimal
/// string, using only integer arithmetic on the digits.
///
/// ⚠️ **Never use a display formatter for this.** The result is handed to the
/// send pipeline as the transaction's amount, and this codebase's display
/// helpers round (and `String.toDecimal()` parses through a Double-backed
/// `NumberFormatter`, which loses precision past ~16 significant digits). An
/// 18-decimal chain's dust threshold is a small number with many decimal
/// places: rounded at display precision it can shrink, and a dust amount that
/// shrinks below THORChain's `dust_threshold` is silently ignored by Bifrost —
/// the transaction confirms, the fee is spent, and nothing is cancelled.
///
/// Locale-independent by construction: it never goes through a formatter, so a
/// comma-decimal locale cannot corrupt it either.
func exactNaturalUnitsString(_ value: BigInt, decimals: Int) -> String {
    guard decimals > 0 else { return value.description }
    let digits = value.description
    let negative = digits.hasPrefix("-")
    let magnitude = negative ? String(digits.dropFirst()) : digits
    let padded = String(repeating: "0", count: max(0, decimals + 1 - magnitude.count)) + magnitude
    let splitIndex = padded.index(padded.endIndex, offsetBy: -decimals)
    let whole = String(padded[..<splitIndex])
    // Trailing zeros are cosmetic here, but trimming them keeps the amount
    // identical to what the user is shown and avoids a needlessly long string.
    let fraction = String(padded[splitIndex...]).replacingOccurrences(
        of: "0+$", with: "", options: .regularExpression
    )
    let sign = negative ? "-" : ""
    return fraction.isEmpty ? "\(sign)\(whole)" : "\(sign)\(whole).\(fraction)"
}
