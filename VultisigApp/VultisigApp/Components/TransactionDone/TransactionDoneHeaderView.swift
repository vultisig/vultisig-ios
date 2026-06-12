//
//  TransactionDoneHeaderView.swift
//  VultisigApp
//
//  Status header for the unified done surface — renders the Rive
//  status animation, the dApp request banner (if any), and the
//  default coin display (or a Blockaid-resolved hero override).
//

import SwiftUI

struct TransactionDoneHeaderView: View {
    let coin: Coin?
    let cryptoAmount: String
    let fiatAmount: String
    let hero: HeroContent?
    let status: TransactionStatus
    let dappMetadata: DAppMetadata?
    let verb: TransactionActionVerb

    init(
        coin: Coin?,
        cryptoAmount: String,
        fiatAmount: String,
        hero: HeroContent?,
        status: TransactionStatus,
        dappMetadata: DAppMetadata? = nil,
        verb: TransactionActionVerb = .send
    ) {
        self.coin = coin
        self.cryptoAmount = cryptoAmount
        self.fiatAmount = fiatAmount
        self.hero = hero
        self.status = status
        self.dappMetadata = dappMetadata
        self.verb = verb
    }

    var body: some View {
        VStack(spacing: 36) {
            TransactionStatusHeaderView(status: status, verb: verb)
                .frame(minHeight: 150, maxHeight: 200)

            VStack(spacing: 8) {
                if let metadata = dappMetadata, !metadata.isEmpty {
                    DAppRequestBanner(metadata: metadata)
                }
                if let hero {
                    HeroContentView(content: hero)
                } else {
                    defaultCoinDisplay
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.colors.bgSurface2, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var defaultCoinDisplay: some View {
        if let coin {
            AsyncImageView(
                logo: coin.logo,
                size: CGSize(width: 32, height: 32),
                ticker: coin.ticker,
                tokenChainLogo: coin.tokenChainLogo
            )
        }

        VStack(spacing: 4) {
            Text(cryptoAmount)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(fiatAmount)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }
}
