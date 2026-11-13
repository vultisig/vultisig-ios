//
//  PerpsFlows.swift
//  VultisigApp
//
//  Builds the review document for every flow: open an order,
//  enable trading (approveAgent + approveBuilderFee in one review), add funds
//  (Arbitrum USDC to the bridge through the existing send flow), withdraw
//  (withdraw3), edit stop / take profit, and a partial close. Pure: the same
//  inputs give the same requests and digests, so tests and the review agree.
//

import Foundation
import Security

/// The vault fields a flow needs, read on the main actor.
struct PerpsVaultContext: Sendable {
    let name: String
    let address: String
    /// Native USDC on Arbitrum, nil when the vault has not added it.
    let arbitrumUsdcBalance: Decimal?
    /// The vault's trading account (m/44'/60'/0'/0/1000), master of its own
    /// Hyperliquid account. Deposits credit it; its key signs every trading action.
    var tradingAddress: String?
}

struct PerpsTicketCosts: Equatable, Sendable {
    let hyperliquidFee: Decimal
    /// The Vultisig fee before any VULT discount ("Vultisig 0.1%").
    let builderFee: Decimal
    let fundingPerDay: Decimal
    /// USDC that must come from the vault before the order can open.
    let transfer: Decimal
    var vultTier: VultDiscountTier?
    /// What the VULT tier takes off `builderFee`.
    var vultDiscount: Decimal = 0

    var tradingFees: Decimal { hyperliquidFee + builderFee - vultDiscount }
}

enum PerpsFlows {
    /// A shortfall is covered by a CCTP deposit: the forwarding fee, plus the
    /// one-time activation fee when the trading account is new.
    static func costs(plan: PerpsOrderPlan, availableToTrade: Decimal, isNewAccount: Bool = false,
                      tier: VultDiscountTier? = PerpsVultTier.current) -> PerpsTicketCosts {
        let notional = plan.estimate.notional
        let hyperliquid = notional * PerpsMath.baseTakerFeeRate
        let builder = notional * PerpsConfig.listBuilderFeeRate
        let discount = builder - notional * PerpsConfig.builderFeeRate(tier: tier)
        let needed = plan.estimate.margin + hyperliquid + builder - discount - availableToTrade
        let overhead = HLCctp.forwardingFee + (isNewAccount ? HLCctp.activationFee : 0)
        let transfer = needed > 0 ? (needed + overhead).rounded(scale: 2, mode: .up) : 0
        return PerpsTicketCosts(
            hyperliquidFee: hyperliquid,
            builderFee: builder,
            fundingPerDay: PerpsMath.dailyFundingCost(side: plan.ticket.side, notional: notional, hourlyRate: plan.market.hourlyFunding),
            transfer: transfer,
            vultTier: discount > 0 ? tier : nil,
            vultDiscount: discount
        )
    }

    // MARK: - Order

    static func order(
        plan: PerpsOrderPlan,
        costs: PerpsTicketCosts,
        vault: PerpsVaultContext,
        isNewAccount: Bool = false
    ) -> PerpsReviewDocument {
        let market = plan.market
        let ticket = plan.ticket
        let estimate = plan.estimate
        var rows = [
            PerpsReviewRow(label: "perpsPositionSize".localized, value: PerpsFormat.usd(estimate.notional)),
            PerpsReviewRow(label: "perpsLiquidationPrice".localized, value: estimate.liquidationPrice.map(PerpsFormat.price) ?? "-")
        ]
        if let stop = ticket.stopLoss { rows.append(PerpsReviewRow(label: "perpsStopLoss".localized, value: PerpsFormat.price(stop))) }
        if let take = ticket.takeProfit { rows.append(PerpsReviewRow(label: "perpsTakeProfit".localized, value: PerpsFormat.price(take))) }
        var deposit: HLCctpDeposit?
        var blocking: String?
        var breakdown = [
            PerpsReviewRow(label: "perpsFeeHyperliquid".localized, value: PerpsFormat.usd(costs.hyperliquidFee)),
            PerpsReviewRow(label: "perpsFeeVultisig".localized, value: PerpsFormat.usd(costs.builderFee))
        ]
        if let tier = costs.vultTier {
            // The swap screen's wording: "VULT Gold: 40%".
            breakdown.append(PerpsReviewRow(label: SwapCryptoLogic.vultDiscountLabel(vultDiscountBps: tier.bpsDiscount),
                                            value: PerpsFormat.usd(-costs.vultDiscount, signed: true)))
        }
        var feeTotal = costs.tradingFees
        if costs.transfer > 0 {
            rows.append(PerpsReviewRow(label: "perpsFromYourVault".localized, value: usdc(costs.transfer)))
            deposit = cctpDeposit(amount: costs.transfer, vault: vault)
            let depositFees = HLCctp.forwardingFee + (isNewAccount ? HLCctp.activationFee : 0)
            breakdown.append(PerpsReviewRow(label: "perpsFeeDeposit".localized, value: PerpsFormat.usd(depositFees)))
            feeTotal += depositFees
            blocking = fundingIssue(amount: costs.transfer, vault: vault) ?? (deposit == nil ? "perpsNoTradingAddress".localized : nil)
        }
        return PerpsReviewDocument(
            sheetTitle: "perpsReview".localized,
            amountLabel: "perpsMargin".localized,
            amount: PerpsFormat.amount(ticket.margin),
            caption: sideCaption(ticket.side, coin: market.coin, leverage: ticket.leverage),
            coin: market.coin,
            rows: rows,
            fees: PerpsReviewFees(total: PerpsFormat.usd(feeTotal), breakdown: breakdown,
                                  showsBreakdown: costs.transfer > 0 || costs.vultTier != nil),
            // Lot rounding means the margin used is a little under the amount entered.
            detailRows: [PerpsReviewRow(label: "perpsMargin".localized, value: PerpsFormat.usd(estimate.margin))],
            // What actually leaves "available": margin plus trading fees, rounded once.
            detailTotalRows: costs.transfer > 0 ? [] : [
                PerpsReviewRow(label: "perpsTotalFromAvailable".localized, value: PerpsFormat.usd(estimate.margin + costs.tradingFees))
            ],
            requests: plan.requests,
            deposit: deposit,
            blockingIssue: blocking
        )
    }

    /// Nil when the vault can fund `amount`; otherwise the inline reason.
    static func fundingIssue(amount: Decimal, vault: PerpsVaultContext) -> String? {
        guard let balance = vault.arbitrumUsdcBalance else { return "perpsVaultHasNoArbitrumUsdc".localized }
        guard balance >= amount else { return String(format: "perpsShortfallLine".localized, usdc(amount), usdc(balance)) }
        return nil
    }

    static func sideCaption(_ side: PerpsSide, coin: String, leverage: Int) -> String {
        String(format: side == .long ? "perpsLongCoin".localized : "perpsShortCoin".localized, coin) + " · \(leverage)×"
    }

    /// The stop loss row: just the stop price ("$66,407"), or "Off".
    /// A take profit lives inside the sheet.
    static func stopLossValue(_ stopLoss: Decimal?) -> String {
        stopLoss.map(PerpsFormat.price) ?? "perpsOff".localized
    }

    // MARK: - Enable trading

    /// approveAgent (named, with on-chain expiry) + approveBuilderFee, both
    /// signed by the trading account. One review, two vault signatures.
    static func enableTrading(
        agentAddress: String,
        nonce: UInt64,
        hasDeposited: Bool,
        now: Date = Date()
    ) throws -> PerpsReviewDocument {
        let validUntil = UInt64(now.timeIntervalSince1970 * 1000) + min(PerpsConfig.agentLifetimeMs, HLUserSignedAction.maxAgentLifetimeMs)
        let name = HLUserSignedAction.agentName(PerpsConfig.agentName, validUntilMs: validUntil)
        let approveAgent = try HLUserSignedAction.approveAgent(
            agentAddress: agentAddress, agentName: name, nonce: nonce,
            isMainnet: PerpsConfig.isMainnet, signatureChainId: PerpsConfig.signatureChainId
        )
        let approveBuilder = try HLUserSignedAction.approveBuilderFee(
            builder: PerpsConfig.builderAddress, maxFeeRate: PerpsConfig.builderMaxFeeRate, nonce: nonce + 1,
            isMainnet: PerpsConfig.isMainnet, signatureChainId: PerpsConfig.signatureChainId
        )
        let expires = Date(timeIntervalSince1970: TimeInterval(validUntil) / 1000)
        return PerpsReviewDocument(
            sheetTitle: "perpsApproveAutomatically".localized,
            amount: "",
            caption: "perpsKeyScopeNote".localized,
            coin: nil,
            rows: [
                PerpsReviewRow(label: "perpsKeyExpires".localized, value: expires.formatted(date: .abbreviated, time: .omitted)),
                PerpsReviewRow(label: "perpsMaxFee".localized, value: PerpsConfig.builderMaxFeeRate)
            ],
            requests: [.userSigned(.approveAgent, approveAgent), .userSigned(.approveBuilderFee, approveBuilder)],
            // A fresh account rejects every action until its first deposit
            // (testnet q00). After that, both approvals must come from the
            // trading account's key, which keysign cannot sign at yet.
            blockingIssue: hasDeposited ? "perpsNotInPreview".localized : "perpsDepositFirst".localized,
            debugNote: "Signs at m/44'/60'/0'/0/1000 through KeysignDerivationResolver. Builder address is a placeholder."
        )
    }

    // MARK: - Add funds

    static func addFunds(amount: Decimal, vault: PerpsVaultContext, isNewAccount: Bool = false) -> PerpsReviewDocument {
        let deposit = cctpDeposit(amount: amount, vault: vault)
        let fees = HLCctp.forwardingFee + (isNewAccount ? HLCctp.activationFee : 0)
        var breakdown = [PerpsReviewRow(label: "perpsForwardingFee".localized, value: usdc(HLCctp.forwardingFee))]
        if isNewAccount { breakdown.append(PerpsReviewRow(label: "perpsActivationFee".localized, value: usdc(HLCctp.activationFee))) }
        let credited = amount - fees
        var blocking = fundingIssue(amount: amount, vault: vault)
        if deposit == nil { blocking = blocking ?? "perpsNoTradingAddress".localized }
        if credited <= 0 { blocking = "perpsDepositBelowFees".localized }
        return PerpsReviewDocument(
            sheetTitle: "perpsAddFunds".localized,
            amount: usdc(amount),
            caption: "perpsToTradingAccount".localized,
            coin: nil,
            rows: [PerpsReviewRow(label: "perpsFrom".localized, value: "perpsVaultArbitrum".localized)],
            fees: PerpsReviewFees(total: usdc(fees), breakdown: breakdown),
            trailingRows: [PerpsReviewRow(label: "perpsYouGet".localized, value: usdc(max(0, credited)))],
            requests: [],
            deposit: deposit,
            blockingIssue: blocking,
            debugNote: "CCTP from Arbitrum to the trading account; batchDepositForBurnWithAuth calldata lands with live deposits."
        )
    }

    // MARK: - Withdraw

    /// The amount, where it goes, then "You receive", fees and
    /// timing. The one-time activation fee is explained in one footnote.
    static func withdraw(amount: Decimal, account: PerpsAccountSnapshot, vault: PerpsVaultContext, nonce: UInt64) throws -> PerpsReviewDocument {
        let quote = PerpsWithdrawQuote.make(amount: amount, account: account)
        let request = try HLUserSignedAction.withdraw3(
            destination: vault.address, amount: amount, nonce: nonce,
            isMainnet: PerpsConfig.isMainnet, signatureChainId: PerpsConfig.signatureChainId
        )
        var blocking: String?
        switch quote.issue {
        case .moreThanWithdrawable: blocking = "perpsMoreThanWithdrawable".localized
        case .belowFees: blocking = "perpsWithdrawBelowFee".localized
        case nil: blocking = nil
        }
        return PerpsReviewDocument(
            sheetTitle: "perpsReview".localized,
            amountLabel: "perpsWithdraw".localized,
            amount: PerpsFormat.amount(amount),
            // The vault is a truncating "To" row, never part of the subtitle.
            caption: "perpsUsdcOnArbitrum".localized,
            coin: nil,
            rows: [
                PerpsReviewRow(label: "perpsTo".localized, value: vault.name, style: .vault),
                PerpsReviewRow(label: "perpsYouReceive".localized, value: PerpsFormat.usd(quote.receive)),
                PerpsReviewRow(label: "perpsFees".localized, value: PerpsFormat.usd(quote.totalFees)),
                PerpsReviewRow(label: "perpsArrivesIn".localized, value: "perpsAboutFiveMin".localized)
            ],
            footer: quote.activationFee > 0
                ? String(format: "perpsActivationFootnote".localized, PerpsFormat.amount(quote.activationFee)) : nil,
            requests: [.userSigned(.withdraw3, request)],
            blockingIssue: blocking
        )
    }

    // MARK: - Auto close (stop loss / take profit)

    /// Cancels the existing triggers being replaced or removed, then places
    /// the new ones as `positionTpsl` reduce-only triggers for the whole position.
    static func editExits(
        position: HLPosition,
        market: PerpsMarket,
        existing: [HLFrontendOrder],
        stopLoss: Decimal?,
        takeProfit: Decimal?,
        nonce: UInt64
    ) throws -> PerpsReviewDocument {
        let currentStop = existing.first(where: \.isStopLoss)
        let currentTake = existing.first(where: \.isTakeProfit)
        let size = try HLWireFormat.wire(abs(position.szi.value))
        var cancels: [(asset: Int, oid: Int64)] = []
        var orders: [HLOrderWire] = []
        for (current, target, kind) in [(currentStop, stopLoss, HLOrderType.Kind.stopLoss), (currentTake, takeProfit, .takeProfit)] {
            guard current?.triggerPx?.value != target else { continue }
            if let current { cancels.append((market.assetIndex, current.oid)) }
            if let target {
                guard target > 0 else { throw PerpsOrderPlannerError.invalidTriggerPrice }
                let price = try HLWireFormat.wire(HLWireFormat.price(target, szDecimals: market.szDecimals))
                orders.append(HLOrderWire(asset: market.assetIndex, isBuy: !position.isLong, price: price, size: size, reduceOnly: true,
                                          type: .trigger(isMarket: true, triggerPrice: price, kind: kind)))
            }
        }
        var requests: [HLExchangeRequest] = []
        var next = nonce
        let expiry = HLNonceSource.defaultExpiryMs
        if !cancels.isEmpty {
            requests.append(try .l1(.cancel, action: HLActions.cancel(cancels), nonce: next, isMainnet: PerpsConfig.isMainnet, expiresAfter: next + expiry))
            next += 1
        }
        if !orders.isEmpty {
            requests.append(try .l1(.order, action: HLActions.order(orders, grouping: .positionTpsl, builder: PerpsConfig.builderFee),
                                    nonce: next, isMainnet: PerpsConfig.isMainnet, expiresAfter: next + expiry))
        }
        return PerpsReviewDocument(
            sheetTitle: "perpsStopLoss".localized,
            amount: "",
            caption: sideCaption(position.isLong ? .long : .short, coin: market.coin, leverage: position.leverage.value),
            coin: market.coin,
            rows: [
                PerpsReviewRow(label: "perpsTakeProfit".localized, value: takeProfit.map(PerpsFormat.price) ?? "perpsOff".localized),
                PerpsReviewRow(label: "perpsStopLoss".localized, value: stopLoss.map(PerpsFormat.price) ?? "perpsOff".localized)
            ],
            requests: requests,
            blockingIssue: requests.isEmpty ? "perpsNoChanges".localized : nil
        )
    }

    // MARK: - Partial close

    struct CloseEstimate: Equatable, Sendable {
        let size: Decimal
        let price: Decimal
        let realizedPnl: Decimal
        let fees: Decimal
        let releasedMargin: Decimal
        let remainingLiquidation: Decimal?
        /// The part of `releasedMargin` that is already uPnL (isolated margin
        /// includes it), so it is not counted twice in `returned`.
        var pnlInMargin: Decimal = 0

        /// What lands back in the trading account: the margin put in, the P&L
        /// at the close price, minus the closing fee.
        var returned: Decimal { max(0, releasedMargin - pnlInMargin + realizedPnl - fees) }
    }

    /// P&L at the current mark, so the position screen, the "Your position"
    /// row and the close result use one price. Falls back to the venue's figure.
    static func livePnl(position: HLPosition, markPrice: Decimal?) -> (pnl: Decimal, roe: Decimal) {
        guard let markPrice, markPrice > 0, let entry = position.entryPx?.value, position.leverage.value > 0 else {
            return (position.unrealizedPnl.value, position.returnOnEquity.value)
        }
        let size = abs(position.szi.value)
        let pnl = PerpsMath.unrealizedPnl(side: position.isLong ? .long : .short, entryPrice: entry, markPrice: markPrice, size: size)
        let initialMargin = size * entry / Decimal(position.leverage.value)
        return (pnl, initialMargin > 0 ? pnl / initialMargin : 0)
    }

    static func closeEstimate(position: HLPosition, market: PerpsMarket, size requested: Decimal) -> CloseEstimate {
        let total = abs(position.szi.value)
        let size = HLWireFormat.size(min(requested, total), szDecimals: market.szDecimals)
        let entry = position.entryPx?.value ?? market.markPrice
        let side: PerpsSide = position.isLong ? .long : .short
        let pnl = PerpsMath.unrealizedPnl(side: side, entryPrice: entry, markPrice: market.markPrice, size: size)
        let fees = size * market.markPrice * (PerpsMath.baseTakerFeeRate + PerpsConfig.builderFeeRate)
        let fraction = total > 0 ? size / total : 0
        let released = position.marginUsed.value * fraction
        let remaining = total - size
        // Isolated margin (which already includes uPnL, testnet q07) leaves with
        // the closed part, so the liquidation stays about where it was. Cross
        // keeps the venue's figure.
        let liquidation: Decimal?
        if remaining <= 0 {
            liquidation = nil
        } else if position.leverage.isCross {
            liquidation = position.liquidationPx?.value
        } else {
            liquidation = PerpsMath.liquidationPrice(side: side, entryPrice: entry, size: remaining,
                                                     collateral: position.marginUsed.value - released,
                                                     schedule: market.marginSchedule)
        }
        return CloseEstimate(size: size, price: market.markPrice, realizedPnl: pnl, fees: fees, releasedMargin: released,
                             remainingLiquidation: liquidation,
                             pnlInMargin: position.leverage.isCross ? 0 : position.unrealizedPnl.value * fraction)
    }

    /// Net profit as the hero, then what is closed, the price,
    /// the fee and what comes back. A reduce-only IOC at mid ± 1%.
    static func partialClose(
        position: HLPosition,
        market: PerpsMarket,
        size: Decimal,
        nonce: UInt64
    ) throws -> PerpsReviewDocument {
        let estimate = closeEstimate(position: position, market: market, size: size)
        let order = closeOrder(position: position, market: market, size: estimate.size)
        let request = try HLExchangeRequest.l1(.order, action: HLActions.order([order], builder: PerpsConfig.builderFee),
                                               nonce: nonce, isMainnet: PerpsConfig.isMainnet, expiresAfter: nonce + HLNonceSource.defaultExpiryMs)
        let net = PerpsCloseFlows.netProfit(estimate)
        return PerpsReviewDocument(
            sheetTitle: "perpsReview".localized,
            // Titled by the lot-rounded amount, never the chip's percentage.
            amountLabel: String(format: "perpsCloseAmount".localized, PerpsCloseFlows.sizeText(estimate.size, coin: market.coin)),
            amount: PerpsFormat.usd(net, signed: true),
            amountTone: net >= 0 ? .positive : .negative,
            caption: PerpsCloseFlows.positionCaption(position),
            coin: market.coin,
            rows: [
                PerpsReviewRow(label: "perpsValue".localized, value: PerpsFormat.usd(estimate.size * estimate.price)),
                PerpsReviewRow(label: "perpsEstPrice".localized, value: PerpsFormat.price(estimate.price)),
                PerpsReviewRow(label: "perpsFees".localized, value: PerpsFormat.usd(estimate.fees)),
                PerpsReviewRow(label: "perpsBackToTradingAccount".localized, value: PerpsFormat.usd(estimate.returned))
            ],
            requests: [request],
            blockingIssue: estimate.size * market.markPrice < PerpsOrderPlanner.minimumNotional ? "perpsMinimumNotional".localized : nil
        )
    }

    /// Reduce-only market close: IOC limit at mid ± 1% slippage, opposite side.
    static func closeOrder(position: HLPosition, market: PerpsMarket, size: Decimal) -> HLOrderWire {
        let mid = market.midPrice ?? market.markPrice
        let price = HLWireFormat.marketPrice(mid: mid, isBuy: !position.isLong, slippage: Decimal(string: "0.01") ?? 0, szDecimals: market.szDecimals)
        return HLOrderWire(asset: market.assetIndex, isBuy: !position.isLong, price: HLWireFormat.decimalString(price),
                           size: HLWireFormat.decimalString(size), reduceOnly: true, type: .limit(.ioc))
    }

    // MARK: - Helpers

    /// The CCTP deposit into the trading account, nil without one.
    static func cctpDeposit(amount: Decimal, vault: PerpsVaultContext, now: Date = Date()) -> HLCctpDeposit? {
        guard let trading = vault.tradingAddress, !vault.address.isEmpty else { return nil }
        let validBefore = UInt64(now.timeIntervalSince1970) + 3_600
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard status == errSecSuccess else { return nil }
        return try? HLCctpDeposit.make(from: vault.address, tradingAddress: trading, amount: amount, validBefore: validBefore, authNonce: nonce)
    }

    static func usdc(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSDecimalNumber(decimal: value)) ?? "-") + " USDC"
    }

    static func fundingText(_ perDay: Decimal) -> String {
        let text = PerpsFormat.usd(perDay < 0 ? -perDay : perDay)
        return String(format: perDay >= 0 ? "perpsFundingPaysPerDay".localized : "perpsFundingEarnsPerDay".localized, text)
    }
}
