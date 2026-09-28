//
//  FunctionTransactionReviewSummaryView.swift
//  VultisigApp
//

import SwiftUI

/// A DeFi operation's review, laid out per the design: the amount on its own
/// card, the vault, then rows with a hairline between each.
struct FunctionTransactionReviewSummaryView<Disclosures: View>: View {
    let summary: FunctionTransactionReviewSummary
    let disclosures: () -> Disclosures

    @State private var rateRevision = 0

    init(
        summary: FunctionTransactionReviewSummary,
        @ViewBuilder disclosures: @escaping () -> Disclosures
    ) {
        self.summary = summary
        self.disclosures = disclosures
    }

    var body: some View {
        VStack(spacing: 20) {
            heroCard

            VStack(spacing: 12) {
                KeysignReviewVaultLine(name: summary.vaultName, address: summary.vaultAddress)

                ForEach(summary.rows) { row in
                    KeysignReviewHairline()
                    KeysignReviewRow(
                        label: row.label,
                        value: row.value,
                        image: row.image,
                        color: row.color,
                        isMultiline: row.isMultiline
                    )
                }

                KeysignReviewHairline()
                KeysignReviewFeeRow(label: "estNetworkFee".localized, amount: summary.fee.amount, fiat: summary.fee.fiat)

                ForEach(summary.additionalRows) { row in
                    KeysignReviewHairline()
                    KeysignReviewRow(label: row.label, value: row.value, color: row.color)
                }
            }

            disclosures()
        }
        // Figures priced before the rates arrived are repriced when they do.
        .onReceive(RateProvider.shared.ratesDidChange) { _ in
            rateRevision &+= 1
        }
    }

    @ViewBuilder
    private var heroCard: some View {
        let hero = heroContent
        switch hero {
        case .send(let title, let coin), .receive(let title, let coin):
            amountCard(title: title, coin: coin)
        case .swap(_, let from, let to):
            KeysignReviewPairCards(glyph: .chevronRight) {
                KeysignReviewCoinAmount(caption: nil, logo: from.logo, ticker: from.ticker, amountText: from.amountText, fiat: from.fiat)
            } trailing: {
                KeysignReviewCoinAmount(caption: nil, logo: to.logo, ticker: to.ticker, amountText: to.amountText, fiat: to.fiat)
            }
        case .title(let text, let caption):
            KeysignReviewCard {
                VStack(spacing: 8) {
                    Text(text)
                        .keysignReviewText(.title3)
                        .foregroundStyle(Theme.colors.textPrimary)
                    if let caption {
                        Text(caption)
                            .keysignReviewText(.caption)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
        case .projected(let title, let estimate, let scope):
            KeysignReviewCard {
                VStack(spacing: 8) {
                    if let estimate {
                        KeysignReviewCoinAmount(
                            caption: title,
                            logo: estimate.logo,
                            ticker: estimate.ticker,
                            amountText: "≈ \(estimate.amountText)",
                            fiat: estimate.fiat
                        )
                    } else {
                        Text(title)
                            .keysignReviewText(.title3)
                            .foregroundStyle(Theme.colors.textPrimary)
                    }

                    Text(scope)
                        .keysignReviewText(.caption)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func amountCard(title: String?, coin: HeroCoinAmount) -> some View {
        KeysignReviewCard {
            KeysignReviewCoinAmount(
                caption: title,
                logo: coin.logo,
                ticker: coin.ticker,
                amountText: coin.amountText,
                fiat: coin.fiat
            )
        }
    }

    private var heroContent: HeroContent {
        _ = rateRevision
        return summary.hero.refreshedFiat()
    }
}

private extension HeroCoinAmount {
    var amountText: String {
        ticker.isEmpty ? amount : "\(amount) \(ticker)"
    }
}
