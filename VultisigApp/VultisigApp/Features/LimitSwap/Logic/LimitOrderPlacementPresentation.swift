//
//  LimitOrderPlacementPresentation.swift
//  VultisigApp
//
//  How a limit-order PLACEMENT is presented to a CO-SIGNER, derived from the
//  `=<:` memo alone.
//
//  The initiator's placement Verify (`SwapVerifyScreen`, `isLimit` branch) reads
//  the live `SwapTransaction.limitContext` to show a limit-specific title, the
//  from → minimum-payout pair, the target price and the expiry. A co-signing
//  device has none of that: it holds only a `KeysignPayload`, whose `=<:` memo is
//  the sole on-the-wire record that the deposit places a resting order rather
//  than a market swap. Without this, a co-signer falls back to the generic
//  simulation-derived hero and sees an ordinary deposit — the exact blind-signing
//  risk this parity closes.
//
//  ⚠️ **Memo-derived, on purpose — mirrors `LimitOrderCancelPresentation`.** The
//  limit-ness lives ONLY in the memo (`=<:…` places, `=>:…` is the market path),
//  which is the same discriminator THORChain itself keys on. Everything shown
//  here is reconstructed from that memo plus the payload's own source coin and
//  deposited amount — never from a `SwapTransaction`/`LimitOrder`, which the
//  co-signer does not have.
//
//  ⚠️ **The target price is the memo's effective floor, not the typed price.**
//  The placement memo carries the LIM (guaranteed-minimum output in THORChain's
//  1e8 fixed point) and the expiry, but NOT the user's originally-typed target
//  price. So the price shown here is reconstructed as `minOutput ÷ sourceAmount`,
//  which is exactly what the signed order guarantees — and can read a hair below
//  the initiator's typed price after fixed-point truncation / byte-fit rounding.
//  That is the honest value to show on a signing screen: what you sign is what
//  you see.
//

import BigInt
import Foundation

enum LimitOrderPlacementPresentation {

    /// Everything the co-signer's Verify screen shows for a limit-order
    /// placement, already reduced to display strings.
    struct Display: Equatable {
        /// Swap-shaped hero: the limit title above the source → minimum-payout
        /// pair.
        let hero: HeroContent
        /// The order's guaranteed price, written like the initiator's row:
        /// `1 <source> = <price> <target>`.
        let targetPriceValue: String
        /// The order's lifetime, e.g. `12h` — or `nil` when the memo's block
        /// interval isn't a whole number of hours (which no order this app
        /// builds ever is), so the screen omits the row rather than show a
        /// floored/rounded value the order was not signed with.
        let expiryValue: String?
    }

    /// Build the placement display for a co-signer's `KeysignPayload`, or `nil`
    /// when the payload is not a limit-order placement (every other transaction
    /// keeps its existing presentation).
    ///
    /// Gated strictly on the `=<:` prefix via `isLimitSwapMemo`, the same
    /// predicate the memo builder uses — so a cancel (`m=<:`), a market swap
    /// (`=>:`), an LP add/remove (`+`/`-`) or any other memo returns `nil` and is
    /// left byte-identical.
    static func display(for payload: KeysignPayload?) -> Display? {
        guard let payload,
              let parsed = parsePlacementMemo(payload.memo) else { return nil }

        // The deposit amount IS the source amount, in the source coin's natural
        // units. `payload.coin` is the source coin on every placement route
        // (native RUNE MsgDeposit, native gas-asset transfer, ERC20 router
        // deposit), so this needs no swap-payload special-casing.
        let sourceAmount = payload.toAmountDecimal
        guard sourceAmount > 0 else { return nil }

        // LIM is the guaranteed-minimum output in THORChain's 1e8 fixed point,
        // target-asset agnostic — `limNaturalOutput` is the same conversion the
        // initiator's "you receive" figure uses.
        //
        // `limNaturalOutput` returns 0 for a LIM too large to represent as a
        // `Decimal`. A memo can carry any integer, so a hostile one could push
        // the LIM past that range; showing the resulting 0 minimum / 0 price
        // would be a fabricated figure on a signing screen. Reject instead, so
        // the co-signer falls back to the generic (still honest) hero rather
        // than a false zero.
        let minOutput = limNaturalOutput(parsed.lim)
        guard minOutput > 0 else { return nil }
        let targetPrice = minOutput / sourceAmount
        let sourceTicker = payload.coin.ticker

        let hero = HeroContent.swap(
            title: "limitSwap.verify.title".localized,
            from: HeroCoinAmount(
                amount: sourceAmount.formatForDisplay(),
                ticker: sourceTicker,
                logo: payload.coin.logo
            ),
            // No target logo: a co-signer has no target `Coin`, only the memo's
            // asset string. The hero row hides the icon for an empty logo rather
            // than guess at an image, and the ticker still names the asset.
            to: HeroCoinAmount(
                amount: minOutput.formatForDisplay(),
                ticker: parsed.targetTicker,
                logo: ""
            )
        )

        return Display(
            hero: hero,
            targetPriceValue: String(
                format: "limitSwap.detail.targetPriceFormat".localized,
                sourceTicker,
                targetPrice.formatForDisplay(),
                parsed.targetTicker
            ),
            expiryValue: parsed.expiryHours.map { "\($0)h" }
        )
    }

    /// Whether a memo about to be signed places a limit order — the co-signer
    /// side of the `=<:` discriminator.
    static func isPlacement(memo: String?) -> Bool {
        isLimitSwapMemo(memo)
    }

    /// The fields a placement hero needs, parsed out of the `=<:` memo.
    struct ParsedPlacement: Equatable {
        let targetTicker: String
        let lim: BigInt
        /// `nil` when the memo's block interval isn't a whole number of hours —
        /// see `Display.expiryValue`.
        let expiryHours: Int?
    }

    /// Parse a placement memo into the target ticker, LIM and expiry hours.
    ///
    /// Wire layout (see `composeLimitSwapMemo`):
    ///
    ///     =<:<TARGET_ASSET>:<DEST_ADDR>:<LIM>/<INTERVAL>/<QTY>:<AFFILIATE>:<BPS>
    ///
    /// Only the target asset (field 1) and the `LIM/INTERVAL` group (field 3) are
    /// read; the destination address, quantity and affiliate tail don't affect
    /// what a co-signer needs to verify. Returns `nil` for any memo that isn't a
    /// well-formed placement so callers stay on their existing presentation.
    static func parsePlacementMemo(_ memo: String?) -> ParsedPlacement? {
        guard isLimitSwapMemo(memo), let memo else { return nil }

        // `omittingEmptySubsequences: false` so a malformed empty field is caught
        // as such rather than silently shifting the fields left.
        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        // [0]=`=<`, [1]=target asset, [2]=dest, [3]=LIM/INTERVAL/QTY, …
        guard fields.count >= 4 else { return nil }

        let targetAsset = fields[1]
        let targetTicker = thorchainMemoAssetTicker(targetAsset)
        guard !targetTicker.isEmpty else { return nil }

        let limGroup = fields[3].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard limGroup.count >= 2,
              let lim = decodeCompressedLim(limGroup[0]), lim > 0,
              let intervalBlocks = Int(limGroup[1]), intervalBlocks > 0 else {
            return nil
        }

        // Only surface an expiry when the interval is an exact whole-hour count.
        // Every order this app builds is (`computeExpiryBlocks(hours:)` =
        // hours × `blocksPerHour`); a stray remainder means a memo we can't state
        // in whole hours, so we omit the field rather than floor it to a wrong —
        // possibly `0h` — value.
        let expiryHours = intervalBlocks.isMultiple(of: THORChainConstants.blocksPerHour)
            ? THORChainConstants.hours(forBlocks: intervalBlocks)
            : nil

        return ParsedPlacement(
            targetTicker: targetTicker,
            lim: lim,
            expiryHours: expiryHours
        )
    }
}

/// Largest `<mantissa>e<exponent>` exponent a LIM field may carry.
///
/// Purely a denial-of-service bound: a co-signer receives the memo over the
/// wire, so a hostile `1e1000000000` would otherwise force a multi-gigabyte
/// `BigInt.power` allocation. A LIM is a 1e8 fixed-point amount, and even an
/// astronomically large token quantity needs far fewer than 80 trailing zeros —
/// the real fixtures top out at `6e11` — so this rejects the pathological case
/// without touching any legitimate order. Values that survive this cap but still
/// exceed `Decimal`'s range are caught downstream by the `minOutput > 0` guard.
private let maxCompressedLimExponent = 80

/// Decode a memo LIM field back to its integer value, inverting `compressLim`.
///
/// The LIM is written either as a plain decimal (`1600000000`) or in THORChain's
/// `<mantissa>e<exponent>` shorthand (`16e8`), which `compressLim` emits when it
/// is strictly shorter. Both decode to the same integer. Returns `nil` for
/// anything that is neither form (a negative or oversized exponent, non-digits)
/// so a malformed or hostile memo doesn't fabricate a price or exhaust memory.
func decodeCompressedLim(_ field: String) -> BigInt? {
    if let plain = BigInt(field) {
        return plain
    }
    let parts = field.lowercased().split(separator: "e", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2,
          let mantissa = BigInt(parts[0]),
          let exponent = Int(parts[1]),
          exponent >= 0, exponent <= maxCompressedLimExponent else {
        return nil
    }
    return mantissa * BigInt(10).power(exponent)
}

/// The plain ticker inside a THORChain memo asset — `ETH.ETH` → `ETH`,
/// `ETH.USDC-06EB48` → `USDC`, `THOR.RUNE` → `RUNE`, secured `eth-usdc-0xa0b…` →
/// `USDC`, `btc-btc` → `BTC`.
///
/// Drops the chain segment (everything up to the first `.` / `/` / `~` / `-`
/// separator — the same rule `thorchainMemoAssetIsAbbreviated` uses) and then
/// takes the symbol up to any `-<contract>` suffix, upper-cased. Returns an empty
/// string for an asset with no symbol so callers can reject it.
func thorchainMemoAssetTicker(_ asset: String) -> String {
    let separators: Set<Character> = [".", "/", "~", "-"]
    let symbol: Substring
    if let chainEnd = asset.firstIndex(where: { separators.contains($0) }) {
        symbol = asset[asset.index(after: chainEnd)...]
    } else {
        symbol = asset[...]
    }
    guard let contractSeparator = symbol.firstIndex(of: "-") else {
        return symbol.uppercased()
    }
    return symbol[..<contractSeparator].uppercased()
}
