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
    /// Max was tapped before any fee was known. A provisional amount fetches a
    /// quote (and with it the real fee); Max then re-applies once against it.
    private(set) var isMaxAwaitingFee = false
    /// Which provisional share is being quoted. Near the whole balance first,
    /// so a provider minimum is cleared; lower only if the provider rejects it.
    @ObservationIgnored private var provisionalStep = 0
    static let provisionalMaxShares: [Decimal] = [
        Decimal(string: "0.95") ?? 0, Decimal(string: "0.75") ?? 0, Decimal(string: "0.5") ?? 0
    ]

    /// Approve legs from the existing allowance check (0, 1, or 2 for a
    /// reset), for the quote on screen. Nil while unknown.
    private(set) var approvalLegs: Int?
    @ObservationIgnored private var approvalTask: Task<Void, Never>?
    /// The spend `approvalLegs` answers for; a refresh of the same spend keeps
    /// the answer instead of re-reading the allowance every quote cycle.
    @ObservationIgnored private var approvalQuery: ERC20ApprovalQuery?
    @ObservationIgnored private let approvalResolver: ERC20ApprovalResolving

    var showRouteSheet = false
    var showFeeDetails = false
    var pickerSide: SwapReworkPickerSide?

    #if DEBUG
    /// Fictional fixture state; when set, the screen renders it and live
    /// quotes are never fetched.
    let demoState: SwapReworkFormState?
    #endif

    init(details: SwapDetailsViewModel? = nil, approvalResolver: ERC20ApprovalResolving = ERC20ApprovalResolver()) {
        self.approvalResolver = approvalResolver
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
        isMaxAwaitingFee = false
        setAmount(updated, vault: vault, immediate: false)
    }

    /// 25 / 50 / 100 (Max). Max on a native coin leaves the network fee and any
    /// balance the chain makes the account keep.
    func selectPercent(_ percentage: Int, vault: Vault) {
        let isNativeMax = percentage == 100 && details.fromCoin.isNativeToken
        // A native Max with no fee known yet would spend the whole balance and
        // leave nothing for gas. Quote a provisional share first to learn it.
        let awaitingFee = isNativeMax && fundingReserve == 0
        if awaitingFee {
            provisionalStep = 0
            applyProvisionalMax(vault: vault)
            return
        }
        guard let text = SwapCryptoLogic.percentageAmountText(
            percentage: percentage,
            fromCoin: details.fromCoin,
            fee: fundingReserve
        ), let amount = SwapAmountInput.parseToken(text) else { return }
        keepsGasReserve = isNativeMax
        let normalized = SwapKeypadInput.normalized(amount, maxFractionDigits: maxFractionDigits)
        // Re-applying Max with an unchanged reserve would re-quote the same
        // amount forever; only a different amount is worth a fetch.
        guard normalized != amountText else {
            isMaxAwaitingFee = false
            return
        }
        setAmount(normalized, vault: vault, immediate: true)
    }

    /// Quotes `provisionalMaxShares[provisionalStep]` of the balance while the
    /// fee is unknown. Gives up (keeping the last provisional amount on screen,
    /// with the provider's error) when every share has been rejected.
    private func applyProvisionalMax(vault: Vault) {
        guard provisionalStep < Self.provisionalMaxShares.count else {
            isMaxAwaitingFee = false
            return
        }
        let share = Self.provisionalMaxShares[provisionalStep]
        let amount = details.fromCoin.balanceDecimal * share
        let normalized = SwapKeypadInput.normalized(amount, maxFractionDigits: maxFractionDigits)
        keepsGasReserve = true
        setAmount(normalized, vault: vault, immediate: true)
        isMaxAwaitingFee = true
    }

    /// What Max leaves behind: the same funding fee `balanceError` validates
    /// against (the signed bond, Solana headroom, any storage reserve).
    private var fundingReserve: BigInt {
        SwapCryptoLogic.fundingNetworkFee(
            displayedFee: details.displayedNetworkFeeWei,
            gasEstimate: details.gas,
            storageReserve: details.storageReserve,
            chain: details.fromCoin.chain
        )
    }

    private func setAmount(_ text: String, vault: Vault, immediate: Bool) {
        isMaxAwaitingFee = false
        resetApproval()
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

    private func resetApproval() {
        approvalTask?.cancel()
        approvalTask = nil
        approvalQuery = nil
        approvalLegs = nil
    }

    /// Reads the allowance the same way the review's hand-off does
    /// (`ERC20ApprovalResolver` on `SwapCryptoLogic.approvalQuery`), read-only,
    /// so the form can count approval legs and their gas before review. The
    /// review still reads it again and signs what it decides.
    func refreshApproval() {
        guard details.isApproveRequired,
              let query = try? SwapCryptoLogic.approvalQuery(
                fromCoin: details.fromCoin, amount: details.amountInCoinDecimal, quote: details.quote
              ) else {
            resetApproval()
            return
        }
        guard query != approvalQuery else { return }
        resetApproval()
        approvalQuery = query
        approvalTask = Task { [weak self, approvalResolver] in
            let requirement = try? await approvalResolver.requirement(for: query)
            // Applied only if it still answers the spend on screen.
            guard !Task.isCancelled, let self, self.approvalQuery == query else { return }
            self.approvalLegs = requirement.map(SwapApprovalGas.legs(for:))
            // An unanswered read stays unknown and is retried next refresh.
            if requirement == nil { self.approvalQuery = nil }
        }
    }

    private func resetQuoteTracking() {
        resetApproval()
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
        // A provisional amount rejected at the quote or at the fee step (a
        // UTXO plan that cannot fit amount plus fee) is handled the same way.
        if isMaxAwaitingFee, let error = details.error {
            // A lower share cannot clear a provider minimum: stop at the
            // largest one and let the "too small" issue speak. Any other
            // rejection steps down to the next share.
            if SwapReworkIssue.issue(for: error, nativeProviderName: "") == .amountTooSmall {
                isMaxAwaitingFee = false
                return
            }
            provisionalStep += 1
            applyProvisionalMax(vault: vault)
            return
        }
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
        refreshApproval()
    }

    /// Max is computed against the fee known when it was tapped; the first
    /// quote often brings the real one. Re-run Max once it would overspend.
    private func reapplyMaxIfFeeGrew(vault: Vault) {
        guard keepsGasReserve, details.balanceError == .insufficientGas else { return }
        selectPercent(100, vault: vault)
    }

    /// Fees landed (a quote fetch, or a route pick's fee refresh). Finishes a
    /// Max that was waiting for its fee, and re-runs Max if a route with more
    /// gas made it overspend.
    func feesSettled(vault: Vault) {
        guard !isDemo, keepsGasReserve else { return }
        if isMaxAwaitingFee {
            guard fundingReserve > 0 else { return }
            selectPercent(100, vault: vault)
            return
        }
        reapplyMaxIfFeeGrew(vault: vault)
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

    /// Rechecked after the async approval read, right before the sheet: the
    /// quote must be the one the user tapped on, still validate (which checks it
    /// matches the current request), and not have expired while the allowance
    /// RPC ran.
    func canStillPresent(quoteAtTap: SwapQuote?) -> Bool {
        guard let quoteAtTap, details.quote == quoteAtTap else { return false }
        return details.validateForm() && !clock.isExpired(at: Date())
    }

    func selectRoute(id: String, vault: Vault) {
        guard let quote = details.allQuotes.first(where: { Self.routeID(for: $0) == id }) else { return }
        details.selectProvider(quote, vault: vault)
        refreshApproval()
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
            balanceError: details.quote == nil ? nil : (details.balanceError ?? approvalGasShortfall),
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
            routeGasNote: fees.map { "\($0.networkLabel) \(SwapReworkFormat.fee($0.breakdown.fixedGasFiat))" },
            feeTicker: details.feeCoin.ticker,
            gasToAddText: gasToAddText,
            selectedRouteID: activeID,
            timer: SwapReworkQuoteTimer(
                state: timerState,
                fraction: Double(max(details.timer, 0)) / 59
            ),
            fees: fees,
            approval: approval,
            issue: issue,
            // Unsigned: the title already says "lost".
            valueLossText: issue == nil && (fees?.breakdown.isValueLossHigh ?? false)
                ? fees?.breakdown.allInChangeText.map { String($0.drop(while: { $0 == "-" })) }
                : nil,
            minimumText: minimumAmountText,
            feeWarning: issue == nil ? feeWarning(fees) : nil,
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
        if isMaxAwaitingFee { return "swapReworkEstimatingGas".localized }
        let reserve = fundingReserve
        guard reserve > 0 else { return nil }
        let feeCoin = details.feeCoin
        let crypto = feeCoin.decimal(for: reserve)
        return "\(SwapReworkFormat.amount(crypto, ticker: feeCoin.ticker)) · \(feeCoin.fiat(decimal: crypto).formatToFiat())"
    }

    /// A SECURE+ mint from an ERC-20 approves the THORChain router, which the
    /// synthetic quote does not name, so the form cannot read that allowance.
    /// It says an approval may be needed and leaves the gas to the review.
    private var isSecuredMintFromToken: Bool {
        details.isSecuredMint && details.fromCoin.chain.chainType == .EVM && !details.fromCoin.isNativeToken
    }

    private var approval: SwapReworkApproval? {
        if isSecuredMintFromToken, details.quote != nil {
            return SwapReworkApproval(
                ticker: details.fromCoin.ticker,
                amountText: SwapReworkFormat.amount(details.fromAmountDecimal),
                spenderName: SwapProviderKind.thorchain.displayName,
                legs: nil
            )
        }
        guard details.isApproveRequired, let quote = details.quote, approvalLegs != 0 else { return nil }
        return SwapReworkApproval(
            ticker: details.fromCoin.ticker,
            amountText: SwapReworkFormat.amount(details.fromAmountDecimal),
            spenderName: quote.displayName ?? quote.kind.displayName,
            legs: approvalLegs
        )
    }

    // MARK: Routes

    var rankedRoutes: [SwapRankedRoute] {
        let toCoin = details.toCoin
        // The source send is the same for every route on this chain, so the
        // active quote's gas stands for all of them (the sheet says so).
        let sharedGas: Decimal? = {
            guard details.quote != nil, details.displayedNetworkFeeWei > 0 else { return nil }
            let feeCoin = details.feeCoin
            return feeCoin.fiat(decimal: feeCoin.decimal(for: details.displayedNetworkFeeWei))
        }()
        let options = details.allQuotes.map { quote in
            let received = quote.expectedNetToAmount(toCoin: toCoin) ?? 0
            // SwapKit folds its fees into the rate: unknown, never "$0.00".
            let providerFees: Decimal? = SwapCryptoLogic.showsDiscountAmounts(quote: quote)
                ? SwapCryptoLogic.affiliateFeeFiat(
                    quote: quote, fromCoin: details.fromCoin, toCoin: toCoin, feeCoin: details.feeCoin
                ) + SwapCryptoLogic.outboundFeeFiat(quote: quote, toCoin: toCoin)
                : nil
            return SwapRouteOption(
                id: Self.routeID(for: quote),
                providerName: quote.displayName ?? quote.kind.displayName,
                providerLogo: quote.kind.providerLogo,
                receivedAmount: received,
                receivedFiat: toCoin.fiat(decimal: received),
                feesFiat: providerFees,
                etaSeconds: quote.totalSwapSeconds,
                gasFiat: sharedGas
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
            feesText: details.isLoadingFees ? "" : (fees.map { SwapReworkFormat.fee(feeTotal($0.breakdown)) } ?? ""),
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
        let networkFiat = feeCoin.fiat(decimal: networkCrypto)
        let legs = details.isApproveRequired ? (approvalLegs ?? 0) : 0
        let breakdown = SwapFeeBreakdown(.init(
            networkFiat: networkFiat,
            networkCrypto: SwapReworkFormat.amount(networkCrypto, ticker: feeCoin.ticker),
            approvalFiat: SwapApprovalGas.fiat(legs: legs, perLegFiat: networkFiat),
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

        return SwapReworkFeeRows(
            breakdown: breakdown,
            networkLabel: String(format: "swapReworkGas".localized, feeCoin.chain.name),
            networkCrypto: breakdown.input.networkCrypto,
            approvalLabel: legs > 0 ? String(format: "swapReworkApprovalGas".localized, legs) : nil,
            protocolLabel: outbound > 0 ? String(format: "swapReworkProtocolFee".localized, providerName) : nil,
            tierName: breakdown.input.tier?.name,
            minimumReceived: minimum.map { SwapReworkFormat.amount($0, ticker: toCoin.ticker) } ?? "",
            slippageText: details.advancedSettings.slippage.displayValue,
            priceImpactText: details.priceImpactString,
            leavesVaultText: leavesVaultText(
                networkCrypto: SwapApprovalGas.totalGas(swapGas: networkCrypto, legs: legs),
                totalFiat: breakdown.totalDebitFiat
            )
        )
    }

    /// The displayed total, or the raw one when every row truncates to $0.00
    /// but something is charged, so the card can say "<$0.01".
    private func feeTotal(_ breakdown: SwapFeeBreakdown) -> Decimal {
        breakdown.displayTotalFiat > 0 ? breakdown.displayTotalFiat : breakdown.totalFiat
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

    /// "0.00088 ETH ($1.72)": the fee coin still missing for swap plus
    /// approval gas, the same sum as the shortfall card. Nil when nothing is.
    private var gasToAddText: String? {
        let feeCoin = details.feeCoin
        let legs = details.isApproveRequired ? (approvalLegs ?? 0) : 0
        let swapGas = feeCoin.decimal(for: details.displayedNetworkFeeWei)
        let needed = SwapApprovalGas.totalGas(swapGas: swapGas, legs: legs) + feeCoin.decimal(for: details.storageReserve)
            + (feeCoin.id == details.fromCoin.id ? details.fromAmountDecimal : 0)
        let short = needed - feeCoin.balanceDecimal
        guard swapGas > 0, short > 0 else { return nil }
        return "\(SwapReworkFormat.amount(short, ticker: feeCoin.ticker)) (\(feeCoin.fiat(decimal: short).formatToFiat()))"
    }

    /// Back from Receive or Buy: read the fee coin's balance again and
    /// re-quote, so the not-enough-gas card clears on its own.
    func refreshAfterForeground(vault: Vault) {
        guard !isDemo, details.fromAmountDecimal > 0 else { return }
        details.updateBalance(for: details.feeCoin)
        details.updateBalance(for: details.fromCoin)
        details.refreshData(vault: vault)
    }

    /// The existing balance gate counts swap gas only. Once the allowance check
    /// says approve legs come first, the fee coin must also cover their gas.
    private var approvalGasShortfall: SwapCryptoLogic.Errors? {
        let legs = details.isApproveRequired ? (approvalLegs ?? 0) : 0
        guard legs > 0 else { return nil }
        let feeCoin = details.feeCoin
        let swapGas = feeCoin.decimal(for: details.displayedNetworkFeeWei)
        let needed = SwapApprovalGas.totalGas(swapGas: swapGas, legs: legs) + feeCoin.decimal(for: details.storageReserve)
        let spendsFeeCoin = feeCoin.id == details.fromCoin.id ? details.fromAmountDecimal : 0
        return feeCoin.balanceDecimal < needed + spendsFeeCoin ? .insufficientGas : nil
    }

    /// "You have 0.00020 ETH. Add 0.00088 ETH ($1.72) to pay for gas." Only
    /// meaningful while `.notEnoughGas` is the issue.
    var gasShortfallText: String? {
        let feeCoin = details.feeCoin
        // Swap gas plus every approve leg the allowance check asked for.
        let legs = details.isApproveRequired ? (approvalLegs ?? 0) : 0
        let swapGas = feeCoin.decimal(for: details.displayedNetworkFeeWei)
        let needed = SwapApprovalGas.totalGas(swapGas: swapGas, legs: legs) + feeCoin.decimal(for: details.storageReserve)
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

    // MARK: Minimum and fee warning

    /// The provider's minimum, rounded up to what the keypad can type.
    var minimumAmount: Decimal? {
        SwapReworkIssue.minimumAmount(for: details.error).map { $0.rounded(scale: maxFractionDigits, mode: .up) }
    }

    /// The exact amount `useMinimum` enters. The display formatter truncates
    /// digits, which would show less than the provider's floor.
    var minimumAmountText: String? {
        minimumAmount.map { "\(SwapKeypadInput.normalized($0, maxFractionDigits: maxFractionDigits)) \(details.fromCoin.ticker)" }
    }

    func useMinimum(vault: Vault) {
        guard let minimum = minimumAmount else { return }
        keepsGasReserve = false
        setAmount(SwapKeypadInput.normalized(minimum, maxFractionDigits: maxFractionDigits), vault: vault, immediate: true)
    }

    /// The fees-over-5% card: shown with the value-loss trigger, built from the
    /// same breakdown so its numbers match the fee rows.
    private func feeWarning(_ fees: SwapReworkFeeRows?) -> SwapReworkFeeWarning? {
        guard let fees, fees.breakdown.isValueLossHigh, let share = fees.breakdown.feeShare else { return nil }
        let breakdown = fees.breakdown
        let scale: Decimal = 10
        let atScale = breakdown.feeShare(atScale: scale).map { scaled in
            String(
                format: "swapReworkFeeAtScale".localized,
                SwapReworkFormat.amount(details.fromAmountDecimal * scale, ticker: details.fromCoin.ticker),
                SwapFeeBreakdown.shareText(scaled)
            )
        }
        return SwapReworkFeeWarning(
            shareText: SwapFeeBreakdown.shareText(share),
            gasPart: NSDecimalNumber(decimal: breakdown.gasPartOfFees).doubleValue,
            gasText: SwapReworkFormat.fee(breakdown.fixedGasFiat),
            vultisigText: SwapReworkFormat.fee(breakdown.variableFeesFiat),
            receiveText: breakdown.input.receiveFiat.formatToFiat(),
            atScaleText: breakdown.fixedGasFiat > 0 ? atScale : nil,
            gasLabel: fees.networkLabel
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
        case .amountTooSmall?:
            // Offered only when the vault can actually send the minimum.
            if let minimum = minimumAmount, minimum <= details.fromCoin.balanceDecimal {
                return .useMinimum(amountText: minimumAmountText ?? "")
            }
            return .enterAmount
        case .tradingHalted?, .other?:
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
        case .confirmNewAmount, .getNewQuote, .chooseAnotherCoin, .useMinimum:
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
            var row = SwapReworkPickerRow(
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
            if side == .pay { row.unswappableReason = gasExceedsValueReason(for: coin, value: fiat) }
            return row
        }
    }

    /// Only judged where the gas is known: coins on the chain of the quote on
    /// screen. An ERC-20 is assumed to need an approval leg on top of the swap.
    private func gasExceedsValueReason(for coin: Coin, value: Decimal) -> String? {
        guard details.quote != nil, coin.chain == details.fromCoin.chain,
              details.displayedNetworkFeeWei > 0 else { return nil }
        let feeCoin = details.feeCoin
        let swapGas = feeCoin.fiat(decimal: feeCoin.decimal(for: details.displayedNetworkFeeWei))
        let needsApproval = coin.chain.chainType == .EVM && !coin.isNativeToken
        let gas = needsApproval ? swapGas * 2 : swapGas
        guard gas > value else { return nil }
        return String(
            format: (needsApproval ? "swapReworkDustAllowSwapGas" : "swapReworkDustSwapGas").localized,
            SwapReworkFormat.fee(gas)
        )
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
