//
//  SwapReviewSummary.swift
//  VultisigApp
//
//  What the swap review shows, as text, read off a `SwapTransaction` once so
//  the view only lays it out.
//

import SwiftUI

struct SwapReviewSummary {
    struct Side {
        let logo: String
        let ticker: String
        /// The chain's logo, badged on the coin's unless the coin is the
        /// chain's own, so ETH on Base never reads as ETH on Ethereum.
        let chainLogo: String?
        let amount: String
        let fiat: String
        let caption: String?
        let footnote: String?
    }

    struct FeeLine: Identifiable {
        enum Icon {
            case vultTier(ImageResource?)
            case referral
        }

        let label: String
        let value: String?
        var valueColor: Color = Theme.colors.textPrimary
        var icon: Icon?

        var id: String { label }
    }

    let from: Side
    let to: Side
    let vaultName: String
    let vaultAddress: String
    /// "Target Price: 1 A = x B" and the expiry, for a limit order.
    let limitTerms: (targetPrice: String, expiry: String)?
    let provider: (name: String, logo: String)?
    /// Absent for a limit order, which executes at its target price.
    let slippage: String?
    let totalFee: String?
    let feeLines: [FeeLine]
    /// A limit order's only fee: the source-chain network fee.
    let limitNetworkFee: (amount: String, fiat: String)?
    let externalRecipient: String?
}

extension SwapReviewSummary {
    init(transaction: SwapTransaction, vault: Vault) {
        from = Side(
            logo: transaction.fromCoin.logo,
            ticker: transaction.fromCoin.ticker,
            chainLogo: transaction.fromCoin.chainBadgeLogo,
            amount: transaction.fromAmount.formatForDisplay(),
            fiat: transaction.fromFiatAmount.formatToFiat(includeCurrencySymbol: true),
            caption: nil,
            footnote: nil
        )
        // A market swap's amount is the quote's expected output, with the floor
        // the memo enforces in its own line. A placed limit order's amount IS
        // the signed floor, so "min. payout" is exactly right there.
        to = Side(
            logo: transaction.toCoin.logo,
            ticker: transaction.toCoin.ticker,
            chainLogo: transaction.toCoin.chainBadgeLogo,
            amount: transaction.toAmountDecimal.formatForDisplay(),
            fiat: Self.destinationFiat(transaction),
            caption: (transaction.isLimit ? "minPayout" : "expectedPayout").localized,
            footnote: transaction.minPayoutCaption
        )
        vaultName = vault.name
        vaultAddress = transaction.fromCoin.address

        // LIM = sourceAmount(fromCoin) × targetPrice, so targetPrice is
        // toCoin-per-1-fromCoin. The row MUST read "1 <fromCoin> = <price>
        // <toCoin>": passing toCoin first would confirm the reciprocal pair
        // against the signed memo.
        limitTerms = transaction.limitContext.map { limit in
            (
                targetPrice: String(
                    format: "limitSwap.verify.targetPrice".localized,
                    transaction.fromCoin.ticker,
                    limit.targetPrice.formatForDisplay(),
                    transaction.toCoin.ticker
                ),
                expiry: formatLimitExpiry(blocks: limit.expiryBlocks)
            )
        }

        provider = transaction.providerDisplayName.map { (name: $0, logo: $0) }
        slippage = transaction.isLimit ? nil : transaction.advancedSettings.slippage.displayValue

        totalFee = transaction.showTotalFees ? transaction.totalFeeString : nil
        var lines: [FeeLine] = []
        if transaction.showGas {
            lines.append(FeeLine(
                label: "networkFee".localized,
                value: "\(transaction.swapGasString) (\(transaction.approveFeeString))"
            ))
        }
        // Gross list-rate Vultisig fee; applied savings are itemised below and
        // the total stays the net charge.
        if transaction.showAffiliateFeeRow {
            lines.append(FeeLine(label: transaction.swapFeeLabel, value: transaction.baseAffiliateFee))
        }
        if transaction.showProtocolFeeRow {
            lines.append(FeeLine(label: "swap.protocol_fee".localized, value: transaction.outboundFeeString))
        }
        if !transaction.vultDiscount.isEmpty {
            lines.append(FeeLine(
                label: transaction.vultDiscountLabel,
                value: nil,
                icon: .vultTier(VultDiscountTier.from(bpsDiscount: transaction.vultDiscountBps)?.icon)
            ))
        }
        if !transaction.referralDiscount.isEmpty {
            lines.append(FeeLine(label: transaction.referralDiscountLabel, value: nil, icon: .referral))
        }
        if !transaction.priceImpactString.isEmpty {
            lines.append(FeeLine(
                label: "swap.price_impact".localized,
                value: transaction.priceImpactString,
                valueColor: transaction.priceImpactColor
            ))
        }
        feeLines = lines

        // A resting `=<` order has no market quote, so none of the fee lines
        // above apply; its source-chain network fee is the one it has.
        if transaction.isLimit, !transaction.limitNetworkFeeString.isEmpty {
            limitNetworkFee = (amount: transaction.limitNetworkFeeString, fiat: transaction.limitNetworkFeeFiat)
        } else {
            limitNetworkFee = nil
        }

        externalRecipient = transaction.hasExternalRecipient ? transaction.recipientAddress : nil
    }

    /// Prices `toAmountDecimal` directly rather than through
    /// `transaction.toFiatAmount`, which is `formatForDisplay()`'d for its own
    /// callers and abbreviates at 1M (`"1.25M"`) — a string `formatToFiat`
    /// cannot parse back into a fiat value.
    private static func destinationFiat(_ transaction: SwapTransaction) -> String {
        transaction.toCoin.fiat(decimal: transaction.toAmountDecimal).formatToFiat(includeCurrencySymbol: true)
    }
}
