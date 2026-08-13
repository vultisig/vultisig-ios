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

    var body: some View {
        VStack(spacing: 12) {
            switch content {
            case .title(let text, let caption):
                titleOnly(text: text, caption: caption)
            case .send(let title, let coin):
                send(title: title, coin: coin)
            case .swap(let title, let from, let to):
                swap(title: title, from: from, to: to)
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
        // ⚠️ Stays CENTRED, unlike `send` / `swap`. This is a standalone caption
        // block — a function name over a sub-line — with no amount row beneath it
        // to agree with, so leading would only make it hug an edge for no reason.
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// ⚠️ Leading, to agree with the `coinRow` under it.
    ///
    /// The title used to be centred over a left-aligned amount, so the two read
    /// as separate blocks rather than one sentence — and the generic header this
    /// replaces (`SendCryptoVerifySummaryView.heroHeader`) has always been
    /// left-aligned, so a transaction that grew a hero visibly shifted its own
    /// title sideways.
    @ViewBuilder
    private func send(title: String?, coin: HeroCoinAmount) -> some View {
        if let title {
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        coinRow(coin, iconSize: 36)
    }

    /// Leading for the same reason as `send` — the two `coinRow`s below it are.
    @ViewBuilder
    private func swap(title: String?, from: HeroCoinAmount, to: HeroCoinAmount) -> some View {
        if let title {
            Text(title)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
