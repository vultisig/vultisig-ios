//
//  LimitMath.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Scales `targetPrice` to THORChain's 1e8 fixed-point and derives the LIM
/// (minimum amount out) for the memo.
///
/// **Fund-safety: overflow MUST fail loud.** If `targetPrice` is large enough
/// that scaling it by 1e8 overflows `Decimal` (max ~1e127), the multiply yields
/// a `Decimal` NaN whose `stringValue` is `"NaN"`. `BigInt("NaN")` is `nil`. A
/// silent `?? 0` fallback would emit `LIM=0` in the memo, which THORChain reads
/// as "fill at ANY price" — the exact opposite of a limit order. We throw
/// `LimitSwapMemoError.targetPriceOverflow` instead so the place-order flow
/// surfaces the error rather than placing a price-blind swap.
func computeLim(sourceAmount: BigInt, sourceDecimals: Int, targetPrice: Decimal) throws -> BigInt {
    // Reject NEGATIVE inputs up-front. A negative source amount or target price
    // produces a NEGATIVE LIM that sails straight past the `lim <= 0` underflow
    // guard below (which only fires when BOTH inputs are strictly positive), so
    // THORChain would receive a nonsensical negative minimum-out — a fund-safety
    // hazard from the invalid-input side, mirroring the overflow/underflow
    // guards. A zero source amount stays a separate upstream precondition
    // (rejected by `validateLimitSwapInputs`) and still returns 0 without
    // throwing, so callers that display an expected output before the user has
    // typed an amount are unaffected.
    guard sourceAmount >= 0, targetPrice >= 0 else {
        throw LimitSwapMemoError.limitAmountTooSmall
    }

    var price = targetPrice
    var scaled = Decimal()
    NSDecimalMultiplyByPowerOf10(&scaled, &price, Int16(Coin.thorchainFixedPointExponent), .plain)

    var truncated = Decimal()
    NSDecimalRound(&truncated, &scaled, 0, .down)

    // `Decimal.isNaN` catches an overflowed multiply; the explicit BigInt parse
    // guard is belt-and-suspenders for any other unrepresentable result.
    guard !truncated.isNaN,
          let priceBig = BigInt(NSDecimalNumber(decimal: truncated).stringValue) else {
        throw LimitSwapMemoError.targetPriceOverflow
    }
    let denominator = BigInt(10).power(sourceDecimals)
    let lim = (sourceAmount * priceBig) / denominator

    // Integer division truncates toward zero: a dust source amount, a very low
    // target price, or a zero target price against a positive source can floor
    // the LIM to 0. A `LIM=0` memo means "fill at ANY price" — the same hazard
    // the overflow guard above prevents, from the underflow side. Fail loud for
    // ANY positive source that yields `lim <= 0`, regardless of the target
    // price's sign, so `targetPrice == 0` also throws rather than emitting a
    // price-blind order (defense-in-depth: `validateLimitSwapInputs` already
    // rejects a non-positive target price upstream). A zero SOURCE amount stays
    // a separate precondition and returns 0 here without throwing, so callers
    // that display an expected output before an amount is typed are unaffected.
    if lim <= 0, sourceAmount > 0 {
        throw LimitSwapMemoError.limitAmountTooSmall
    }
    return lim
}

/// The minimum output the placed order guarantees, in the target asset's
/// natural units — i.e. the LIM the memo encodes, expressed for display.
///
/// Derived from the SAME truncated `computeLim` the signed memo uses (THORChain
/// LIM is 1e8 fixed-point for the target asset), NOT a fresh full-precision
/// `sourceAmount * targetPrice`. That matters on the Verify / Done screens: a
/// full-precision figure could read slightly HIGHER than the order actually
/// guarantees after fixed-point truncation + integer division — overstating a
/// "minimum you receive". Reusing `computeLim` keeps display == memo exactly.
///
/// Non-throwing (a computed display property can't throw): returns 0 when
/// `computeLim` rejects the order (overflow / dust underflow) — such an order
/// can't be placed, so the Verify screen is never reached for it anyway.
func limitOrderExpectedOutput(
    sourceAmount: BigInt,
    sourceDecimals: Int,
    targetPrice: Decimal
) -> Decimal {
    guard let lim = try? computeLim(
        sourceAmount: sourceAmount,
        sourceDecimals: sourceDecimals,
        targetPrice: targetPrice
    ) else {
        return 0
    }
    return limNaturalOutput(lim)
}

/// Convert a THORChain LIM (1e8 fixed-point, target asset) to the target's
/// natural units for display. Shared by `limitOrderExpectedOutput` and the
/// byte-fitting path, so a memo whose LIM was rounded UP to fit
/// (`buildFittedLimitSwapMemo`) shows the EXACT effective minimum the order was
/// signed with — display == memo.
func limNaturalOutput(_ lim: BigInt) -> Decimal {
    guard let limDecimal = Decimal(string: lim.description) else { return 0 }
    var scaled = limDecimal
    var natural = Decimal()
    NSDecimalMultiplyByPowerOf10(&natural, &scaled, Int16(-Coin.thorchainFixedPointExponent), .plain)
    return natural
}

/// Decimal places the amount fields render, and therefore the precision a
/// DERIVED amount must be quantized to.
///
/// A derived deposit that carries more decimals than the field shows would make
/// the screen disagree with the signed transaction. Matches the 1e8 fixed point
/// THORChain uses for the LIM, so the two ends of the form round the same way.
let limitAmountDisplayPrecision = 8

/// The source amount needed to buy `targetOutput` of the target asset at
/// `targetPrice` — the inverse of `limitOrderExpectedOutput`, for the entry
/// direction where the user states what they want to RECEIVE.
///
/// **Truncates, never rounds up.** Rounding up would make a typed buy figure come
/// out exact on screen at the cost of spending more of the user's balance than
/// they asked for — the display would be flattering and the deposit would be
/// larger. Truncating means the derived sell is at most one smallest-unit short,
/// and the buy the caller then re-derives through `limitOrderExpectedOutput` is
/// the order's real guaranteed minimum. So a typed `10` may settle to
/// `9.99999998`: the same **display == memo** rule the rest of this file keeps,
/// applied to the direction the user did not type.
///
/// Returns 0 for a non-positive output or price — there is no meaningful source
/// amount for either, and the caller's validation rejects both upstream.
func limitSourceAmount(
    forTargetOutput targetOutput: Decimal,
    targetPrice: Decimal,
    sourceDecimals: Int
) -> BigInt {
    guard targetOutput > 0, targetPrice > 0 else { return 0 }

    // Quantize to the precision the Sell field can DISPLAY before scaling into
    // the coin's smallest units. Without this, an 18-decimal source derives an
    // amount carrying more decimals than the field renders, so the deposit shown
    // on screen is not the deposit that gets signed — the exact divergence this
    // form is built to prevent. Truncating (not rounding) keeps the derived
    // deposit at or below what the stated output requires.
    var rawUnits = targetOutput / targetPrice
    var units = Decimal()
    NSDecimalRound(&units, &rawUnits, limitAmountDisplayPrecision, .down)

    var scaled = Decimal()
    NSDecimalMultiplyByPowerOf10(&scaled, &units, Int16(sourceDecimals), .down)
    var truncated = Decimal()
    NSDecimalRound(&truncated, &scaled, 0, .down)

    guard !truncated.isNaN,
          let amount = BigInt(NSDecimalNumber(decimal: truncated).stringValue),
          amount > 0 else {
        return 0
    }
    return amount
}

/// Source amount (in the source coin's smallest units) to probe THORChain with
/// when seeding the market-price reference *before* the user enters an amount.
///
/// The old behaviour probed with a whole 1 unit (`10^decimals`) of the source.
/// For a cheap source (e.g. 1 RUNE ≈ $1.4) THORChain rejects the quote because
/// the target-chain outbound fee exceeds the tiny output, so `marketPriceRef`
/// never loads and the limit form shows no market reference. High-value sources
/// (1 BTC / 1 ETH) probe fine, which is why only cheap-source pairs looked
/// broken. Normalizing the probe to a fixed fiat notional (~$100) keeps it above
/// outbound fees for cheap sources while staying reasonable (a fraction of a
/// coin) for expensive ones.
///
/// When `sourceAmount > 0` it is returned verbatim; the notional only sizes the
/// pre-input probe. Note the caller refreshes the market reference on asset
/// change / first load (not on every amount keystroke), so in practice this
/// seeds a spot reference that stays valid until the pair changes. Falls back to
/// 1 whole unit when no price rate is available (`sourceFiatPricePerUnit <= 0`),
/// matching the prior seed.
func marketProbeAmount(
    sourceAmount: BigInt,
    sourceDecimals: Int,
    sourceFiatPricePerUnit: Decimal,
    notionalFiat: Decimal = 100
) -> BigInt {
    if sourceAmount > 0 { return sourceAmount }

    let oneUnit = BigInt(10).power(sourceDecimals)
    guard sourceFiatPricePerUnit > 0, notionalFiat > 0 else { return oneUnit }

    // Whole source coins worth `notionalFiat`, scaled up to smallest units.
    var units = notionalFiat / sourceFiatPricePerUnit
    var scaled = Decimal()
    NSDecimalMultiplyByPowerOf10(&scaled, &units, Int16(sourceDecimals), .plain)
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, .up)

    guard !rounded.isNaN,
          let probe = BigInt(NSDecimalNumber(decimal: rounded).stringValue),
          probe > 0 else {
        return oneUnit
    }
    return probe
}

/// Preferred default SOURCE chain for the **limit-swap entry only**.
///
/// Two different situations arrive here as the same `marketDefaultChain`, and
/// `isSourceExplicit` is what tells them apart:
///
/// - **No intent** (`false`) — the shared market default sorts alphabetically
///   (`SwapCoinsResolver` picks the first held coin), which lands on a cheap
///   source like RUNE and presents an untradeable-looking RUNE→BTC default. Here
///   we prefer a high-value, liquid, THORChain-routable native source the vault
///   actually holds — BTC, then ETH — skipping any candidate that collides with
///   the target chain (which would be a self-pair).
/// - **Explicit intent** (`true`) — the user entered the swap from a specific
///   chain/coin, so that source is a real choice, not an alphabetical accident.
///   Honor it whenever it is usable, and only fall back to the preference above
///   when it isn't (unroutable, or a self-pair with the target).
///
/// **Never returns `targetChain` while any held, THORChain-routable alternative
/// native source exists** (a same-chain source→target is not THORChain-routable).
/// It only returns the target chain (or an unroutable inherited default) in the
/// degenerate case where the vault holds no other routable native source. Pure so
/// it is unit-testable; the caller resolves the chosen chain back to the concrete
/// vault `Coin`. Does NOT change the shared market default.
func preferredLimitSourceChain(
    marketDefaultChain: Chain,
    isSourceExplicit: Bool,
    targetChain: Chain,
    availableNativeChains: Set<Chain>
) -> Chain {
    // 0. An explicitly chosen source is real user intent — keep it when it's
    //    usable (THORChain-routable and not a self-pair). Same rule as step 2;
    //    intent is what promotes it above the BTC/ETH preference. An unusable
    //    explicit source falls through rather than seeding an unplaceable order.
    if isSourceExplicit, marketDefaultChain != targetChain, isThorchainRoutable(chain: marketDefaultChain) {
        return marketDefaultChain
    }
    // 1. High-value routable sources the vault holds (BTC → ETH), excluding a
    //    self-pair with the target. (BTC/ETH are always THORChain-routable.)
    for candidate in [Chain.bitcoin, .ethereum]
    where candidate != targetChain && availableNativeChains.contains(candidate) {
        return candidate
    }
    // 2. Keep the market default when it's THORChain-routable and not a self-pair.
    if marketDefaultChain != targetChain, isThorchainRoutable(chain: marketDefaultChain) {
        return marketDefaultChain
    }
    // 3. Otherwise pick any other held, THORChain-ROUTABLE native chain
    //    (deterministic order). Never seed an unroutable source (e.g. SOL/TON):
    //    the picker filters those out, but the initial seed bypasses that filter,
    //    so an unroutable seed would enable Place Order only for `preparePlaceableOrder`
    //    to silently reject it.
    if let alternative = availableNativeChains
        .filter({ $0 != targetChain && isThorchainRoutable(chain: $0) })
        .sorted(by: { $0.name < $1.name })
        .first {
        return alternative
    }
    // 4. Nothing routable else is held — a self-pair (or the inherited default) is
    //    unavoidable; the caller keeps its concrete market-default coin.
    return marketDefaultChain
}

/// Resolves the concrete SOURCE `Coin` the **limit entry** seeds with, given the
/// shared market-default source, the target coin, and the vault's coins. Maps
/// `preferredLimitSourceChain` back to a native `Coin` the vault holds, falling
/// back to the market default when the preferred chain isn't held (or already is
/// the market default). Pure so the "held + non-colliding with target" guarantee
/// is directly testable. Does NOT change the shared market default.
///
/// `isSourceExplicit` marks `marketDefault` as a source the user actually chose
/// (entered the swap from) rather than an alphabetical fallback — see
/// `preferredLimitSourceChain`.
func limitDefaultSourceCoin(
    marketDefault: Coin,
    isSourceExplicit: Bool,
    targetCoin: Coin,
    vaultCoins: [Coin]
) -> Coin {
    let availableNativeChains = Set(vaultCoins.filter { $0.isNativeToken }.map(\.chain))
    let chain = preferredLimitSourceChain(
        marketDefaultChain: marketDefault.chain,
        isSourceExplicit: isSourceExplicit,
        targetChain: targetCoin.chain,
        availableNativeChains: availableNativeChains
    )
    guard chain != marketDefault.chain,
          let coin = vaultCoins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
        return marketDefault
    }
    return coin
}

/// Whether a change to a mirrored text field is a genuine USER edit rather than
/// the echo of a value the view just wrote PROGRAMMATICALLY (`newText ==
/// lastSyncedText`).
///
/// The USD display mirrors the canonical asset-terms target price, and the two
/// amount fields mirror each other through it. All three are rewritten by the
/// view whenever the price moves for some other reason (a preset tap, a chart
/// drag, a new rate, a mode switch), and the resulting field change would
/// otherwise convert straight back through that field's coarser display precision
/// and silently round the canonical (LIM-source) price. Pure so the
/// feedback-suppression is unit-testable.
func isUserFieldEdit(newText: String, lastSyncedText: String?) -> Bool {
    newText != lastSyncedText
}

/// The lowest expiry the app will accept, given the ceiling currently in force.
///
/// Normally this is just the app's own floor. It collapses to the ceiling when a
/// mimir ever reports a cap BELOW that floor: the floor is ours and the ceiling
/// is the protocol's, so the protocol has to win — otherwise the accepted range
/// is empty and no order can be placed at all.
///
/// Shared by the clamp and the validator on purpose. They encode one rule, and
/// when each spelled it out separately they disagreed in exactly this case: the
/// clamp produced the ceiling and the validator then rejected the value the
/// clamp had just produced.
func effectiveMinExpiryBlocks(maxBlocks: Int) -> Int {
    min(THORChainConstants.minLimitSwapAgeBlocks, max(maxBlocks, 1))
}

/// Constrain a chosen expiry to what THORChain will actually honour.
///
/// The ceiling matters because the chain clamps **silently**: an interval above
/// `StreamingLimitSwapMaxAge` is overwritten with the max rather than rejected,
/// so an unclamped app would show the user a window the chain never granted.
/// Clamping here means the number on screen, the number in the memo, and the
/// number the queue enforces are the same one.
func clampLimitExpiryBlocks(_ blocks: Int, maxBlocks: Int) -> Int {
    let ceiling = max(maxBlocks, 1)
    return min(max(blocks, effectiveMinExpiryBlocks(maxBlocks: ceiling)), ceiling)
}

/// A block count as a duration a person reads — `45m`, `12h`, `2d 6h`.
///
/// Shared by the expiry card, the custom-duration sheet, and the co-signer's
/// Verify screen, which previously rendered `"\(hours)h"` from a separate
/// whole-hours field. With custom durations that field could no longer state
/// every order (a 150-minute expiry is not a whole number of hours), so the
/// block count became the single representation and this is how it is spelled.
///
/// Zero-valued components are omitted rather than padded, so `2d` doesn't render
/// as `2d 0h 0m`. Sub-minute counts (only reachable from a hand-built memo, never
/// from this app's picker) floor to `0m` rather than claiming a duration.
/// Days are only split out from **two** days up. That threshold is not cosmetic:
/// it is what makes this one function reproduce the preset row the app has always
/// shown — `12h`, `24h`, `3d`. Splitting at one day would render the 24h preset as
/// `1d`, quietly renaming a pill nobody asked to change, and would leave the pills
/// and this formatter speaking differently about the same duration.
func formatLimitExpiry(blocks: Int) -> String {
    let totalMinutes = max(THORChainConstants.minutes(forBlocks: blocks), 0)
    let splitsDays = totalMinutes >= 2 * 1440
    let days = splitsDays ? totalMinutes / 1440 : 0
    let remainder = totalMinutes - days * 1440
    let hours = remainder / 60
    let minutes = remainder % 60

    var parts: [String] = []
    if days > 0 { parts.append(String(format: "limitSwap.expiry.days".localized, days)) }
    if hours > 0 { parts.append(String(format: "limitSwap.expiry.hours".localized, hours)) }
    if minutes > 0 { parts.append(String(format: "limitSwap.expiry.minutes".localized, minutes)) }
    guard !parts.isEmpty else {
        return String(format: "limitSwap.expiry.minutes".localized, 0)
    }
    return parts.joined(separator: " ")
}

/// Target price at `pct` percent above (or below, when negative) `marketPrice`.
///
/// `pct` is a `Decimal` rather than an `Int` because the stepper moves in tenths
/// — `+7.5%` is as valid an intent as the preset pills' whole numbers, and routing
/// both through one function keeps the pills and the sheet from drifting apart.
/// It is the exact inverse of `computePctFromMarket`.
func computePresetPrice(marketPrice: Decimal, pctAboveMarket pct: Decimal) -> Decimal {
    let multiplier = (Decimal(100) + pct) / Decimal(100)
    return marketPrice * multiplier
}

func computePctFromMarket(targetPrice: Decimal, marketPrice: Decimal) -> Decimal {
    guard marketPrice != 0 else { return 0 }
    return (targetPrice - marketPrice) / marketPrice * Decimal(100)
}

// MARK: - Custom percent-offset stepper

/// What one tap of the custom-offset sheet's − / + moves, and the grid every
/// value it can hold sits on.
let limitPctOffsetStep = Decimal(string: "0.1")!

/// How far the custom-offset stepper may be walked.
///
/// THORChain imposes no bound of its own — the memo carries whatever LIM the
/// price implies — so this exists to stop the control producing something that is
/// not a price. At `-100%` the target is zero, and a zero LIM means "fill at ANY
/// price", the one thing a limit order must never say (`computeLim` rejects it);
/// the floor stays a whole percent clear of that edge. The ceiling is far past any
/// realistic target and is there so a held `+` cannot walk the price somewhere the
/// price field can no longer render.
///
/// **The floor is necessary and NOT sufficient, and no fixed percentage could be.**
/// The resolved price is rounded to the memo LIM's 8 decimals, so against a small
/// enough market — a sub-cent token quoted in BTC — even `-99%` rounds to zero.
/// The sheet therefore refuses on the resolved PRICE, not on the offset; this
/// range only keeps the control in a sane band.
let limitPctOffsetRange: ClosedRange<Decimal> = Decimal(-99)...Decimal(999)

func clampLimitPctOffset(_ pct: Decimal) -> Decimal {
    min(max(pct, limitPctOffsetRange.lowerBound), limitPctOffsetRange.upperBound)
}

/// The value the custom-offset sheet opens on, given the order's live offset.
///
/// Snapped onto the stepper's own grid, because the live offset is derived from a
/// price rounded to 8 decimals and is routinely an arbitrary number (`+7.5512%`
/// after a chart drag). Seeding that raw would make the first `+` tap read as
/// `+7.6512` — a control that appears not to know its own step. Nothing is applied
/// to the draft until Set is pressed, so the snap costs the user nothing if they
/// back out.
func limitPctOffsetSeed(from pct: Decimal) -> Decimal {
    var rounded = Decimal()
    var input = clampLimitPctOffset(pct)
    // 1 decimal place == `limitPctOffsetStep`; the two move together.
    NSDecimalRound(&rounded, &input, 1, .plain)
    return rounded
}

/// Step size after `seconds` of holding − or + down.
///
/// The *step* accelerates rather than the tick rate: at a fixed 0.1 it would take
/// 200 ticks to reach the +20% where the far-above-market warning starts, and a
/// tick rate fast enough to fix that would make a short hold unlandable. Starting
/// at 0.1 keeps a hold that is only marginally longer than a tap from overshooting.
func limitPctStep(forHeldSeconds seconds: Double) -> Decimal {
    switch seconds {
    case ..<1.0:
        return limitPctOffsetStep
    case ..<2.5:
        return Decimal(string: "0.5")!
    default:
        return 1
    }
}

func evaluateWarning(targetPrice: Decimal, marketPrice: Decimal) -> LimitSwapWarning? {
    if targetPrice <= marketPrice {
        return .priceAtOrBelowMarket
    }
    let upperBound = marketPrice * Decimal(12) / Decimal(10)
    if targetPrice > upperBound {
        return .priceFarAboveMarket
    }
    return nil
}

// MARK: - Input parsing (locale-aware)

/// Parse a user-entered numeric string into a `Decimal`, locale-aware.
///
/// **Fund-safety:** these values feed the SIGNED memo LIM (target price) and the
/// deposit amount (sell amount). A naive `","→"."` + `Decimal(string:)` silently
/// mis-parses a pasted GROUPED number — in an `en_US` locale `"1,000"` became
/// `Decimal("1.000") == 1.0`, i.e. 1000× too small — which would place a resting
/// order at a price/amount far off what the field shows. Route through the shared
/// `parseInput` (the same locale-aware parser the market amount fields use) so a
/// grouped `"1,000"` is `1000` and a comma-decimal locale's `"1,5"` is `1.5`.
///
/// The `Decimal(string:)` fallback fires only for in-progress typing states the
/// strict locale parser rejects (e.g. a lone trailing separator like `"1."`), so
/// keystroke-by-keystroke editing isn't broken; it never re-introduces the
/// grouping mis-parse because `parseInput` already handles any grouped number.
func parseLimitDecimal(_ text: String, locale: Locale = .current) -> Decimal {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return 0 }
    if let parsed = trimmed.parseInput(locale: locale) {
        return parsed
    }
    return Decimal(string: trimmed.replacingOccurrences(of: ",", with: ".")) ?? 0
}

/// Locale-aware parse of the target-price field into asset-terms `Decimal`.
func parseLimitPrice(_ text: String, locale: Locale = .current) -> Decimal {
    parseLimitDecimal(text, locale: locale)
}

/// The percent-from-market readout's display form: always signed, two decimals.
///
/// The `+` is explicit because the sign is the whole point of the readout — an
/// unsigned `5.00%` reads as a magnitude, while `+5.00%` reads as a direction.
/// ASCII `-` (not the typographic minus), matching every other number this form
/// prints.
///
/// `locale` is explicit rather than left to the formatter's ambient default, so a
/// test pins the separator instead of inheriting the host machine's.
func formatLimitPercent(_ pct: Decimal, locale: Locale = .current) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.usesGroupingSeparator = false
    formatter.positivePrefix = "+"
    formatter.negativePrefix = "-"
    return formatter.string(from: NSDecimalNumber(decimal: pct))
        ?? NSDecimalNumber(decimal: pct).stringValue
}

/// Locale-aware parse of the sell-amount field into the source coin's smallest
/// units. Truncates (rounds toward zero) at the coin's decimal precision, exactly
/// as the prior naive parser did — only the locale/grouping handling changes.
func parseLimitAmount(_ text: String, decimals: Int, locale: Locale = .current) -> BigInt {
    let decimal = parseLimitDecimal(text, locale: locale)
    guard decimal > 0 else { return 0 }
    var scaled = Decimal()
    var input = decimal
    NSDecimalMultiplyByPowerOf10(&scaled, &input, Int16(decimals), .down)
    var truncated = Decimal()
    NSDecimalRound(&truncated, &scaled, 0, .down)
    return BigInt(NSDecimalNumber(decimal: truncated).stringValue) ?? 0
}
