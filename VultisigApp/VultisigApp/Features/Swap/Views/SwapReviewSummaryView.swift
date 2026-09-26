//
//  SwapReviewSummaryView.swift
//  VultisigApp
//

import SwiftUI
import VultisigUIResources

/// The swap review's figures, laid out per the design: the pair, the vault,
/// the limit terms, provider, slippage and fees.
struct SwapReviewSummaryView: View {
    let summary: SwapReviewSummary

    var body: some View {
        VStack(spacing: 20) {
            KeysignReviewPairCards(glyph: .chevronRight) {
                side(summary.from)
            } trailing: {
                side(summary.to)
            }

            details
        }
    }

    private var details: some View {
        VStack(spacing: 12) {
            KeysignReviewVaultLine(name: summary.vaultName, address: summary.vaultAddress)

            // An external recipient is a different destination from the user's
            // own address, so it must be seen before signing.
            if let recipient = summary.externalRecipient {
                KeysignReviewRow(label: "recipient".localized, value: recipient, color: Theme.colors.alertWarning)
            }

            KeysignReviewHairline()

            if let terms = summary.limitTerms {
                limitTermsRow(terms)
                KeysignReviewHairline()
            }

            if let provider = summary.provider {
                KeysignReviewRow(label: "provider".localized, labelStyle: .caption) {
                    HStack(spacing: 4) {
                        VultisigImage(provider.logo)
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(provider.name)
                            .keysignReviewText(.caption)
                            .foregroundStyle(Theme.colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            if let slippage = summary.slippage {
                KeysignReviewRow(
                    label: "slippage".localized,
                    value: slippage,
                    color: Theme.colors.textSecondary,
                    labelStyle: .caption,
                    valueStyle: .caption
                )
            }

            fees
        }
    }

    @ViewBuilder
    private var fees: some View {
        if let limitFee = summary.limitNetworkFee {
            KeysignReviewFeeRow(label: "networkFee".localized, amount: limitFee.amount, fiat: limitFee.fiat)
        }
        if let totalFee = summary.totalFee {
            if summary.feeLines.isEmpty {
                KeysignReviewRow(label: "totalFee".localized, value: totalFee, color: Theme.colors.textSecondary)
            } else {
                KeysignReviewDisclosure(title: "totalFee".localized, value: totalFee, isInitiallyExpanded: true) {
                    feeLines
                }
            }
        } else {
            feeLines
        }
    }

    private var feeLines: some View {
        ForEach(summary.feeLines) { line in
            KeysignReviewRow(label: line.label, labelStyle: .caption) {
                if let value = line.value {
                    KeysignReviewRowValue(text: value, color: line.valueColor, style: .caption)
                }
            }
            .modifier(FeeLineIcon(icon: line.icon))
        }
    }

    private func limitTermsRow(_ terms: (targetPrice: String, expiry: String)) -> some View {
        HStack(spacing: 4) {
            Text(terms.targetPrice)
                .keysignReviewText(.caption)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Icon(.calendarClock, color: Theme.colors.textTertiary, size: 16)
            Text(terms.expiry)
                .keysignReviewText(.caption)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }

    private func side(_ side: SwapReviewSummary.Side) -> some View {
        VStack(spacing: 8) {
            AsyncImageView(
                logo: side.logo,
                size: CGSize(width: 36, height: 36),
                ticker: side.ticker,
                tokenChainLogo: side.chainLogo
            )

            VStack(spacing: 0) {
                if let caption = side.caption {
                    Text(caption)
                        .keysignReviewText(.caption)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .lineLimit(1)
                }
                Text("\(side.amount) \(side.ticker)")
                    .keysignReviewText(.bodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(side.fiat)
                    .keysignReviewText(.bodyS)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(1)
                // The floor the signed memo enforces, in full: it wraps rather
                // than truncate. Absent on routes that enforce none, so the
                // review never asserts a guarantee the signature does not back.
                if let footnote = side.footnote {
                    Text(footnote)
                        .keysignReviewText(.caption)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
        }
    }
}

/// A discount line's mark, before its label.
private struct FeeLineIcon: ViewModifier {
    let icon: SwapReviewSummary.FeeLine.Icon?

    func body(content: Content) -> some View {
        if let icon {
            HStack(spacing: 4) {
                iconView(icon)
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func iconView(_ icon: SwapReviewSummary.FeeLine.Icon) -> some View {
        switch icon {
        case .vultTier(let image):
            if let image {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "star.circle.fill")
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.turquoise)
            }
        case .referral:
            Image(systemName: "megaphone.fill")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.primaryAccent4)
        }
    }
}
