//
//  SwapReworkViewModel.swift
//  VultisigApp
//
//  The reworked form's view model. It owns no swap logic of its own: quotes,
//  routes, fees, discounts, validation and the transaction handed to the
//  review sheet all come from the existing `SwapDetailsViewModel`, which this
//  wraps. What it adds is the R3 presentation: keypad input, Max that keeps
//  gas, ranked routes, the honest fee breakdown, quote expiry, the price-move
//  confirmation and one resolved issue per state.
//

import BigInt
import Foundation

@MainActor
@Observable
final class SwapReworkViewModel {
    let details: SwapDetailsViewModel

    private(set) var amountText: String = ""
    private(set) var clock = SwapQuoteClock()
    private(set) var now = Date()
    /// The payout the user last saw and accepted (by reviewing or confirming).
    private var acknowledgedReceive: Decimal?
    private(set) var priceMove: SwapPriceMove = .unchanged
    /// Max was tapped on a native coin: the amount keeps the network fee behind.
    private(set) var keepsGasReserve = false

    var showRouteSheet = false
    var showFeeDetails = false
    var pickerSide: SwapReworkPickerSide?

    #if DEBUG
    /// Fictional fixture state; when set, the screen renders it and live
    /// quotes are never fetched.
    let demoState: SwapReworkFormState?
    #endif

    init(details: SwapDetailsViewModel? = nil) {
        // Resolved here, not as a default argument, which would be evaluated
        // outside the main actor the details view model is isolated to.
        self.details = details ?? SwapDetailsViewModel()
        #if DEBUG
        self.demoState = SwapReworkConfig.demoScenario.map(SwapReworkDemo.formState(for:))
        #endif
    }

    var isDemo: Bool {
        #if DEBUG
        demoState != nil
        #else
        false
        #endif
    }

    // MARK: - Input

    private var maxFractionDigits: Int { min(details.fromCoin.decimals, 8) }

    func press(_ key: PerpsKeypadKey, vault: Vault) {
        let updated = SwapKeypadInput.apply(key, to: amountText, maxFractionDigits: maxFractionDigits)
        guard updated != amountText else { return }
        keepsGasReserve = false
        setAmount(updated, vault: vault, immediate: false)
    }

    /// 25 / 50 / 100 (Max). Max on a native coin leaves the network fee and any
    /// balance the chain makes the account keep.
    func selectPercent(_ percentage: Int, vault: Vault) {
        guard let text = SwapCryptoLogic.percentageAmountText(
            percentage: percentage,
            fromCoin: details.fromCoin,
            fee: details.fee + details.storageReserve
        ), let amount = SwapAmountInput.parseToken(text) else { return }
        keepsGasReserve = percentage == 100 && details.fromCoin.isNativeToken
        setAmount(SwapKeypadInput.normalized(amount, maxFractionDigits: maxFractionDigits), vault: vault, immediate: true)
    }

    private func setAmount(_ text: String, vault: Vault, immediate: Bool) {
        amountText = text
        acknowledgedReceive = nil
        priceMove = .unchanged
        clock.reset()
        details.fromAmount = text
        details.updateFromAmount(vault: vault, immediate: immediate)
    }

    func flip(vault: Vault) {
        details.error = nil
        details.switchCoins(vault: vault)
        let fromChain = details.fromChain
        details.fromChain = details.toChain
        details.toChain = fromChain
        amountText = ""
        details.fromAmount = ""
        resetQuoteTracking()
    }

    func coinsChanged() {
        amountText = details.fromAmount
        keepsGasReserve = false
        resetQuoteTracking()
    }

    private func resetQuoteTracking() {
        acknowledgedReceive = nil
        priceMove = .unchanged
        clock.reset()
    }

    // MARK: - Quote lifecycle

    /// One-second tick from the screen. The existing view model owns the
    /// refresh cadence; this only reads the clock.
    func tick(vault: Vault, isReviewPresented: Bool) {
        now = Date()
        guard !isDemo, !isReviewPresented else { return }
        details.updateTimer(vault: vault)
    }

    /// Called when a quote fetch settles. A fresh quote restarts the clock and
    /// is checked against the payout the user last accepted.
    func quoteFetchSettled(vault: Vault) {
        guard details.quote != nil, details.error == nil else { return }
        clock.quoteReceived(at: Date())
        let current = details.toAmountDecimal
        if acknowledgedReceive == nil {
            acknowledgedReceive = current
        }
        priceMove = SwapPriceMove.evaluate(acknowledged: acknowledgedReceive, current: current)
        if case .improved = priceMove {
            acknowledgedReceive = current
        }
        reapplyMaxIfFeeGrew(vault: vault)
    }

    /// Max is computed against the fee known when it was tapped; the first
    /// quote often brings the real one. Re-run Max once it would overspend.
    private func reapplyMaxIfFeeGrew(vault: Vault) {
        guard keepsGasReserve, details.balanceError == .insufficientGas else { return }
        selectPercent(100, vault: vault)
    }

    func confirmNewAmount() {
        acknowledgedReceive = details.toAmountDecimal
        priceMove = .unchanged
    }

    func requestNewQuote(vault: Vault) {
        clock.reset()
        details.restartTimer(vault: vault)
    }

    /// The payout shown when the user opened review counts as accepted.
    func willPresentReview() {
        acknowledgedReceive = details.toAmountDecimal
    }

    func selectRoute(id: String, vault: Vault) {
        guard let quote = details.allQuotes.first(where: { Self.routeID(for: $0) == id }) else { return }
        details.selectProvider(quote, vault: vault)
        acknowledgedReceive = quote.expectedNetToAmount(toCoin: details.toCoin)
        priceMove = .unchanged
        showRouteSheet = false
    }

    static func routeID(for quote: SwapQuote) -> String {
        quote.displayName ?? quote.kind.displayName
    }

    // MARK: - Presentation

    var state: SwapReworkFormState {
        #if DEBUG
        if let demoState { return demoState }
        #endif
        return liveState
    }

    private var liveState: SwapReworkFormState {
        let fromCoin = details.fromCoin
        let toCoin = details.toCoin
        let hasAmount = details.fromAmountDecimal > 0
        let ranked = rankedRoutes
        let activeID = details.quote.map(Self.routeID(for:))
        let issue = SwapReworkIssue.resolve(.init(
            hasAmount: hasAmount,
            balanceError: details.quote == nil ? nil : details.balanceError,
            quoteError: details.error,
            isQuoteExpired: clock.isExpired(at: now) && !details.isLoadingQuotes,
            priceMove: priceMove,
            nativeProviderName: details.quote?.kind.displayName ?? SwapProviderKind.thorchain.displayName
        ))
        let fees = feeRows
        let cta = cta(issue: issue, hasAmount: hasAmount)

        return SwapReworkFormState(
            pay: Self.asset(fromCoin),
            receive: Self.asset(toCoin),
            amountText: amountText,
            payFiatText: fromCoin.fiat(decimal: details.fromAmountDecimal).formatToFiat(),
            balanceText: SwapReworkFormat.amount(fromCoin.balanceDecimal, ticker: fromCoin.ticker),
            gasReserveText: gasReserveText,
            showsMaxChip: true,
            receiveAmountText: receiveAmountText,
            receiveFiatText: receiveFiatText,
            allInText: fees?.breakdown.allInChangeText.map { String(format: "swapReworkAllIn".localized, $0) },
            isReceiveIndicative: details.isShowingIndicativeAmount,
            isQuoteLoading: hasAmount && details.isLoadingQuotes && details.quote == nil,
            highlightsReceive: priceMove.needsConfirmation,
            route: routeSummary(ranked: ranked, activeID: activeID, fees: fees),
            routes: ranked,
            selectedRouteID: activeID,
            timer: SwapReworkQuoteTimer(
                state: timerState,
                fraction: Double(max(details.timer, 0)) / 59
            ),
            fees: fees,
            approval: approval,
            issue: issue,
            cta: cta,
            isCTAEnabled: isCTAEnabled(cta)
        )
    }

    static func asset(_ coin: Coin) -> SwapReworkAsset {
        SwapReworkAsset(
            coinID: coin.id,
            ticker: coin.ticker,
            logo: coin.logo,
            chainLogo: coin.tokenChainLogo,
            chainName: coin.chain.name,
            isNative: coin.isNativeToken
        )
    }

    private var timerState: SwapQuoteClock.State {
        guard details.quote != nil || clock.receivedAt != nil else { return .idle }
        if details.isLoadingQuotes { return .refreshing }
        if clock.isExpired(at: now) { return .expired }
        return .live(secondsLeft: max(details.timer, 1))
    }

    private var receiveAmountText: String {
        if details.quote != nil {
            return SwapReworkFormat.amount(details.toAmountDecimal)
        }
        if let indicative = details.toAmountIndicative, details.fromAmountDecimal > 0 {
            return "~" + SwapReworkFormat.amount(indicative)
        }
        return "0"
    }

    private var receiveFiatText: String {
        let amount = details.quote != nil ? details.toAmountDecimal : (details.toAmountIndicative ?? 0)
        guard amount > 0 else { return "" }
        return "≈ " + details.toCoin.fiat(decimal: amount).formatToFiat()
    }

    private var gasReserveText: String? {
        guard keepsGasReserve else { return nil }
        let reserve = details.fee + details.storageReserve
        guard reserve > 0 else { return nil }
        let feeCoin = details.feeCoin
        let crypto = feeCoin.decimal(for: reserve)
        return "\(SwapReworkFormat.amount(crypto, ticker: feeCoin.ticker)) · \(feeCoin.fiat(decimal: crypto).formatToFiat())"
    }

    private var approval: SwapReworkApproval? {
        guard details.isApproveRequired, let quote = details.quote else { return nil }
        return SwapReworkApproval(
            ticker: details.fromCoin.ticker,
            amountText: SwapReworkFormat.amount(details.fromAmountDecimal),
            spenderName: quote.displayName ?? quote.kind.displayName
        )
    }

    // MARK: Routes

    var rankedRoutes: [SwapRankedRoute] {
        let toCoin = details.toCoin
        let options = details.allQuotes.map { quote in
            let received = quote.expectedNetToAmount(toCoin: toCoin) ?? 0
            let providerFees = SwapCryptoLogic.affiliateFeeFiat(
                quote: quote, fromCoin: details.fromCoin, toCoin: toCoin, feeCoin: details.feeCoin
            ) + SwapCryptoLogic.outboundFeeFiat(quote: quote, toCoin: toCoin)
            return SwapRouteOption(
                id: Self.routeID(for: quote),
                providerName: quote.displayName ?? quote.kind.displayName,
                providerLogo: quote.kind.providerLogo,
                receivedAmount: received,
                receivedFiat: toCoin.fiat(decimal: received),
                feesFiat: providerFees,
                etaSeconds: quote.totalSwapSeconds
            )
        }
        return SwapRouteRanking.rank(options)
    }

    private func routeSummary(ranked: [SwapRankedRoute], activeID: String?, fees: SwapReworkFeeRows?) -> SwapReworkRouteSummary? {
        guard let quote = details.quote else { return nil }
        let tag = ranked.first(where: { $0.id == activeID })?.tags.first
        return SwapReworkRouteSummary(
            providerName: quote.displayName ?? quote.kind.displayName,
            providerLogo: quote.kind.providerLogo,
            tag: tag,
            etaText: quote.totalSwapSeconds.map(SwapReworkFormat.eta(seconds:)) ?? "",
            feesText: details.isLoadingFees ? "" : (fees?.breakdown.totalFiat.formatToFiat() ?? ""),
            isSelectable: ranked.count > 1
        )
    }

    // MARK: Fees

    private var feeRows: SwapReworkFeeRows? {
        guard let quote = details.quote, details.fromAmountDecimal > 0 else { return nil }
        let fromCoin = details.fromCoin
        let toCoin = details.toCoin
        let feeCoin = details.feeCoin
        let networkCrypto = feeCoin.decimal(for: details.displayedNetworkFeeWei)
        let net = SwapCryptoLogic.affiliateFeeFiat(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
        let discounts = SwapCryptoLogic.affiliateDiscountBreakdown(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: details.fromAmountDecimal,
            vultDiscountBps: details.vultDiscountBps,
            referralDiscountBps: details.referralDiscountBps
        )
        let outbound = SwapCryptoLogic.outboundFeeFiat(quote: quote, toCoin: toCoin)
        let breakdown = SwapFeeBreakdown(.init(
            networkFiat: feeCoin.fiat(decimal: networkCrypto),
            networkCrypto: SwapReworkFormat.amount(networkCrypto, ticker: feeCoin.ticker),
            protocolFiat: outbound,
            vultisigNetFiat: net,
            vultisigListFiat: net + discounts.total,
            referralFiat: discounts.referral,
            listBps: SwapCryptoLogic.affiliateListFeeBps,
            tierDiscountBps: details.vultDiscountBps,
            tier: VultDiscountTier.from(bpsDiscount: details.vultDiscountBps),
            vultisigIncludedInRate: !SwapCryptoLogic.showsDiscountAmounts(quote: quote),
            payFiat: fromCoin.fiat(decimal: details.fromAmountDecimal),
            receiveFiat: toCoin.fiat(decimal: details.toAmountDecimal)
        ))
        let providerName = quote.displayName ?? quote.kind.displayName
        let minimum = SwapCryptoLogic.signedMinimumOutput(quote: quote, fromCoin: fromCoin, toCoin: toCoin)
        let networkLabelKey = details.isApproveRequired ? "swapReworkGasAllowSwap" : "swapReworkGas"

        return SwapReworkFeeRows(
            breakdown: breakdown,
            networkLabel: String(format: networkLabelKey.localized, feeCoin.chain.name),
            networkCrypto: breakdown.input.networkCrypto,
            protocolLabel: outbound > 0 ? String(format: "swapReworkProtocolFee".localized, providerName) : nil,
            tierName: breakdown.input.tier?.name,
            minimumReceived: minimum.map { SwapReworkFormat.amount($0, ticker: toCoin.ticker) } ?? "",
            slippageText: details.advancedSettings.slippage.displayValue,
            priceImpactText: details.priceImpactString,
            leavesVaultText: leavesVaultText(networkCrypto: networkCrypto, totalFiat: breakdown.totalDebitFiat)
        )
    }

    private func leavesVaultText(networkCrypto: Decimal, totalFiat: Decimal) -> String {
        let fromCoin = details.fromCoin
        let feeCoin = details.feeCoin
        let amount = SwapReworkFormat.amount(details.fromAmountDecimal)
        let gas = SwapReworkFormat.amount(networkCrypto)
        let crypto = feeCoin.id == fromCoin.id
            ? "\(amount) + \(gas) \(fromCoin.ticker)"
            : "\(amount) \(fromCoin.ticker) + \(gas) \(feeCoin.ticker)"
        return "\(crypto) · \(totalFiat.formatToFiat())"
    }

    /// "You have 0.00020 ETH. Add 0.00088 ETH ($1.72) to pay for gas." Only
    /// meaningful while `.notEnoughGas` is the issue.
    var gasShortfallText: String? {
        let feeCoin = details.feeCoin
        let needed = feeCoin.decimal(for: details.displayedNetworkFeeWei + details.storageReserve)
        guard needed > 0 else { return nil }
        if feeCoin.id == details.fromCoin.id {
            return String(format: "swapReworkGasUseMax".localized, SwapReworkFormat.amount(needed, ticker: feeCoin.ticker))
        }
        let have = feeCoin.balanceDecimal
        let short = max(needed - have, 0)
        return String(
            format: "swapReworkGasShortfall".localized,
            SwapReworkFormat.amount(have, ticker: feeCoin.ticker),
            SwapReworkFormat.amount(short, ticker: feeCoin.ticker),
            feeCoin.fiat(decimal: short).formatToFiat()
        )
    }

    // MARK: CTA

    private func cta(issue: SwapReworkIssue?, hasAmount: Bool) -> SwapReworkCTA {
        guard hasAmount else { return .enterAmount }
        switch issue {
        case .overBalance?:
            return .insufficient(ticker: details.fromCoin.ticker)
        case .notEnoughGas?:
            return .fixGas(ticker: details.feeCoin.ticker)
        case .noRoute?:
            return .chooseAnotherCoin
        case .quoteExpired?:
            return .getNewQuote
        case .priceMoved?:
            return .confirmNewAmount
        case .tradingHalted?, .amountTooSmall?, .other?:
            return .enterAmount
        case nil:
            break
        }
        if details.isLoadingQuotes || details.isLoadingFees || details.isLoadingTransaction { return .loading }
        return .review
    }

    private func isCTAEnabled(_ cta: SwapReworkCTA) -> Bool {
        switch cta {
        case .enterAmount, .loading, .insufficient, .fixGas:
            return false
        case .confirmNewAmount, .getNewQuote, .chooseAnotherCoin:
            return true
        case .review, .reviewWith:
            return details.validateForm()
        }
    }
}

// MARK: - Token picker

extension SwapReworkViewModel {
    static let recents = SwapRecentTokens()

    private static let curatedTokens: [SwapTokenTrust.Token] = TokensStore.TokenSelectionAssets.map {
        SwapTokenTrust.Token(chain: $0.chain.name, ticker: $0.ticker, contract: $0.contractAddress)
    }

    func pickerRows(side: SwapReworkPickerSide) -> [SwapReworkPickerRow] {
        #if DEBUG
        if isDemo { return SwapReworkDemo.pickerRows }
        #endif
        let coins = side == .pay ? details.fromCoins : details.toCoins
        return coins.map { coin in
            let fiat = coin.fiat(decimal: coin.balanceDecimal)
            return SwapReworkPickerRow(
                asset: Self.asset(coin),
                contract: coin.contractAddress,
                balanceText: SwapReworkFormat.amount(coin.balanceDecimal),
                fiatText: fiat > 0 ? fiat.formatToFiat() : "",
                fiatValue: fiat,
                trust: SwapTokenTrust.assess(
                    .init(chain: coin.chain.name, ticker: coin.ticker, contract: coin.isNativeToken ? "" : coin.contractAddress),
                    curated: Self.curatedTokens
                )
            )
        }
    }

    var recentIDs: [String] {
        #if DEBUG
        if isDemo { return SwapReworkDemo.recentIDs }
        #endif
        return Self.recents.ids
    }

    /// Applies a picked token. The screen's coin observers then re-quote
    /// through the existing view model, exactly as the old picker did.
    func selectToken(_ row: SwapReworkPickerRow, side: SwapReworkPickerSide) {
        pickerSide = nil
        guard !isDemo else { return }
        let coins = side == .pay ? details.fromCoins : details.toCoins
        guard let coin = coins.first(where: { $0.id == row.id }) else { return }
        Self.recents.record(coin.id)
        switch side {
        case .pay: details.fromCoin = coin
        case .receive: details.toCoin = coin
        }
    }
}

enum SwapReworkPickerSide: String, Identifiable {
    case pay
    case receive
    var id: String { rawValue }
}
