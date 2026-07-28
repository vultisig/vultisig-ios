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
struct RippleTrustLineActivationSheet: View {
    @ObservedObject var viewModel: RippleTrustLineActivationViewModel
    /// Optional so the presenting binding and the content can be driven by the
    /// same `@State` without the sheet body having to exist before a coin does.
    let coin: Coin?
    @Binding var isPresented: Bool
    let onActivate: () -> Void

    var body: some View {
        if let coin {
            content(coin: coin)
        }
    }

    private func content(coin: Coin) -> some View {
        Screen {
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
                    Spacer()
                    actions
                }
            }
        }
        // iOS dismisses by swipe; macOS has no drag affordance, so it needs an
        // explicit close, matching every other sheet in the app.
        .crossPlatformToolbar(showsBackButton: false) {
            #if os(macOS)
                CustomToolbarItem(placement: .leading) {
                    ToolbarButton(image: .xmark) {
                        isPresented = false
                    }
                }
            #endif
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
            // Middle truncation: an issuer's leading and trailing characters are
            // what distinguish it from a lookalike, so the ellipsis belongs in
            // the middle rather than at the end.
            row("rippleTrustLineIssuer", value: viewModel.quote?.issuer, ticker: nil, truncatesInMiddle: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface2))
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

    /// No Cancel button: the sheet is dismissible by swipe on iOS and by the
    /// toolbar close on macOS, so a third way out is redundant chrome.
    private var actions: some View {
        PrimaryButton(title: "rippleTrustLineActivateAction".localized, action: onActivate)
            .disabled(!viewModel.canActivate)
    }

    @ViewBuilder
    private func row(
        _ title: String,
        value: String?,
        ticker: String?,
        truncatesInMiddle: Bool = false
    ) -> some View {
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
                    .truncationMode(truncatesInMiddle ? .middle : .tail)
            }
        }
    }
}
