//
//  PerpsFlowViewModels.swift
//  VultisigApp
//
//  Perps view models for the ticket and the money / position sheets.
//  Each ends at a `PerpsReviewDocument` for the shared review sheet; none of
//  them can sign or submit.
//

import Foundation
import OSLog
import WalletCore

private let perpsFlowLogger = Logger(subsystem: "com.vultisig.app", category: "perps")

extension PerpsVaultContext {
    @MainActor
    init(vault: Vault) {
        // Native USDC by contract, never by ticker: the deposit always authorizes this token.
        let usdc = vault.coins.first { $0.chain == .arbitrum && $0.contractAddress.lowercased() == HLCctp.arbitrumUsdc }
        // The vault's main EVM address (same on every EVM chain), without
        // depending on which EVM chains the user keeps in the wallet.
        let mainAddress = vault.coins.first { ($0.chain == .ethereum || $0.chain == .arbitrum) && $0.isNativeToken }?.address
            ?? PerpsDerivedAccount.derive(.main, vault: vault)?.address ?? ""
        let isSupported = PerpsConfig.isSupported(vault: vault)
        self.init(
            name: Self.demoVaultName ?? vault.name,
            address: mainAddress,
            arbitrumUsdcBalance: Self.demoVaultUsdc ?? usdc?.balanceDecimal,
            tradingAddress: isSupported ? PerpsDerivedAccount.derive(.trading, vault: vault)?.address : nil,
            isSupported: isSupported,
            tierKey: vault.pubKeyECDSA
        )
    }

    /// Debug only: a long vault name, to check the "To" row truncates.
    private static var demoVaultName: String? {
        #if DEBUG
        PerpsConfig.debugVaultName
        #else
        nil
        #endif
    }

    /// Debug story: a fictional vault balance, like the fictional account.
    private static var demoVaultUsdc: Decimal? {
        #if DEBUG
        PerpsDemoStory.isOn ? PerpsDemoStory.vaultUsdc : nil
        #else
        nil
        #endif
    }
}

enum PerpsInput {
    /// Parses what an amount or price field holds. A lone comma is the
    /// decimal pad's separator in comma-decimal locales ("76,5", "0,125"),
    /// never grouping: editable fields are prefilled ungrouped (`priceText`),
    /// so "1,500" typed on a German keypad is 1.5, not 1,500. With both
    /// separators the last one is the decimal ("1,250.75", "75.000,5").
    /// Anything else that is not a plain number is rejected.
    static func decimal(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        if let last = cleaned.lastIndex(where: { $0 == "." || $0 == "," }) {
            let decimalSeparator = cleaned[last]
            let grouping: Character = decimalSeparator == "." ? "," : "."
            if cleaned.contains(grouping) {
                cleaned.removeAll { $0 == grouping }
            }
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard cleaned.range(of: #"^\d*\.?\d*$"#, options: .regularExpression) != nil,
              cleaned.contains(where: \.isNumber) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func text(_ value: Decimal) -> String { HLWireFormat.decimalString(value) }

    /// What a keypad field shows while typing: "62287.5" reads "62,287.5".
    /// The text itself stays plain digits and one ".", whatever the locale.
    static func grouped(_ text: String) -> String {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let integer = parts.first else { return text }
        var grouped = ""
        for (index, character) in integer.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let head = String(grouped.reversed())
        return parts.count > 1 ? head + "." + parts[1] : head
    }

    /// USDC amounts always show cents: "101.30".
    static func usdcText(_ value: Decimal) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), NSDecimalNumber(decimal: value).doubleValue)
    }

    /// A price for an input field: ungrouped, so a comma in a field is only
    /// ever a decimal separator.
    static func priceText(_ value: Decimal) -> String { PerpsFormat.plainPrice(value, grouped: false) }
}

// MARK: - Ticket

@MainActor
final class PerpsTicketViewModel: ObservableObject {
    @Published var amountText = "100"
    @Published var leverage: Int
    @Published var showsSizeInCoin = false
    /// Auto close starts on with a default stop that follows the amount and
    /// leverage until the user edits it in the auto close sheet.
    @Published var autoCloseOn = true
    @Published private(set) var autoCloseEdited = false
    @Published private(set) var editedTakeProfit: Decimal?
    @Published private(set) var editedStopLoss: Decimal?

    let side: PerpsSide
    @Published private(set) var market: PerpsMarket
    @Published private(set) var account: PerpsAccountSnapshot?
    let vault: PerpsVaultContext
    let maxAllowedLeverage: Int
    /// The VULT tier this ticket prices with: one snapshot feeds the fee shown,
    /// Max, and the builder fee the order carries, so they can never disagree.
    @Published private(set) var vultTier: VultDiscountTier?

    /// `vultTier` defaults to this vault's own resolved tier (`PerpsVultTier.tier(for:)`).
    init(side: PerpsSide, market: PerpsMarket, account: PerpsAccountSnapshot?, vault: PerpsVaultContext,
         vultTier: VultDiscountTier?? = nil) {
        self.side = side
        self.market = market
        self.account = account
        self.vault = vault
        self.vultTier = vultTier ?? PerpsVultTier.tier(for: vault.tierKey)
        let isFirstTrade = (account?.positions.isEmpty ?? true) && (account?.fills.isEmpty ?? true)
        maxAllowedLeverage = min(isFirstTrade ? PerpsConfig.firstTradeMaxLeverage : market.maxLeverage, market.maxLeverage)
        leverage = min(PerpsConfig.defaultLeverage, market.maxLeverage)
    }

    /// After a reconnect: fresh price and account, so size, available and the
    /// default stop are recomputed before Review comes back. The draft stays.
    func refresh(market: PerpsMarket, account: PerpsAccountSnapshot?) {
        self.market = market
        self.account = account
        vultTier = PerpsVultTier.tier(for: vault.tierKey)
    }

    /// A position already open in this market. Adding to it or trading against
    /// it is not modelled yet, so the ticket refuses rather than re-levering it.
    var openPosition: HLPosition? { account?.position(coin: market.coin) }

    var title: String { String(format: side == .long ? "perpsLongCoin".localized : "perpsShortCoin".localized, market.coin) }
    var isNewAccount: Bool { account?.isEmpty ?? true }
    var availableToTrade: Decimal { account?.availableToTrade ?? 0 }
    var referencePrice: Decimal { market.midPrice ?? market.markPrice }
    /// Evenly spaced slider stops up to the market's max (1/2/3/5/10/20/40×;
    /// a 25× market ends on 25×).
    var leverageOptions: [Int] {
        let stops = PerpsConfig.leveragePresets.filter { $0 <= market.maxLeverage }
        return stops.last == market.maxLeverage ? stops : stops + [market.maxLeverage]
    }

    /// What the Leverage sheet shows live for a candidate leverage, before it is applied.
    func preview(leverage candidate: Int) -> (size: Decimal, liquidation: Decimal?) {
        let estimate = PerpsMath.estimate(side: side, margin: PerpsInput.decimal(amountText) ?? 0, leverage: candidate, price: referencePrice,
                                          szDecimals: market.szDecimals, maxLeverage: market.maxLeverage, marginMode: .isolated,
                                          schedule: market.marginSchedule)
        return (estimate.notional, estimate.liquidationPrice)
    }

    /// 25% / 50% of what can be traded (floored to cents); Max uses `applyMax`.
    func applyFraction(_ fraction: Decimal) {
        amountText = PerpsInput.usdcText((affordableMargin * fraction).rounded(scale: 2, mode: .down))
    }

    /// Max fills what the account can trade with, or the vault's USDC when the
    /// account is empty (the difference arrives by deposit).
    func applyMax() {
        amountText = PerpsInput.usdcText(affordableMargin.rounded(scale: 2, mode: .down))
    }

    /// The most margin the balance can fund once trading fees (and, from the
    /// vault, the deposit's forwarding + first-deposit fees) are taken out:
    /// margin + margin x leverage x fee rate fits in what is there.
    var affordableMargin: Decimal {
        let fromAccount = availableToTrade > 0
        // The vault side is floored to cents first: the deposit is rounded up to
        // cents, so a fractional-cent balance must not let Max ask for more.
        var base = fromAccount ? availableToTrade : (vault.arbitrumUsdcBalance ?? 0).rounded(scale: 2, mode: .down)
        if !fromAccount { base -= HLCctp.forwardingFee + (isNewAccount ? HLCctp.activationFee : 0) }
        guard base > 0 else { return 0 }
        let feeRate = PerpsMath.baseTakerFeeRate + PerpsConfig.builderFeeRate(tier: vultTier)
        return base / (1 + Decimal(leverage) * feeRate)
    }

    /// Stop 7% from entry, or halfway to liquidation if that is closer.
    var defaultStop: Decimal? {
        let estimate = PerpsMath.estimate(side: side, margin: PerpsInput.decimal(amountText) ?? 0, leverage: leverage, price: referencePrice,
                                          szDecimals: market.szDecimals, maxLeverage: market.maxLeverage, marginMode: .isolated,
                                          schedule: market.marginSchedule)
        var distance = PerpsConfig.defaultStopDistance
        if let liquidation = estimate.liquidationPrice, referencePrice > 0 {
            distance = min(distance, abs(referencePrice - liquidation) / referencePrice / 2)
        }
        guard distance > 0 else { return nil }
        let stop = PerpsFormat.roundedPrice(referencePrice * (1 - side.sign * distance))
        return HLWireFormat.price(stop, szDecimals: market.szDecimals)
    }

    var takeProfit: Decimal? { autoCloseOn && autoCloseEdited ? editedTakeProfit : nil }
    var stopLoss: Decimal? {
        guard autoCloseOn else { return nil }
        return autoCloseEdited ? editedStopLoss : defaultStop
    }

    func applyAutoClose(takeProfit: Decimal?, stopLoss: Decimal?) {
        autoCloseEdited = true
        editedTakeProfit = takeProfit
        editedStopLoss = stopLoss
        autoCloseOn = takeProfit != nil || stopLoss != nil
    }

    var ticket: PerpsTicket {
        PerpsTicket(side: side, margin: PerpsInput.decimal(amountText) ?? 0, leverage: leverage, marginMode: .isolated,
                    limitPrice: nil, takeProfit: takeProfit, stopLoss: stopLoss)
    }

    /// "Stop $62,500", "TP $72,000 · Stop $62,500" or "Off".
    var stopLossValue: String { PerpsFlows.stopLossValue(stopLoss) }

    /// "$250.00 available", "$0.00 available" with nothing to trade. Leverage
    /// has its own row, so it is not repeated here.
    var summaryLine: String {
        String(format: "perpsAvailableAmount".localized, PerpsFormat.usd(availableToTrade))
    }

    /// "Add 101.02 USDC to trade.": what the vault is missing to fund the order.
    var shortfallMessage: String? {
        guard let transfer = fundingShortfall else { return nil }
        let missing = max(0, transfer - (vault.arbitrumUsdcBalance ?? 0))
        return String(format: "perpsAddToTrade".localized, PerpsFormat.usd(missing.rounded(scale: 2, mode: .up)))
    }

    /// For the screen (estimate, costs, issue): read on every render, so it
    /// takes no nonce. The review reserves real ones (`reviewDocument`).
    var plan: Result<PerpsOrderPlan, PerpsOrderPlannerError> { plan(nonce: 0) }

    private func plan(nonce: UInt64) -> Result<PerpsOrderPlan, PerpsOrderPlannerError> {
        do {
            return .success(try PerpsOrderPlanner.plan(market: market, ticket: ticket, nonce: nonce,
                                                       builder: PerpsConfig.builderFee(tier: vultTier), openPosition: openPosition))
        } catch let error as PerpsOrderPlannerError {
            return .failure(error)
        } catch {
            // Wire formatting refused a value: say so, never pretend it is too small.
            perpsFlowLogger.error("Perps order plan failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.requestBuildFailed)
        }
    }

    var estimate: PerpsOrderEstimate? {
        if case .success(let plan) = plan { return plan.estimate }
        return nil
    }

    var costs: PerpsTicketCosts? {
        guard case .success(let plan) = plan else { return nil }
        return PerpsFlows.costs(plan: plan, availableToTrade: availableToTrade, isNewAccount: isNewAccount, tier: vultTier)
    }

    var sizeText: String {
        guard let estimate else { return "-" }
        return showsSizeInCoin ? "\(HLWireFormat.decimalString(estimate.size)) \(market.coin)" : PerpsFormat.usd(estimate.notional)
    }

    /// One inline reason the order cannot be reviewed, or nil.
    var issue: String? {
        guard (PerpsInput.decimal(amountText) ?? 0) > 0 else { return nil }
        if case .failure(let error) = plan {
            switch error {
            case .sizeTooSmall, .minimumNotional: return "perpsMinimumNotional".localized
            case .leverageOutOfRange: return "perpsLeverageOutOfRange".localized
            case .isolatedOnly: return "perpsIsolatedOnly".localized
            case .missingLimitPrice: return nil
            case .invalidTriggerPrice: return "perpsInvalidPrice".localized
            case .requestBuildFailed: return "perpsReviewUnavailable".localized
            case .positionOpen: return positionOpenMessage
            }
        }
        if let costs, costs.transfer > 0, let reason = PerpsFlows.fundingIssue(amount: costs.transfer, vault: vault) { return reason }
        return PerpsTriggerRules.issue(side: side, reference: referencePrice, liquidation: estimate?.liquidationPrice,
                                       takeProfit: ticket.takeProfit, stopLoss: ticket.stopLoss)
    }

    var canReview: Bool { estimate != nil && issue == nil }

    /// USDC the vault is short of to fund this order, when that is the only
    /// thing in the way. The ticket then offers Add funds and keeps its draft.
    var fundingShortfall: Decimal? {
        guard let costs, costs.transfer > 0, PerpsFlows.fundingIssue(amount: costs.transfer, vault: vault) != nil else { return nil }
        return costs.transfer
    }

    func reviewDocument() -> PerpsReviewDocument? {
        guard canReview,
              case .success(let plan) = plan(nonce: HyperliquidExchangeDryRunClient.shared.nonces.next(count: 2)) else { return nil }
        // Costs from this same plan and tier: the fee shown is the fee signed.
        let costs = PerpsFlows.costs(plan: plan, availableToTrade: availableToTrade, isNewAccount: isNewAccount, tier: vultTier)
        return PerpsFlows.order(plan: plan, costs: costs, vault: vault, isNewAccount: isNewAccount)
    }

    /// "You already have a BTC long open. …"
    var positionOpenMessage: String? {
        openPosition.map { PerpsFlows.positionOpenMessage($0) }
    }
}

/// Where take profit and stop loss may sit relative to the reference price.
enum PerpsTriggerRules {
    static func issue(side: PerpsSide, reference: Decimal, liquidation: Decimal?, takeProfit: Decimal?, stopLoss: Decimal?) -> String? {
        // Zero, or a sub-tick price that snapped to zero, is never a trigger.
        if [stopLoss, takeProfit].contains(where: { ($0 ?? 1) <= 0 }) { return "perpsInvalidPrice".localized }
        if let stop = stopLoss {
            if side == .long ? stop >= reference : stop <= reference {
                return side == .long ? "perpsStopBelowPrice".localized : "perpsStopAbovePrice".localized
            }
            if let liquidation, side == .long ? stop <= liquidation : stop >= liquidation {
                return "perpsStopBeyondLiquidation".localized
            }
        }
        if let take = takeProfit, side == .long ? take <= reference : take >= reference {
            return side == .long ? "perpsTakeAbovePrice".localized : "perpsTakeBelowPrice".localized
        }
        return nil
    }

    /// Estimated P&L if a trigger fills at its price.
    static func outcome(side: PerpsSide, entry: Decimal, trigger: Decimal, size: Decimal) -> Decimal {
        PerpsMath.unrealizedPnl(side: side, entryPrice: entry, markPrice: trigger, size: size)
    }
}

// MARK: - Auto close sheet

@MainActor
final class PerpsAutoCloseViewModel: ObservableObject {
    @Published var takeText: String
    @Published var stopText: String

    @Published private(set) var side: PerpsSide
    /// False after a failed poll until a fresh tick: Review / Done stay off meanwhile.
    @Published private(set) var pricesAreFresh = true
    @Published private(set) var entry: Decimal
    @Published private(set) var reference: Decimal
    @Published private(set) var size: Decimal
    @Published private(set) var liquidation: Decimal?
    /// The market's lot decimals: an edited trigger is snapped to a valid
    /// Hyperliquid price before it is checked, so the price validated, shown
    /// in the review and signed is the same number.
    let szDecimals: Int

    init(side: PerpsSide, entry: Decimal, reference: Decimal, size: Decimal, liquidation: Decimal?, szDecimals: Int,
         takeProfit: Decimal?, stopLoss: Decimal?) {
        self.side = side
        self.szDecimals = szDecimals
        self.entry = entry
        self.reference = reference
        self.size = size
        self.liquidation = liquidation
        initialTake = takeProfit
        initialStop = stopLoss
        // Exact and ungrouped, so opening the sheet never moves a live trigger.
        let take = takeProfit.map(HLWireFormat.decimalString) ?? ""
        let stop = stopLoss.map(HLWireFormat.decimalString) ?? ""
        takeText = take
        stopText = stop
        initialTakeText = take
        initialStopText = stop
    }

    /// The position's live numbers from the 15 s poll. Typed triggers stay as
    /// they are; checks and outcomes follow the new price, size and liquidation.
    func refresh(_ inputs: PerpsExitInputs) {
        if inputs.side != side {
            // The position flipped elsewhere: nothing typed for the old side still applies.
            side = inputs.side
            takeText = inputs.takeProfit.map(HLWireFormat.decimalString) ?? ""
            stopText = inputs.stopLoss.map(HLWireFormat.decimalString) ?? ""
        } else {
            // Untouched fields follow the venue's triggers; typed ones stay.
            if takeText == initialTakeText { takeText = inputs.takeProfit.map(HLWireFormat.decimalString) ?? "" }
            if stopText == initialStopText { stopText = inputs.stopLoss.map(HLWireFormat.decimalString) ?? "" }
        }
        initialTake = inputs.takeProfit
        initialStop = inputs.stopLoss
        initialTakeText = inputs.takeProfit.map(HLWireFormat.decimalString) ?? ""
        initialStopText = inputs.stopLoss.map(HLWireFormat.decimalString) ?? ""
        entry = inputs.entry
        reference = inputs.reference
        size = inputs.size
        liquidation = inputs.liquidation
    }

    func setPricesFresh(_ isFresh: Bool) { pricesAreFresh = isFresh }

    private var initialTake: Decimal?
    private var initialStop: Decimal?
    private var initialTakeText: String
    private var initialStopText: String

    /// An untouched field keeps the existing trigger exactly; an edited one is
    /// rounded to what the UI shows.
    var takeProfit: Decimal? { trigger(takeText, initialText: initialTakeText, initial: initialTake) }
    var stopLoss: Decimal? { trigger(stopText, initialText: initialStopText, initial: initialStop) }

    /// Text that is there but is not a number. It must block Done / Review:
    /// read as "no trigger", it would cancel the existing one.
    var hasInvalidInput: Bool {
        [takeText, stopText].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty && PerpsInput.decimal($0) == nil }
    }

    private func trigger(_ text: String, initialText: String, initial: Decimal?) -> Decimal? {
        if text == initialText, let initial { return initial }
        return PerpsInput.decimal(text).map { HLWireFormat.price(PerpsFormat.roundedPrice($0), szDecimals: szDecimals) }
    }

    func outcome(_ trigger: Decimal?) -> Decimal? {
        trigger.map { PerpsTriggerRules.outcome(side: side, entry: entry, trigger: $0, size: size) }
    }

    var issue: String? {
        if !pricesAreFresh { return "perpsPricesUpdating".localized }
        if hasInvalidInput { return "perpsInvalidPrice".localized }
        return PerpsTriggerRules.issue(side: side, reference: reference, liquidation: liquidation, takeProfit: takeProfit, stopLoss: stopLoss)
    }
}

/// What an open stop loss / take profit sheet follows while the screen polls.
struct PerpsExitInputs: Hashable {
    let side: PerpsSide
    let entry: Decimal
    let reference: Decimal
    let size: Decimal
    let liquidation: Decimal?
    /// The triggers in force: untouched fields follow them.
    let takeProfit: Decimal?
    let stopLoss: Decimal?

    init(side: PerpsSide, entry: Decimal, reference: Decimal, size: Decimal, liquidation: Decimal?,
         takeProfit: Decimal?, stopLoss: Decimal?) {
        self.side = side
        self.entry = entry
        self.reference = reference
        self.size = size
        self.liquidation = liquidation
        self.takeProfit = takeProfit
        self.stopLoss = stopLoss
    }

    init(position: HLPosition, market: PerpsMarket, triggers: [HLFrontendOrder]) {
        self.init(side: position.isLong ? .long : .short, entry: position.entryPx?.value ?? market.markPrice,
                  reference: market.markPrice, size: abs(position.szi.value), liquidation: position.liquidationPx?.value,
                  takeProfit: triggers.first(where: \.isTakeProfit)?.triggerPx?.value,
                  stopLoss: triggers.first(where: \.isStopLoss)?.triggerPx?.value)
    }
}

/// Which trigger field the keypad types into.
enum PerpsTriggerField: Hashable { case stopLoss, takeProfit }

extension PerpsAutoCloseViewModel {
    /// "Close if BTC drops 5% / 7% / 10% / 25%" (rises, for a short), from the entry.
    static let stopPresets: [Decimal] = [5, 7, 10, 25]

    func stopPrice(dropPercent: Decimal) -> Decimal {
        let raw = entry * (1 - side.sign * dropPercent / 100)
        return HLWireFormat.price(PerpsFormat.roundedPrice(raw), szDecimals: szDecimals)
    }

    func applyStopPreset(_ percent: Decimal) {
        stopText = HLWireFormat.decimalString(stopPrice(dropPercent: percent))
    }

    /// The preset the current stop equals, if any (7% for the default stop).
    var selectedStopPreset: Decimal? {
        guard let stopLoss else { return nil }
        return Self.stopPresets.first { stopPrice(dropPercent: $0) == stopLoss }
    }

    /// The stop loss / take profit edit for an open position, or nil when
    /// nothing changed or a trigger sits on the wrong side. A build failure
    /// is logged, never swallowed.
    func exitsReview(position: HLPosition, market: PerpsMarket, existing: [HLFrontendOrder], tier: VultDiscountTier?,
                     nonce: UInt64) -> PerpsReviewDocument? {
        // Validated against the exact position the document is built for.
        guard issue == nil, (position.isLong ? PerpsSide.long : .short) == side else { return nil }
        do {
            let document = try PerpsFlows.editExits(position: position, market: market, existing: existing,
                                                    stopLoss: stopLoss, takeProfit: takeProfit, tier: tier, nonce: nonce)
            return document.blockingIssue == nil ? document : nil
        } catch {
            perpsFlowLogger.error("Perps exit edit failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Validation only (nonce 0), for the Review button's enabled state.
    func canReviewExits(position: HLPosition, market: PerpsMarket, existing: [HLFrontendOrder], tier: VultDiscountTier?) -> Bool {
        exitsReview(position: position, market: market, existing: existing, tier: tier, nonce: 0) != nil
    }

    /// Prices take up to 6 decimals (Hyperliquid's cap), so small coins can be typed.
    func press(_ key: PerpsKeypadKey, into field: PerpsTriggerField) {
        switch field {
        case .stopLoss: stopText = PerpsKeypadKey.apply(key, to: stopText, maxDecimals: 6)
        case .takeProfit: takeText = PerpsKeypadKey.apply(key, to: takeText, maxDecimals: 6)
        }
    }
}

// MARK: - Add funds

@MainActor
final class PerpsFundsViewModel: ObservableObject {
    @Published var amountText = ""

    let account: PerpsAccountSnapshot?
    let vault: PerpsVaultContext

    init(account: PerpsAccountSnapshot?, vault: PerpsVaultContext, prefill: Decimal? = nil) {
        self.account = account
        self.vault = vault
        amountText = prefill.map { PerpsInput.usdcText($0.rounded(scale: 2, mode: .up)) } ?? ""
    }

    var amount: Decimal { PerpsInput.decimal(amountText) ?? 0 }
    var source: Decimal { vault.arbitrumUsdcBalance ?? 0 }

    func applyMax() { amountText = PerpsInput.usdcText(source.rounded(scale: 2, mode: .down)) }

    var issue: String? {
        guard amount > 0 else { return nil }
        if let reason = PerpsFlows.fundingIssue(amount: amount, vault: vault) { return reason }
        if amount <= HLCctp.forwardingFee + ((account?.isEmpty ?? true) ? HLCctp.activationFee : 0) { return "perpsDepositBelowFees".localized }
        return nil
    }

    var canReview: Bool { amount > 0 && issue == nil }

    func reviewDocument() -> PerpsReviewDocument? {
        guard canReview else { return nil }
        return PerpsFlows.addFunds(amount: amount, vault: vault, isNewAccount: account?.isEmpty ?? true)
    }
}

// MARK: - Close

/// 25 / 50 / 100%, net profit after fees, what comes back and what stays open.
@MainActor
final class PerpsCloseViewModel: ObservableObject {
    @Published var fraction: PerpsCloseFraction

    @Published private(set) var position: HLPosition
    @Published private(set) var market: PerpsMarket
    /// One tier for the fee shown and the order built.
    let vultTier: VultDiscountTier?

    /// False after a failed poll until a fresh tick: Review stays off meanwhile.
    @Published private(set) var pricesAreFresh = true

    init(position: HLPosition, market: PerpsMarket, fraction: PerpsCloseFraction = .all, vultTier: VultDiscountTier?) {
        self.position = position
        self.market = market
        self.fraction = fraction
        self.vultTier = vultTier
    }

    /// Follows the screen's 15 s poll, so the review's IOC price and "back to
    /// trading account" are never from when the sheet opened.
    func setPricesFresh(_ isFresh: Bool) { pricesAreFresh = isFresh }

    func refresh(position: HLPosition, market: PerpsMarket) {
        self.position = position
        self.market = market
        // Never widen the user's pick: an unavailable fraction sizes to 0,
        // which `issue` reports and Review stays disabled until they re-pick.
    }

    var total: Decimal { abs(position.szi.value) }
    var size: Decimal { fraction.size(of: total, szDecimals: market.szDecimals) }
    var remaining: Decimal { total - size }
    var estimate: PerpsFlows.CloseEstimate { PerpsFlows.closeEstimate(position: position, market: market, size: size, tier: vultTier) }
    var netProfit: Decimal { PerpsCloseFlows.netProfit(estimate) }

    func isAvailable(_ fraction: PerpsCloseFraction) -> Bool { fraction.isAvailable(total: total, szDecimals: market.szDecimals) }

    var title: String {
        String(format: "perpsCloseSide".localized, market.coin, position.isLong ? "perpsLong".localized : "perpsShort".localized)
    }

    /// The $10 minimum applies to partial closes only: closing everything is
    /// always allowed, even when the position shrank under $10.
    var issue: String? {
        if !pricesAreFresh { return "perpsPricesUpdating".localized }
        return size < total && size * market.markPrice < PerpsOrderPlanner.minimumNotional ? "perpsMinimumNotional".localized : nil
    }

    func reviewDocument() -> PerpsReviewDocument? {
        guard size > 0, issue == nil else { return nil }
        return try? PerpsFlows.partialClose(position: position, market: market, size: size, tier: vultTier,
                                            nonce: HyperliquidExchangeDryRunClient.shared.nonces.next())
    }
}

// MARK: - Margin

/// Add or remove isolated margin, with liquidation before → after.
@MainActor
final class PerpsMarginViewModel: ObservableObject {
    @Published var isAdding: Bool
    @Published var amountText: String

    @Published private(set) var position: HLPosition
    @Published private(set) var market: PerpsMarket
    @Published private(set) var account: PerpsAccountSnapshot

    init(position: HLPosition, market: PerpsMarket, account: PerpsAccountSnapshot, isAdding: Bool = true, prefill: Decimal? = nil) {
        self.position = position
        self.market = market
        self.account = account
        self.isAdding = isAdding
        amountText = prefill.map { PerpsInput.text($0) } ?? ""
    }

    /// False after a failed poll until a fresh tick: Review stays off meanwhile.
    @Published private(set) var pricesAreFresh = true
    func setPricesFresh(_ isFresh: Bool) { pricesAreFresh = isFresh }

    /// Follows the poll: the limit, liquidation before → after and the review use live numbers.
    func refresh(position: HLPosition, market: PerpsMarket, account: PerpsAccountSnapshot) {
        self.position = position
        self.market = market
        self.account = account
    }

    var amount: Decimal { PerpsInput.decimal(amountText) ?? 0 }
    var change: PerpsMarginChange {
        PerpsMarginFlows.change(position: position, market: market, account: account, delta: isAdding ? amount : -amount)
    }

    /// "$149.81 available" or "Up to $6.20".
    var limitLine: String {
        isAdding
            ? String(format: "perpsAvailableAmount".localized, PerpsFormat.usd(account.availableToTrade))
            : String(format: "perpsUpTo".localized, PerpsFormat.usd(change.maxRemovable))
    }

    /// Fills the limit: what is available to add, or the most that can come out (already floored to cents).
    func applyMax() {
        let limit = isAdding ? account.availableToTrade.rounded(scale: 2, mode: .down) : change.maxRemovable
        amountText = PerpsInput.usdcText(limit)
    }

    var issue: String? {
        guard amount > 0 else { return nil }
        if !pricesAreFresh { return "perpsPricesUpdating".localized }
        return change.issue?.message(maxRemovable: change.maxRemovable)
    }

    var canReview: Bool { amount > 0 && issue == nil }

    func reviewDocument() -> PerpsReviewDocument? {
        guard canReview else { return nil }
        return try? PerpsMarginFlows.review(position: position, market: market, change: change,
                                            nonce: HyperliquidExchangeDryRunClient.shared.nonces.next())
    }
}

// MARK: - Withdraw

/// Amount on a keypad, Max = the server's withdrawable, and what arrives.
@MainActor
final class PerpsWithdrawViewModel: ObservableObject {
    @Published var amountText: String

    let account: PerpsAccountSnapshot
    let vault: PerpsVaultContext

    init(account: PerpsAccountSnapshot, vault: PerpsVaultContext, prefill: Decimal? = nil) {
        self.account = account
        self.vault = vault
        amountText = prefill.map { PerpsInput.text($0) } ?? ""
    }

    var amount: Decimal { PerpsInput.decimal(amountText) ?? 0 }
    var quote: PerpsWithdrawQuote { PerpsWithdrawQuote.make(amount: amount, account: account) }

    func applyMax() { amountText = PerpsInput.usdcText(account.availableToWithdraw.rounded(scale: 2, mode: .down)) }

    /// Keypad input: one dot, at most two decimals, no leading zeros.
    func press(_ key: PerpsKeypadKey) {
        amountText = PerpsKeypadKey.apply(key, to: amountText)
    }

    var issue: String? {
        guard (try? HLAddress.bytes(vault.address)) != nil else { return "perpsNoVaultAddress".localized }
        switch quote.issue {
        case .moreThanWithdrawable: return "perpsMoreThanWithdrawable".localized
        case .belowFees: return "perpsWithdrawBelowFee".localized
        case nil: return nil
        }
    }

    var canReview: Bool { amount > 0 && issue == nil }

    func reviewDocument() -> PerpsReviewDocument? {
        guard canReview else { return nil }
        return try? PerpsFlows.withdraw(amount: amount, account: account, vault: vault, nonce: HyperliquidExchangeDryRunClient.shared.nonces.next())
    }
}

enum PerpsKeypadKey: Hashable, Sendable {
    case digit(Int)
    case dot
    case delete

    /// `maxDecimals`: 2 for USD amounts, more for prices of small coins.
    static func apply(_ key: PerpsKeypadKey, to text: String, maxDecimals: Int = 2) -> String {
        switch key {
        case .delete:
            return String(text.dropLast())
        case .dot:
            if text.contains(".") || maxDecimals == 0 { return text }
            return text.isEmpty ? "0." : text + "."
        case .digit(let digit):
            if let dot = text.firstIndex(of: "."), text[text.index(after: dot)...].count >= maxDecimals { return text }
            if text == "0" { return "\(digit)" }
            guard text.count < 12 else { return text }
            return text + "\(digit)"
        }
    }
}
