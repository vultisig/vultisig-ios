//
//  LimitSwapCancelMemoBuilder.swift
//  VultisigApp
//
//  Builds THORChain's `m=<` modify-limit-swap memo in its CANCEL form, and
//  decides whether a given order may be cancelled at all.
//
//  Verified against THORNode `develop` (`x/thorchain/memo/memo_modify_limit_swap.go`,
//  `handler_modify_limit_swap.go`, `keeper/v1/keeper_adv_swap_queue.go`).
//  The GitHub mirror is stale; gitlab.com/thorchain/thornode is authoritative.
//

import BigInt
import Foundation

/// THORChain's modify-limit-swap memo prefix. Distinct from `limitSwapMemoPrefix`
/// (`=<:`), which PLACES an order — `m=<:` modifies one that is already resting.
/// Shared by the builder and `isModifyLimitSwapMemo` so the two can't drift.
let modifyLimitSwapMemoPrefix = "m=<:"

/// True when `memo` MODIFIES a resting order — which includes, but is not
/// limited to, cancelling it.
///
/// Named for what it actually matches. A cancel is the special case where the
/// memo's final field is `0`; a non-zero final field re-targets the order
/// instead. This app only ever builds the cancel form (modify is out of scope),
/// so in practice the two coincide here — but a predicate that says "cancel"
/// while matching any modification is the kind of small lie that outlives the
/// assumption that made it true.
///
/// Prefix-matched: everything after the prefix is the order's addressing payload.
func isModifyLimitSwapMemo(_ memo: String?) -> Bool {
    memo?.hasPrefix(modifyLimitSwapMemoPrefix) ?? false
}

/// True when `memo` CANCELS a resting order, rather than merely modifying one.
///
/// The distinction is `ModifiedTargetAmount`, the memo's final field: THORNode
/// branches on `msg.ModifiedTargetAmount.IsZero()` and reads zero as a cancel.
/// Any other value re-targets the order, which is a different action with a
/// different outcome and different words for it.
///
/// This app only ever builds the cancel form, so today the two coincide — which
/// is exactly why the looser predicate is not good enough to key behaviour on.
/// A retarget suppressed from history, or titled "You're cancelling a limit
/// order", would be a lie the day someone builds modify, and it would be a lie
/// in a place nobody thought to look.
func isCancelLimitSwapMemo(_ memo: String?) -> Bool {
    guard let memo, isModifyLimitSwapMemo(memo) else { return false }
    // Fields are colon-separated and the modified target is the last of them.
    // `omittingEmptySubsequences: false` so a trailing `:` yields an empty final
    // field rather than silently promoting the asset before it.
    guard let modifiedTarget = memo.split(separator: ":", omittingEmptySubsequences: false).last else {
        return false
    }
    // Compared NUMERICALLY, the way THORNode's `getUint` reads it — `"00"` is
    // zero there, and a string comparison would call that a retarget. Digits
    // only, so a sign cannot smuggle `"-0"` past an unsigned field.
    guard !modifiedTarget.isEmpty, modifiedTarget.allSatisfy({ $0.isASCII && $0.isNumber }) else {
        return false
    }
    return BigInt(String(modifiedTarget)) == 0
}

/// The `ModifiedTargetAmount` that means "cancel".
///
/// THORNode's handler branches on `msg.ModifiedTargetAmount.IsZero()` — verbatim
/// comment: *"the target is being modified to zero, which is interpreted as a
/// cancel"*. Any non-zero value MODIFIES the order's trade target instead, which
/// is a different feature we deliberately do not build.
private let cancelModifiedTargetAmount = "0"

/// Everything the cancel memo needs, already reduced to the exact integers
/// THORChain itself holds. Held as `BigInt` rather than `String` so a caller
/// cannot hand this an unparsed or negative value.
struct LimitOrderCancelInputs: Equatable, Sendable {
    /// THORChain memo form of the order's SOURCE asset.
    ///
    /// ⚠️ Must carry the token's **full** contract address
    /// (`ETH.USDC-0XA0B86991…`), never the placement memo's 6-character
    /// abbreviation. `ModifyLimitSwapMemo` is the one inbound memo type
    /// `processOneTxIn` does not run through `fuzzyAssetMatch`, so an
    /// abbreviation is taken literally and keys a bucket the order was never
    /// indexed under.
    ///
    /// ⚠️ Must be the asset's **secured** denom (`eth-usdc-0xa0b…`) when the
    /// source is a secured asset — never its layer-1 form (`ETH.USDC-0XA0B…`).
    /// `MsgModifyLimitSwap.ValidateBasic` enforces
    /// `From.IsChain(Source.Asset.GetChain())`, and `Asset.GetChain()` returns
    /// `THORChain` **only** when the asset is a synth, trade or secured asset.
    /// Emitting the layer-1 form makes `GetChain()` report `ETH`, and the cancel
    /// — sent from a THOR address — is then rejected outright at validation.
    /// `thorchainCancelMemoAsset` emits both correctly.
    let sourceAsset: String
    /// The order's deposited source amount in THORChain's 1e8 fixed point.
    let sourceAmount1e8: BigInt
    /// THORChain memo form of the order's TARGET asset, under the same
    /// full-contract rule as `sourceAsset`.
    let targetAsset: String
    /// The order's ORIGINAL trade target (the LIM the placement memo encoded),
    /// in the target asset's 1e8 fixed point.
    let tradeTarget: BigInt
}

enum LimitSwapCancelMemoError: Error, Equatable {
    /// An amount was zero or negative. Both amounts are part of the ratio the
    /// matcher keys on, and a zero trade target would additionally make
    /// THORNode's `getRatio` return the sentinel `"0"` bucket.
    case nonPositiveAmount
    case emptyAsset
    /// An asset carried a truncated token identifier — the placement memo's
    /// 6-character contract suffix, most likely.
    ///
    /// Structural, not advisory. This memo type skips `fuzzyAssetMatch`, so the
    /// abbreviation is never expanded: the cancel is accepted by the chain,
    /// costs a fee, addresses a bucket no order was indexed under, and cancels
    /// nothing. The builder refuses rather than letting those bytes exist.
    case abbreviatedAsset
}

/// Shortest token identifier suffix a cancel memo will accept.
///
/// An EVM contract is 42 characters (`0X` + 40 hex) and the placement memo's
/// abbreviation is 6, so anything in between is a wide, unambiguous gap. Fixed
/// at a length rather than an exact `0X…` pattern so a future asset flavour with
/// a differently-shaped full identifier is not rejected out of hand — the job
/// here is to catch truncation, not to validate contract syntax.
private let minimumFullTokenIdentifierLength = 20

/// Whether a THORChain memo asset carries a token identifier that has been
/// truncated — `ETH.USDC-06EB48` rather than `ETH.USDC-0XA0B86991…`.
///
/// The chain prefix has to be stripped first, and cannot simply be assumed to
/// end at a `.`: a SECURED asset spells the whole thing with `-`, so a secured
/// native denom is `btc-btc` and a secured token is `eth-usdc-0xa0b…`. Reading
/// the tail after the last `-` would call the first of those truncated and make
/// every secured-native order uncancellable.
///
/// So: drop everything up to the first separator (`.` layer-1, `/` synth, `~`
/// trade, `-` secured) — that is the chain — and look at the SYMBOL that
/// follows. A symbol is `TICKER` or `TICKER-<identifier>`, and only the second
/// form can be truncated. `BTC.BTC`, `THOR.RUNE`, `THOR.TCY` and `btc-btc` all
/// carry no identifier at all and are full by construction, which is what keeps
/// a pre-existing order with native legs cancellable.
func thorchainMemoAssetIsAbbreviated(_ asset: String) -> Bool {
    let separators: Set<Character> = [".", "/", "~", "-"]
    let symbol: Substring
    if let chainEnd = asset.firstIndex(where: { separators.contains($0) }) {
        symbol = asset[asset.index(after: chainEnd)...]
    } else {
        symbol = asset[...]
    }
    // A contract carries no `-` of its own, so the first one inside the symbol
    // is the identifier's separator.
    guard let identifierStart = symbol.firstIndex(of: "-") else { return false }
    return symbol[symbol.index(after: identifierStart)...].count < minimumFullTokenIdentifierLength
}

/// Build the `m=<` memo that cancels a resting limit order.
///
/// Wire layout, exactly three fields after the prefix:
///
///     m=<:<SRC_AMOUNT><SRC_ASSET>:<TRADE_TARGET><TGT_ASSET>:0
///
/// Both coins are `<amount><ASSET>` with **no space** — THORNode's `getCoin`
/// scans leading digits and splices the space back in before parsing.
///
/// ⚠️ **Assets are spelled in FULL — never with the placement memo's
/// 6-character contract suffix.** `processOneTxIn` runs every other inbound memo
/// through `fuzzyAssetMatch`, which is what lets a placement say
/// `ETH.USDC-06EB48` and still be indexed under
/// `ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48`. `ModifyLimitSwapMemo`
/// is the exception: its asset string is used verbatim to build the lookup key.
/// A cancel repeating the placement's abbreviation therefore addresses a bucket
/// that, by construction, holds nothing — and THORChain answers with
/// `could not find matching limit swap`. Enforced, not merely documented, by
/// `thorchainMemoAssetIsAbbreviated` below.
///
/// ⚠️ **Amounts are PLAIN decimal integers — never `compressLim`'d.** The
/// placement memo's LIM goes through `getUintWithScientificNotation`, which
/// understands `544e6`; these coin amounts go through `cosmos.ParseCoins` /
/// `common.ParseCoin`, which do NOT. A compressed amount here fails to parse and
/// the cancel is rejected. The two memos look similar and are not.
///
/// ⚠️ **Why both amounts must be exact.** THORNode does not compare the amounts
/// directly. It builds an index key from
/// `(layer1Source > layer1Target / rewriteRatio(18, sourceAmount × 1e8 / tradeTarget))`
/// and then scans that bucket for a swap whose `FromAddress` matches the sender,
/// taking the FIRST match. The amounts are load-bearing only through that
/// integer division — but one unit of drift in either lands in a different
/// bucket, and a cancel that matches nothing is indistinguishable from a
/// successful one from the client's side. Hence `LimitOrderCancelInputs` is fed
/// from values captured at signing and cross-checked against the queue, never
/// re-derived. See `limitOrderCancelEligibility`.
func buildCancelLimitSwapMemo(_ inputs: LimitOrderCancelInputs) throws -> String {
    guard !inputs.sourceAsset.isEmpty, !inputs.targetAsset.isEmpty else {
        throw LimitSwapCancelMemoError.emptyAsset
    }
    guard inputs.sourceAmount1e8 > 0, inputs.tradeTarget > 0 else {
        throw LimitSwapCancelMemoError.nonPositiveAmount
    }
    guard !thorchainMemoAssetIsAbbreviated(inputs.sourceAsset),
          !thorchainMemoAssetIsAbbreviated(inputs.targetAsset) else {
        throw LimitSwapCancelMemoError.abbreviatedAsset
    }
    let source = "\(inputs.sourceAmount1e8.description)\(inputs.sourceAsset)"
    let target = "\(inputs.tradeTarget.description)\(inputs.targetAsset)"
    return "\(modifyLimitSwapMemoPrefix)\(source):\(target):\(cancelModifiedTargetAmount)"
}

// MARK: - Eligibility

/// Why an order cannot be cancelled from this app. Each case maps to its own
/// user-facing explanation — a disabled button with no reason is worse than no
/// button.
enum LimitOrderCancelBlocker: Equatable, Sendable {
    /// The order has already closed. Nothing left to cancel.
    case terminal
    /// The order predates the fields cancelling needs, or its source chain was
    /// never recorded. Fails closed: we would rather grey the button out than
    /// guess at the amounts the matcher keys on.
    case missingSignedData
    /// A cancel for this order has already succeeded on-chain and is waiting to
    /// be observed in the queue.
    ///
    /// The order stays NON-TERMINAL on purpose — `.cancelling` — because that is
    /// what keeps a cancel that silently matched nothing visible rather than
    /// papered over. But a live order would also leave the button live, letting
    /// the user pay the fee (and on L1 donate the dust) again for an identical
    /// memo that would land in the identical ratio bucket. This blocker is the
    /// guard; `.cancelling` is the same fact with a face the user can read.
    /// Self-resolving in both directions: the order leaves `.cancelling` when it
    /// closes, and drops back to `.pending` if the cancel record is withdrawn.
    case cancelAlreadyBroadcast
    /// The order was funded from a chain THORChain cannot route, so there is no
    /// inbound vault to send the cancel to.
    case unsupportedSourceChain
    /// The cancel memo does not fit the source chain's per-transaction budget.
    ///
    /// In practice this is an ERC20 target from a UTXO source: two full
    /// contract-suffixed assets plus two exact amounts overflow the 80-byte
    /// `OP_RETURN` cap, and NOTHING in a cancel memo can be shortened — the
    /// amounts define the ratio bucket, short codes are rejected by
    /// `cosmos.ParseCoins`, and this memo type skips `fuzzyAssetMatch`. The
    /// order still refunds automatically at expiry.
    case memoTooLongForSourceChain
    /// What we recorded at signing and what the queue reports disagree.
    ///
    /// One of the two is wrong and there is no way to tell which. Signing either
    /// would be a guess whose failure mode is silent — the cancel simply matches
    /// nothing and looks like it worked.
    case signedDataDisagreesWithChain
}

/// Which spelling of one of the order's assets a cancel memo may use.
///
/// Three sources, in decreasing order of how much they prove:
///
/// 1. **The queue's own report** (`observed`) — the string THORChain built this
///    order's index entry from, after `fuzzyAssetMatch` resolved whatever the
///    placement memo abbreviated. Authoritative by construction, and the only
///    source for an order placed before the full form was recorded.
/// 2. **The full form captured at signing** (`signed`) — derived locally from
///    the coin's own contract address, so it is exact whenever it exists.
/// 3. **The stored placement spelling** (`stored`) — usable ONLY when it carries
///    no truncated token identifier, which makes it full by construction. That
///    covers every native leg (`BTC.BTC`, `THOR.RUNE`) and every secured denom.
///
/// `.unknown` when none of the three yields a spelling that can be signed — the
/// fail-closed answer, and the one a legacy EVM-token leg lands on until the
/// queue has been polled once.
///
/// `.disagrees` when a local spelling and the chain's own DISAGREE. One of the
/// two is wrong and there is no way to tell which, so neither is signed. This is
/// the check that would have caught the 2026-07-21 rehearsal before it cost a
/// fee: the amounts were compared against the queue and matched, the assets were
/// not compared at all, and the assets were the whole problem.
///
/// Compared case-insensitively because case carries no meaning here and the two
/// sources disagree on it by convention: this app emits a secured denom
/// lower-case, THORChain reports it upper-case, and `common.ParseCoin`
/// upper-cases whatever it is given. Anything beyond case is a real difference.
func limitOrderCancelMemoAsset(
    stored: String,
    signed: String?,
    observed: String?
) -> LimitOrderCancelAssetResolution {
    let local = signed?.trimmedNonEmpty
        ?? (thorchainMemoAssetIsAbbreviated(stored) ? nil : stored.trimmedNonEmpty)
    guard let observed = observed?.trimmedNonEmpty else {
        return local.map { .resolved($0) } ?? .unknown
    }
    guard let local else {
        // No local spelling to check it against — the legacy EVM-token case,
        // rescued by the only source that still holds the full contract.
        return .resolved(observed)
    }
    guard local.caseInsensitiveCompare(observed) == .orderedSame else {
        return .disagrees
    }
    // Proven equal bar case, so the local spelling is kept: it is the exact
    // byte form this app derived and its tests pin.
    return .resolved(local)
}

/// Which spelling of an asset a cancel memo may use, or why there isn't one.
enum LimitOrderCancelAssetResolution: Equatable {
    case resolved(String)
    /// What we hold and what the chain reports are not the same asset.
    case disagrees
    /// No source can supply the full spelling.
    case unknown
}

enum LimitOrderCancelEligibility: Equatable, Sendable {
    case cancellable(LimitOrderCancelInputs)
    case blocked(LimitOrderCancelBlocker)

    var blocker: LimitOrderCancelBlocker? {
        switch self {
        case .cancellable: return nil
        case let .blocked(blocker): return blocker
        }
    }

    var isCancellable: Bool { blocker == nil }
}

/// Decide whether `details` describes an order this app can cancel, and if so
/// with which exact amounts.
///
/// **Fails closed at every unknown.** The failure this guards against is not a
/// crash or an error dialog — it is a cancel that is accepted, costs a fee, and
/// silently matches no order at all. Every branch that cannot prove the amounts
/// are the ones THORChain holds returns `.blocked`.
func limitOrderCancelEligibility(_ details: LimitOrderDetails) -> LimitOrderCancelEligibility {
    guard !details.isTerminal else {
        return .blocked(.terminal)
    }
    guard details.cancelBroadcastHash == nil else {
        return .blocked(.cancelAlreadyBroadcast)
    }
    // `LimitOrder` carries no chain field, and `sourceAsset` alone cannot stand
    // in for one: a SECURED asset source is THORChain-placed but its memo asset
    // is a bare denom (`eth-usdc-0xa0b…`) with no `THOR.` prefix, while a
    // `THOR.`-prefixed string tells us nothing about where the deposit came
    // from. So the source chain is recorded explicitly at placement; `nil` means
    // the order predates that and is treated as not cancellable.
    guard let sourceChainRawValue = details.sourceChainRawValue,
          let sourceChain = Chain(rawValue: sourceChainRawValue) else {
        return .blocked(.missingSignedData)
    }
    // Both routes are supported: a THORChain-sourced order cancels via
    // `MsgDeposit` from the vault's THOR address, and an L1-sourced order
    // cancels by sending the same memo from the chain that funded it — THORNode
    // dispatches `m=<` from the Bifrost observed-tx path too. What matters is
    // only that THORChain can route the source chain at all.
    guard sourceChain == .thorChain || isThorchainRoutable(chain: sourceChain) else {
        return .blocked(.unsupportedSourceChain)
    }
    // Bound in two steps rather than `flatMap(BigInt.init)`: an unapplied
    // `BigInt.init` is ambiguous here (this codebase carries radix/hex
    // initializer overloads that also match `(String) -> BigInt?`), which is the
    // same footgun already documented for `Int.init` on the tracking path.
    guard let signedSourceAmountText = details.sourceAmount1e8,
          let signedTradeTargetText = details.tradeTarget,
          let signedSourceAmount = BigInt(signedSourceAmountText),
          let signedTradeTarget = BigInt(signedTradeTargetText),
          signedSourceAmount > 0, signedTradeTarget > 0 else {
        return .blocked(.missingSignedData)
    }

    // Cross-check against what THORChain itself reports, when it has reported
    // anything. `state.deposit` IS the swap's `Tx.Coins[0].Amount` (THORNode
    // assigns it verbatim), and `trade_target` IS `msg.TradeTarget` — i.e. the
    // exact pair the matcher's ratio is computed from. Absence is NOT
    // disagreement: an order placed seconds ago has not been polled yet, and
    // refusing to cancel it until the first poll lands would be a worse failure
    // than the one this check prevents.
    // An observation that is PRESENT but unparseable blocks, exactly as a
    // mismatch does. "Absent" and "present but not understood" are different
    // claims: the first is a poll that hasn't happened, the second means the
    // wire carried something this code does not model — a protocol change, most
    // likely — and proceeding would sign amounts we failed to verify. THORChain
    // amounts are `cosmos.Uint` decimal strings, so this should never fire; if
    // it does, that IS the signal.
    if let observedDepositText = details.fill.depositAmount {
        guard let observedDeposit = BigInt(observedDepositText),
              observedDeposit == signedSourceAmount else {
            return .blocked(.signedDataDisagreesWithChain)
        }
    }
    if let observedTradeTargetText = details.observedTradeTarget {
        guard let observedTradeTarget = BigInt(observedTradeTargetText),
              observedTradeTarget == signedTradeTarget else {
            return .blocked(.signedDataDisagreesWithChain)
        }
    }

    // The ASSETS get the same treatment as the amounts: resolved against what
    // THORChain reports, and blocked on a disagreement. The stored `sourceAsset`
    // / `targetAsset` are the PLACEMENT strings and are lossy — a 6-character
    // contract suffix cannot be expanded back — so they are usable only when
    // they carry no truncated identifier at all.
    //
    // ⚠️ Comparing the assets is what the 2026-07-21 rehearsal needed and did
    // not have. The amounts were cross-checked and agreed; the assets were never
    // compared, and the asset was the entire defect. A check that verifies
    // everything except the field that broke is a check that reports "all clear"
    // on the way to a rejected transaction.
    let sourceResolution = limitOrderCancelMemoAsset(
        stored: details.sourceAsset,
        signed: details.sourceAssetFull,
        observed: details.observedSourceAsset
    )
    let targetResolution = limitOrderCancelMemoAsset(
        stored: details.targetAsset,
        signed: details.targetAssetFull,
        observed: details.observedTargetAsset
    )
    guard case let .resolved(sourceAsset) = sourceResolution,
          case let .resolved(targetAsset) = targetResolution else {
        return .blocked(
            sourceResolution == .disagrees || targetResolution == .disagrees
                ? .signedDataDisagreesWithChain
                : .missingSignedData
        )
    }

    let inputs = LimitOrderCancelInputs(
        sourceAsset: sourceAsset,
        sourceAmount1e8: signedSourceAmount,
        targetAsset: targetAsset,
        tradeTarget: signedTradeTarget
    )

    // The memo has to be buildable AND fit the chain it will be sent from.
    // Checked here rather than at the point of signing so the button is never
    // offered for an order that cannot actually be cancelled — the whole reason
    // this predicate exists.
    guard let memo = try? buildCancelLimitSwapMemo(inputs) else {
        return .blocked(.missingSignedData)
    }
    guard limitOrderCancelMemoFits(memo, sourceChainKind: sourceChain.chainType) else {
        return .blocked(.memoTooLongForSourceChain)
    }

    return .cancellable(inputs)
}

// MARK: - Duplicate detection

/// Other RESTING orders that the same cancel memo would also address.
///
/// THORNode addresses orders by **(layer-1 source asset, layer-1 target asset,
/// ratio) + `FromAddress`**, never by tx hash, and takes the FIRST match in the
/// bucket — verbatim: *"If multiple swaps exist with the same source/target for
/// a user, only the first is modified."* So two orders that reduce to the same
/// inputs are not independently cancellable, and the user has to be told that
/// the one they tapped may not be the one that closes.
///
/// Compared on THORNode's actual bucket key, NOT on equal amounts: two orders
/// with different deposits and different trade targets collide whenever their
/// ratio is the same (sell 1 and sell 2 at the same price land in one bucket).
/// Comparing amounts for equality would silently under-report exactly the
/// duplicates the user most needs warning about.
///
/// Assets are layer-1-normalized before comparison, because THORNode's key is.
/// A synth, trade or secured representation and the plain L1 asset all collapse
/// to the same key on-chain, so comparing the memo strings verbatim would miss
/// a pair that really does collide — and the whole point of this warning is that
/// the order the user tapped may not be the one that closes.
func duplicateRestingLimitOrders(
    of target: LimitOrderDetails,
    among orders: [LimitOrderDetails]
) -> [LimitOrderDetails] {
    guard case let .cancellable(targetInputs) = limitOrderCancelEligibility(target) else {
        return []
    }
    let targetKey = thorchainLimitOrderBucketKey(targetInputs)
    return orders
        .filter { $0.id != target.id }
        .filter { candidate in
            guard case let .cancellable(inputs) = limitOrderCancelEligibility(candidate) else {
                return false
            }
            return thorchainLimitOrderBucketKey(inputs) == targetKey
        }
        .sorted { $0.createdAt < $1.createdAt }
}

/// Reproduces THORNode's adv-swap-queue index key for a limit order — the tuple
/// that decides which orders are mutually indistinguishable to a cancel.
///
/// Mirrors `getAdvSwapQueueIndexKey` + `getRatio` + `rewriteRatio`:
///
///     ratio = (sourceAmount × 1e8) / tradeTarget      // integer division
///     key   = "<source>><target>/<ratio padded or truncated to 18 chars>/"
///
/// The 18-character normalization is not cosmetic — THORNode zero-pads short
/// ratios so the keys sort in numeric order, and **truncates** longer ones from
/// the right, which deliberately collapses very large ratios into one bucket.
/// Both behaviours have to be reproduced or the duplicate warning disagrees with
/// the chain at exactly the extremes where it matters.
func thorchainLimitOrderBucketKey(_ inputs: LimitOrderCancelInputs) -> String {
    let ratio = (inputs.sourceAmount1e8 * BigInt(10).power(Coin.thorchainFixedPointExponent)) / inputs.tradeTarget
    let source = thorchainLayer1MemoAsset(inputs.sourceAsset)
    let target = thorchainLayer1MemoAsset(inputs.targetAsset)
    return "\(source)>\(target)/\(rewriteThorchainRatio(ratio.description))/"
}

/// Collapse a memo asset string to its layer-1 form, the way THORNode's
/// `Asset.GetLayer1Asset()` does when it builds the queue index key.
///
/// On their side this just clears the synth/trade/secured flags while keeping
/// chain, symbol and ticker; on the wire those three flavours are spelled with
/// `/`, `~` and `-` respectively where the L1 asset uses `.`. So the rule is:
/// the FIRST separator becomes `.`, and the result is upper-cased (secured
/// denoms arrive lower-case).
///
/// An asset already in L1 form is left alone — its first separator is the `.`
/// itself, and the `-` in a contract-suffixed asset like `ETH.USDC-0XA0B…`
/// comes after it, so it must not be touched.
///
/// This is an APPROXIMATION, and deliberately only used for the duplicate
/// WARNING — never to build a memo. It is tuned to over-report rather than
/// under-report: telling a user two orders might be confused when they wouldn't
/// be is a mild annoyance, while missing a real collision means the wrong order
/// closes with no warning at all.
func thorchainLayer1MemoAsset(_ asset: String) -> String {
    let separators: Set<Character> = ["/", "~", "-", "."]
    guard let index = asset.firstIndex(where: { separators.contains($0) }),
          asset[index] != "." else {
        return asset.uppercased()
    }
    return (asset[asset.startIndex..<index] + "." + asset[asset.index(after: index)...]).uppercased()
}

/// THORNode's `ratioLength` — "a value of 18 means that granularity is maxed out
/// at 1 trillion to 1 ratio" (verbatim). Changing it on their side is a kvstore
/// migration, so it is safe to pin.
private let thorchainRatioLength = 18

private func rewriteThorchainRatio(_ ratio: String) -> String {
    if ratio.count < thorchainRatioLength {
        return String(repeating: "0", count: thorchainRatioLength - ratio.count) + ratio
    }
    if ratio.count > thorchainRatioLength {
        return String(ratio.prefix(thorchainRatioLength))
    }
    return ratio
}
