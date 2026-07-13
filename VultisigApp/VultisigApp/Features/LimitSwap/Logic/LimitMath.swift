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

/// Preferred default SOURCE chain for the **limit-swap entry only**. The shared
/// market default sorts alphabetically (`SwapCoinsResolver` picks the first held
/// coin), which lands on a cheap source like RUNE and presents an
/// untradeable-looking RUNE→BTC default. Prefer a high-value, liquid,
/// THORChain-routable native source the vault actually holds — BTC, then ETH —
/// skipping any candidate that collides with the target chain (which would be a
/// self-pair).
///
/// **Never returns `targetChain` while any held, THORChain-routable alternative
/// native source exists** (a same-chain source→target is not THORChain-routable).
/// It only returns the target chain (or an unroutable inherited default) in the
/// degenerate case where the vault holds no other routable native source. Pure so
/// it is unit-testable; the caller resolves the chosen chain back to the concrete
/// vault `Coin`. Does NOT change the shared market default.
func preferredLimitSourceChain(
    marketDefaultChain: Chain,
    targetChain: Chain,
    availableNativeChains: Set<Chain>
) -> Chain {
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
func limitDefaultSourceCoin(marketDefault: Coin, targetCoin: Coin, vaultCoins: [Coin]) -> Coin {
    let availableNativeChains = Set(vaultCoins.filter { $0.isNativeToken }.map(\.chain))
    let chain = preferredLimitSourceChain(
        marketDefaultChain: marketDefault.chain,
        targetChain: targetCoin.chain,
        availableNativeChains: availableNativeChains
    )
    guard chain != marketDefault.chain,
          let coin = vaultCoins.first(where: { $0.chain == chain && $0.isNativeToken }) else {
        return marketDefault
    }
    return coin
}

/// Whether a change to the USD price field is a genuine USER edit rather than the
/// echo of a value the view just wrote PROGRAMMATICALLY (`newText ==
/// lastSyncedText`). The limit price display keeps a USD mirror of the
/// asset-terms target price; a preset tap / rate change / mode switch rewrites
/// that mirror, and without this guard the resulting field change would convert
/// back through the 2-dp USD display and silently round the canonical
/// (LIM-source) price. Pure so the feedback-suppression is unit-testable.
func isUserUsdPriceEdit(newText: String, lastSyncedText: String?) -> Bool {
    newText != lastSyncedText
}

func computeExpiryBlocks(hours: Int) -> Int {
    return THORChainConstants.blocks(forHours: hours)
}

func computePresetPrice(marketPrice: Decimal, pctAboveMarket pct: Int) -> Decimal {
    let multiplier = (Decimal(100) + Decimal(pct)) / Decimal(100)
    return marketPrice * multiplier
}

func computePctFromMarket(targetPrice: Decimal, marketPrice: Decimal) -> Decimal {
    guard marketPrice != 0 else { return 0 }
    return (targetPrice - marketPrice) / marketPrice * Decimal(100)
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
