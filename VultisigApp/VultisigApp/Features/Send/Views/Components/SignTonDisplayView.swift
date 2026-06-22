//
//  SignTonDisplayView.swift
//  VultisigApp
//
//  Renders TonConnect multi-message keysign payloads as labeled per-message
//  panels. Mirrors `SignTonDisplay.tsx` from the Vultisig Windows codebase:
//  decodes each BOC body locally, resolves jetton wallet addresses to coin
//  metadata, and falls back to a TonAPI emulation for swaps the local decoder
//  doesn't recognise.
//

import SwiftUI

struct SignTonDisplayView: View {
    let signTon: SignTon
    let keysignPayload: KeysignPayload?
    let vault: Vault
    let fromAddress: String

    @StateObject private var viewModel = TonSignDisplayViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let swap = viewModel.simulationSwap {
                VStack(alignment: .leading, spacing: 12) {
                    swapCard(
                        from: SwapAmount(
                            amount: swap.fromAmount,
                            decimals: swap.fromDecimals,
                            ticker: swap.fromTicker,
                            logo: swap.fromLogo
                        ),
                        to: SwapAmount(
                            amount: swap.toAmount,
                            decimals: swap.toDecimals,
                            ticker: swap.toTicker,
                            logo: swap.toLogo
                        )
                    )
                    // Surface every BOC body — multi-message swap requests
                    // (e.g. STON.fi gas + swap) carry distinct payloads per
                    // message and we lose audit visibility if we keep only
                    // the first.
                    ForEach(Array(signTon.tonMessages.enumerated()), id: \.offset) { _, message in
                        if let payload = message.payload, !payload.isEmpty {
                            rawPayloadPanel(payload: payload)
                        }
                    }
                }
            } else if viewModel.isSimulating {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.visibleEntries(fromAddress: fromAddress)) { entry in
                    entryView(entry: entry)
                }
            }
        }
        .task(id: cacheKey) {
            await viewModel.load(
                signTon: signTon,
                keysignPayload: keysignPayload,
                vault: vault,
                fromAddress: fromAddress
            )
        }
    }

    // Combining inputs into a single key keeps the SwiftUI `task(id:)` modifier
    // honest — it cancels the prior load when any input that materially changes
    // the displayed BOC switches.
    private var cacheKey: String {
        let messagesKey = signTon.tonMessages.map { msg in
            "\(msg.to)|\(msg.amount)|\(msg.payload ?? "")"
        }.joined(separator: "#")
        return "\(vault.pubKeyECDSA)|\(fromAddress)|\(messagesKey)"
    }

    // MARK: - Per-entry content

    @ViewBuilder
    private func entryView(entry: TonSignDisplayViewModel.Entry) -> some View {
        if let swap = entry.swap {
            VStack(alignment: .leading, spacing: 12) {
                swapCard(
                    from: localSwapFromAmount(entry: entry, swap: swap),
                    to: localSwapToAmount(entry: entry, swap: swap)
                )
                if let payload = entry.message.payload, !payload.isEmpty {
                    rawPayloadPanel(payload: payload)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(operationTitle(for: entry).localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)

                messageRows(entry: entry)

                if let payload = entry.message.payload, !payload.isEmpty {
                    DisclosureSection(title: "transactionDetails") {
                        rawPayloadDisclosureContent(payload: payload)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Operation titles

    private func operationTitle(for entry: TonSignDisplayViewModel.Entry) -> String {
        switch entry.intent {
        case .jettonTransfer:
            return "jettonTransfer"
        case .nftTransfer:
            return "nftTransfer"
        case .excesses:
            return "excessGasRefund"
        case .swap:
            return "swap"
        case nil:
            return "transfer"
        }
    }

    // MARK: - Message rows

    @ViewBuilder
    private func messageRows(entry: TonSignDisplayViewModel.Entry) -> some View {
        switch entry.intent {
        case .jettonTransfer(let transfer):
            VStack(alignment: .leading, spacing: 8) {
                row(title: "to", value: transfer.destination)
                row(title: "amount", value: jettonAmountString(rawAmount: transfer.amount, coin: entry.jettonCoin))
                row(title: "forwardTonAmount", value: tonAmountString(rawAmount: transfer.forwardTonAmount))
            }
        case .nftTransfer(let nft):
            VStack(alignment: .leading, spacing: 8) {
                row(title: "to", value: nft.newOwner)
                row(title: "forwardTonAmount", value: tonAmountString(rawAmount: nft.forwardAmount))
            }
        case .excesses, .swap, nil:
            VStack(alignment: .leading, spacing: 8) {
                row(title: "to", value: entry.message.to)
                row(title: "amount", value: tonAmountString(rawAmount: entry.message.amount))
            }
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title.localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .frame(minWidth: 52, alignment: .leading)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .font(Theme.fonts.bodySMedium)
    }

    // MARK: - Swap card

    private struct SwapAmount {
        let amount: String
        let decimals: Int
        let ticker: String
        let logo: String
    }

    private func localSwapFromAmount(
        entry: TonSignDisplayViewModel.Entry,
        swap: TonMessageBodyIntent.Swap
    ) -> SwapAmount {
        switch swap.offerAsset {
        case .ton:
            return SwapAmount(amount: swap.offerAmount, decimals: 9, ticker: "GRAM", logo: "gram")
        case .jetton:
            let coin = entry.jettonCoin
            return SwapAmount(
                amount: swap.offerAmount,
                decimals: coin?.decimals ?? 9,
                ticker: coin?.ticker ?? "",
                logo: coin?.logo ?? ""
            )
        }
    }

    private func localSwapToAmount(
        entry: TonSignDisplayViewModel.Entry,
        swap: TonMessageBodyIntent.Swap
    ) -> SwapAmount {
        let coin = entry.swapOutputCoin
        return SwapAmount(
            amount: swap.minOut ?? "0",
            decimals: coin?.decimals ?? 9,
            ticker: coin?.ticker ?? "",
            logo: coin?.logo ?? ""
        )
    }

    private func swapCard(from: SwapAmount, to: SwapAmount) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("youreSwapping".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                swapAmountRow(from)
                swapDividerRow
                swapAmountRow(to)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private func swapAmountRow(_ amount: SwapAmount) -> some View {
        HStack(spacing: 8) {
            coinIcon(logo: amount.logo, ticker: amount.ticker)
            Group {
                Text(formatBaseAmount(rawAmount: amount.amount, decimals: amount.decimals))
                    .foregroundStyle(Theme.colors.textPrimary)
                + Text(" ")
                + Text(amount.ticker)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .font(Theme.fonts.bodyLMedium)
            Spacer(minLength: 0)
        }
    }

    private var swapDividerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.primaryAccent4)
                .padding(6)
                .background(Theme.colors.bgSurface2)
                .clipShape(Circle())
                .bold()
            Text("to".localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.colors.bgSurface2)
        }
    }

    private func coinIcon(logo: String, ticker: String) -> some View {
        AsyncImageView(
            logo: logo,
            size: CGSize(width: 28, height: 28),
            ticker: ticker,
            tokenChainLogo: nil
        )
        .overlay(
            Circle()
                .stroke(Theme.colors.bgSurface2, lineWidth: 2)
        )
    }

    // MARK: - Raw payload

    private func rawPayloadPanel(payload: String) -> some View {
        DisclosureSection(title: "transactionDetails") {
            rawPayloadDisclosureContent(payload: payload)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private func rawPayloadDisclosureContent(payload: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("rawPayload".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(payload)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Amount formatters

    private func tonAmountString(rawAmount: String) -> String {
        "\(formatBaseAmount(rawAmount: rawAmount, decimals: 9)) TON"
    }

    private func jettonAmountString(
        rawAmount: String,
        coin: TonJettonMetadataResolver.Resolved?
    ) -> String {
        guard let coin else { return rawAmount }
        let formatted = formatBaseAmount(rawAmount: rawAmount, decimals: coin.decimals)
        return "\(formatted) \(coin.ticker)"
    }

    private func formatBaseAmount(rawAmount: String, decimals: Int) -> String {
        TonOperationExtractor.formatAmount(rawAmount: rawAmount, decimals: decimals)
    }
}
