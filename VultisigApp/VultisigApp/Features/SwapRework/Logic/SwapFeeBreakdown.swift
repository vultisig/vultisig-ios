//
//  SwapFeeBreakdown.swift
//  VultisigApp
//
//  The honest fee card: every fee the swap costs, in fiat, adding up to the
//  total on screen, with the Vultisig fee at its list rate struck through next
//  to what the vault's VULT tier actually charges.
//
//  Inputs are the fiat values the existing swap logic already derives
//  (`SwapCryptoLogic.affiliateFeeFiat`, `outboundFeeFiat`, the signed network
//  bond), so the rework shows the same money the review and done screens do.
//

import Foundation

struct SwapFeeBreakdown: Equatable {

    struct Input: Equatable {
        /// Source-chain gas, the signed bond (approval included when one is needed).
        let networkFiat: Decimal
        /// The same gas in the fee coin, e.g. "0.00043 ETH".
        let networkCrypto: String
        /// Gas for the ERC-20 approval legs ahead of the swap, once the
        /// allowance check says how many there are. Zero when none are needed
        /// or not known yet.
        var approvalFiat: Decimal = 0
        /// Protocol payout fee (THORChain/Maya outbound). Zero for aggregators,
        /// whose swap cost is already inside the quoted rate.
        let protocolFiat: Decimal
        /// Vultisig fee the quote charges, after every discount.
        let vultisigNetFiat: Decimal
        /// Vultisig fee at the list rate, before any discount.
        let vultisigListFiat: Decimal
        /// Part of the discount that comes from a referral, not the tier.
        var referralFiat: Decimal = 0
        /// List rate in basis points (50).
        let listBps: Int
        /// Discount the vault's VULT tier takes off the list rate, in bps.
        /// `Int.max` is the Ultimate waiver.
        let tierDiscountBps: Int
        let tier: VultDiscountTier?
        /// SwapKit bakes the affiliate into its rate: no separable amount.
        let vultisigIncludedInRate: Bool
        /// What the user pays, in fiat.
        let payFiat: Decimal
        /// What the vault receives, in fiat.
        let receiveFiat: Decimal
    }

    let input: Input

    init(_ input: Input) {
        self.input = input
    }

    /// The rate the tier pays, in bps: 50 list, 30 for Gold, 0 for Ultimate.
    var effectiveBps: Int {
        max(0, input.listBps - min(max(input.tierDiscountBps, 0), input.listBps))
    }

    /// "0.30%"
    var effectiveRateText: String { Self.percent(bps: effectiveBps) }

    /// The quote charged no Vultisig fee although the tier rate is above
    /// zero (a provider minimum on a small swap). The label then says 0.00%
    /// rather than a rate next to $0.00.
    var isWaivedByQuote: Bool {
        !input.vultisigIncludedInRate && input.vultisigNetFiat == 0 && effectiveBps > 0
    }

    /// The rate the quote actually charges, in bps: the list rate scaled by
    /// what the quote charges against the list fee, so a referral discount on
    /// top of the tier shows too (Gold + 5 bps referral = 25). Falls back to
    /// the tier rate when there is no list amount to scale from.
    var chargedBps: Int {
        guard !input.vultisigIncludedInRate, input.vultisigListFiat > 0 else {
            return isWaivedByQuote ? 0 : effectiveBps
        }
        let scaled = (input.vultisigNetFiat / input.vultisigListFiat * Decimal(input.listBps)).rounded(scale: 0)
        return min(max(NSDecimalNumber(decimal: scaled).intValue, 0), input.listBps)
    }

    /// The rate the row states: what the quote actually charges.
    var chargedRateText: String { Self.percent(bps: chargedBps) }
    var listRateText: String { Self.percent(bps: input.listBps) }

    /// Whole percent of the list fee the tier removes (Gold: 40).
    var percentOff: Int {
        guard input.listBps > 0 else { return 0 }
        return min(max(input.tierDiscountBps, 0), input.listBps) * 100 / input.listBps
    }

    /// What the tier saved on this swap, in fiat. Never negative.
    var tierSavingsFiat: Decimal {
        guard !input.vultisigIncludedInRate else { return 0 }
        return max(input.vultisigListFiat - input.vultisigNetFiat - input.referralFiat, 0)
    }

    var showsStrikethrough: Bool {
        !input.vultisigIncludedInRate && input.vultisigListFiat > input.vultisigNetFiat
    }

    /// Network + protocol + Vultisig. Price impact and slippage are already in
    /// the quoted amount and are never added again.
    var totalFiat: Decimal {
        input.networkFiat + input.approvalFiat + input.protocolFiat
            + (input.vultisigIncludedInRate ? 0 : input.vultisigNetFiat)
    }

    /// The total as the rows display it: each row truncated to cents (as
    /// `formatToFiat` shows it) before adding, so the rows on screen always
    /// add up to the total on screen.
    var displayTotalFiat: Decimal {
        let rows = [
            input.networkFiat, input.approvalFiat, input.protocolFiat,
            input.vultisigIncludedInRate ? 0 : input.vultisigNetFiat
        ]
        return rows.reduce(0) { $0 + $1.truncated(toPlaces: 2) }
    }

    /// Everything that leaves the vault, in fiat: the amount plus gas.
    var totalDebitFiat: Decimal { input.payFiat + input.networkFiat + input.approvalFiat }

    /// Received against everything that left, gas included. Negative is a
    /// loss. Nil until both sides are known.
    var allInChange: Decimal? {
        guard totalDebitFiat > 0, input.receiveFiat > 0 else { return nil }
        return (input.receiveFiat - totalDebitFiat) / totalDebitFiat
    }

    /// "-0.68%", two decimals, always signed.
    var allInChangeText: String? {
        guard let change = allInChange else { return nil }
        var percent = (change * 100).rounded(scale: 2)
        // Something still arrives: never round that to a total loss.
        if percent <= -100, change > -1 { percent = Decimal(string: "-99.99") ?? percent }
        let formatted = Self.decimalFormatter.string(from: NSDecimalNumber(decimal: abs(percent))) ?? "0.00"
        return (percent < 0 ? "-" : "+") + formatted + "%"
    }

    /// Fees and price impact take more than this share of the value: the
    /// form warns (without blocking), as R3's high price impact state does.
    static let valueLossWarningThreshold: Decimal = Decimal(string: "-0.05") ?? 0

    var isValueLossHigh: Bool {
        guard let change = allInChange else { return false }
        return change < Self.valueLossWarningThreshold
    }

    static func percent(bps: Int) -> String {
        let value = Decimal(bps) / 100
        return (decimalFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00") + "%"
    }

    /// Always "." for decimals, whatever the locale, to match the keypad.
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter
    }()
}
