//
//  HeroContentView.swift
//  VultisigApp
//

import SwiftUI

/// Renders a `HeroContent` value. Does not provide its own padding/background —
/// the parent wraps this in whatever container it needs (e.g. the done-screen
/// card, the verify-screen summary block).
struct HeroContentView: View {
    let content: HeroContent
    private let verbAlignment: Alignment

    init(content: HeroContent, verbAlignment: Alignment = .center) {
        self.content = content
        self.verbAlignment = verbAlignment
    }

    var body: some View {
        VStack(spacing: 12) {
            switch content {
            case .title(let text, let caption):
                titleOnly(text: text, caption: caption)
            case .send(let title, let coin):
                amountRow(title: title, coin: coin, label: nil)
            case .receive(let title, let coin):
                amountRow(title: title, coin: coin, label: "receive".localized)
            case .swap(let title, let from, let to):
                swap(title: title, from: from, to: to)
            case .projected(let title, let estimate, let scope):
                projected(title: title, estimate: estimate, scope: scope)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func titleOnly(text: String, caption: String?) -> some View {
        VStack(spacing: 4) {
            Text(text)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)

            if let caption {
                Text(caption)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: verbAlignment)
    }

    /// Scope is always visible; an optional estimate is explicitly approximate.
    @ViewBuilder
    private func projected(title: String, estimate: HeroCoinAmount?, scope: String) -> some View {
        Text(title)
            .font(Theme.fonts.bodyMMedium)
            .foregroundStyle(Theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let estimate {
            HStack(spacing: 4) {
                Text(verbatim: "≈")
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textTertiary)
                coinRow(estimate, iconSize: 36)
            }
        }

        Text(scope)
            .font(Theme.fonts.caption10)
            .foregroundStyle(Theme.colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The single-row heroes: send and receive render the same row and differ
    /// only by `label`. Every hero shape but the receive states money leaving,
    /// so the inflow carries an explicit label — without it the row is
    /// indistinguishable from a send.
    @ViewBuilder
    private func amountRow(title: String?, coin: HeroCoinAmount, label: String?) -> some View {
        if let title {
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: verbAlignment)
        }
        if let label {
            VStack(spacing: 8) {
                Text(label)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                coinRow(coin, iconSize: 36)
            }
        } else {
            coinRow(coin, iconSize: 36)
        }
    }

    @ViewBuilder
    private func swap(title: String?, from: HeroCoinAmount, to: HeroCoinAmount) -> some View {
        if let title {
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        VStack(spacing: 12) {
            coinRow(from, iconSize: 28)
            arrowDivider
            coinRow(to, iconSize: 28)
        }
    }

    @ViewBuilder
    private func coinRow(_ coin: HeroCoinAmount, iconSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            if !coin.logo.isEmpty {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: iconSize, height: iconSize),
                    ticker: coin.ticker,
                    tokenChainLogo: nil
                )
            }
            CoinAmountFiatLabel(amount: coin.amount, ticker: coin.ticker, fiat: coin.fiat)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var arrowDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Theme.colors.border)
                .frame(height: 1)
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.colors.textTertiary)
            Text("to".localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
            Rectangle()
                .fill(Theme.colors.border)
                .frame(height: 1)
        }
    }
}

/// Verify-only wrapper that redraws cached hero figures when rates arrive.
/// Done continues to render `HeroContentView` directly and keeps its existing
/// presentation and timing.
struct VerifyHeroContentView: View {
    let content: HeroContent

    @State private var rateRevision = 0

    var body: some View {
        _ = rateRevision
        return HeroContentView(
            content: content.refreshedFiat(),
            verbAlignment: .leading
        )
            .onReceive(RateProvider.shared.ratesDidChange) { _ in
                rateRevision &+= 1
            }
    }
}
