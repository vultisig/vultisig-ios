//
//  RippleTrustLineActivationSheet.swift
//  VultisigApp
//

import SwiftUI

/// Reserve warning shown before opening an XRPL trust line.
///
/// Opening a line is a signed on-ledger operation with a real, permanent cost:
/// it raises the XRP account's reserve floor by one owner-reserve increment for
/// as long as the line exists. That increment is a validator-voted network
/// parameter read live from `server_state`, so the figure here is whatever the
/// network currently says rather than a number baked into the app.
///
/// It also shows the trust-line LIMIT that will be signed. The limit is what the
/// TrustSet actually commits to, and a signed value the user never saw is a
/// value they cannot object to.
struct RippleTrustLineActivationSheet: View, BottomSheetProperties {
    @ObservedObject var viewModel: RippleTrustLineActivationViewModel
    /// Optional so the presenting binding and the content can be driven by the
    /// same `@State` without the sheet body having to exist before a coin does.
    let coin: Coin?
    let onActivate: () -> Void
    let onDismissRequest: () -> Void

    var body: some View {
        if let coin {
            content(coin: coin)
        }
    }

    /// The sheet is only presented once the quote has resolved, so this renders a
    /// terminal state and its height never changes after the first layout pass.
    /// That is load-bearing: the bottom-sheet container measures its content once
    /// and pins the detent to that height, so a sheet that grows after being
    /// presented gets clipped rather than resized.
    private func content(coin: Coin) -> some View {
        VStack(spacing: 24) {
            header(coin: coin)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.colors.alertError)
                    .font(Theme.fonts.bodySMedium)
                    .multilineTextAlignment(.center)
            } else if viewModel.quote != nil {
                costRows(coin: coin)
                blockingMessage
                actions
            }
        }
    }

    private func header(coin: Coin) -> some View {
        VStack(spacing: 12) {
            Icon(.triangleWarning, color: Theme.colors.alertWarning, size: 24)

            Text("rippleTrustLineActivationTitle".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title2)
                .multilineTextAlignment(.center)

            Text(String(format: "rippleTrustLineActivationSubtitle".localized, coin.ticker))
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.bodySMedium)
                .multilineTextAlignment(.center)
        }
    }

    private func costRows(coin: Coin) -> some View {
        VStack(spacing: 12) {
            row("rippleTrustLineOwnerReserve", value: viewModel.ownerReserveXRP, ticker: "XRP")
            row("estNetworkFee", value: viewModel.feeXRP, ticker: "XRP")
            row("rippleTrustLineSpendableAfter", value: viewModel.remainingSpendableXRP, ticker: "XRP")
            // The signed limit. Shown without a ticker suffix ambiguity: it is
            // denominated in the token, not in XRP.
            row("rippleTrustLineLimit", value: viewModel.limitDisplay, ticker: coin.ticker)
            issuerRow
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface2))
    }

    /// The issuer gets its own full-width line rather than sharing one with its
    /// label. An XRPL issuer address is 25–35 characters and only just overflows
    /// a shared row, so a side-by-side layout truncates a couple of characters
    /// while adding an ellipsis — hiding exactly the detail the row exists to let
    /// the user check, and hiding it in the middle where lookalike issuers differ.
    @ViewBuilder
    private var issuerRow: some View {
        if let issuer = viewModel.quote?.issuer {
            VStack(alignment: .leading, spacing: 4) {
                Text("rippleTrustLineIssuer".localized)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)

                Text(issuer)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.priceBodyS)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var blockingMessage: some View {
        if let insufficientXRPMessage = viewModel.insufficientXRPMessage {
            Text(insufficientXRPMessage)
                .foregroundStyle(Theme.colors.alertError)
                .font(Theme.fonts.caption12)
                .multilineTextAlignment(.center)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: "rippleTrustLineActivateAction".localized, action: onActivate)
                .disabled(!viewModel.canActivate)

            Button("cancel".localized, action: onDismissRequest)
                .frame(height: 42, alignment: .center)
                .foregroundStyle(Theme.colors.textButtonDisabled)
                .font(Theme.fonts.caption10)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(_ title: String, value: String?, ticker: String?) -> some View {
        if let value {
            HStack(spacing: 8) {
                Text(title.localized)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .font(Theme.fonts.bodySMedium)
                Spacer(minLength: 8)
                Text(ticker.map { "\(value) \($0)" } ?? value)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.priceBodyS)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
