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
        /// `1 <source> = <price> <target>` — or `nil` when the price is a
        /// positive value too small to state at display precision (it would
        /// format to `0`), so the screen omits the row rather than show a
        /// fabricated zero. The hero's source → minimum-payout pair still carries
        /// the real amounts.
        let targetPriceValue: String?
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
        // initiator's "you receive" figure uses. `parsePlacementMemo` has already
        // bounded the LIM's magnitude (`maxLimDigits`), so this stays a sane
        // number. The `> 0` guard is defense-in-depth: a `limNaturalOutput` of 0
        // for a positive LIM would mean an unrepresentable conversion, and a 0
        // minimum on a signing screen reads as "fill at any price" — reject and
        // fall back to the limit title rather than show that.
        let minOutput = limNaturalOutput(parsed.lim)
        guard minOutput > 0 else { return nil }
        let targetPrice = minOutput / sourceAmount
        let sourceTicker = payload.coin.ticker

        let hero = HeroContent.swap(
            title: placementTitle,
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
            targetPriceValue: targetPriceRow(
                price: targetPrice,
                sourceTicker: sourceTicker,
                targetTicker: parsed.targetTicker
            ),
            expiryValue: parsed.expiryHours.map { "\($0)h" }
        )
    }

    /// The hero for a co-signer's Verify screen, or `nil` when the payload is not
    /// a placement.
    ///
    /// ⚠️ **Always a limit-order hero for a recognized `=<:` memo.** When the full
    /// details reconstruct, it is the swap hero from `display`. When they do NOT
    /// — an out-of-range or malformed LIM, a zero deposit — it falls back to the
    /// limit TITLE, never to the caller's generic simulation hero: on a signing
    /// screen a co-signer must still see that it is placing a limit order rather
    /// than a plain deposit/swap. Mirrors `LimitOrderCancelPresentation.hero`,
    /// which likewise titles every cancel memo even when nothing else resolves.
    /// Takes the already-computed `display` so the reconstruction isn't repeated.
    static func hero(memo: String?, display: Display?) -> HeroContent? {
        guard isLimitSwapMemo(memo) else { return nil }
        return display?.hero ?? .title(text: placementTitle, caption: nil)
    }

    /// Whether a memo about to be signed places a limit order — the co-signer
    /// side of the `=<:` discriminator.
    static func isPlacement(memo: String?) -> Bool {
        isLimitSwapMemo(memo)
    }

    private static var placementTitle: String { "limitSwap.verify.title".localized }

    /// Format the target-price row, or `nil` when the price is positive but too
    /// small to state at display precision.
    ///
    /// `formatForDisplay` truncates toward zero at 8 fractional digits, so a
    /// genuine floor below `0.00000001` per source unit would render as `0` — a
    /// fabricated zero price on a signing screen. The visibility test is NUMERIC
    /// (the price's own 8-dp truncation), not a scan of the formatted string: a
    /// locale with non-ASCII digits (e.g. Arabic-Indic `٠`) would let a formatted
    /// zero slip past a character check. When it can't be stated, omit the row;
    /// the hero's source → minimum-payout pair still carries the true amounts.
    private static func targetPriceRow(price: Decimal, sourceTicker: String, targetTicker: String) -> String? {
        guard price.truncated(toPlaces: Coin.thorchainFixedPointExponent) > 0 else { return nil }
        return String(
            format: "limitSwap.detail.targetPriceFormat".localized,
            sourceTicker,
            price.formatForDisplay(),
            targetTicker
        )
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

/// Longest raw LIM field this will parse. Purely a parse-time DoS bound: it caps
/// the plain-decimal string (and any mantissa) before `BigInt(_:)` is handed it,
/// so a hostile multi-megabyte digit run can't force an unbounded allocation on
/// a co-signer.
private let maxLimFieldLength = 40

/// Largest number of digits a DECODED LIM may have. A LIM is a 1e8 fixed-point
/// amount, so even an astronomically large order stays far under 30 digits
/// (`6e11` = 12 in the real fixtures); a value with more is hostile or malformed
/// and would render an absurd minimum / target price on the signing screen.
///
/// This — not `Decimal` representability — is the effective magnitude bound:
/// `Decimal` happily holds values well past 10^100, so a `limNaturalOutput`
/// conversion of a huge LIM yields a giant number rather than the zero one might
/// expect. The digit cap rejects it outright so `hero(memo:display:)` falls back
/// to the plain limit title instead of a nonsense figure.
private let maxLimDigits = 30

/// Decode a memo LIM field back to its integer value, inverting `compressLim`.
///
/// The LIM is written either as a plain decimal (`1600000000`) or in THORChain's
/// `<mantissa>e<exponent>` shorthand (`16e8`), which `compressLim` emits when it
/// is strictly shorter. Both decode to the same integer. Returns `nil` for
/// anything that is neither form (a negative or oversized exponent, non-digits,
/// an over-long field, or an out-of-range magnitude) so a malformed or hostile
/// memo doesn't fabricate a price or exhaust memory.
func decodeCompressedLim(_ field: String) -> BigInt? {
    // Bound the raw length before any parse — guards the plain-decimal path,
    // which would otherwise hand an unbounded digit string straight to BigInt.
    guard !field.isEmpty, field.count <= maxLimFieldLength else { return nil }

    let value: BigInt
    if let plain = BigInt(field) {
        value = plain
    } else {
        let parts = field.lowercased().split(separator: "e", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              let mantissa = BigInt(parts[0]),
              let exponent = Int(parts[1]),
              exponent >= 0, exponent <= maxCompressedLimExponent else {
            return nil
        }
        value = mantissa * BigInt(10).power(exponent)
    }

    // Reject a non-positive or absurdly large magnitude — see `maxLimDigits`.
    guard value > 0, value.description.count <= maxLimDigits else { return nil }
    return value
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
