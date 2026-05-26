//
//  DoneScreen.swift
//  VultisigApp
//
//  Slot-API entry point that mirrors Android's `TxDoneScaffold`.
//  Composes the status header (built-in from the status source) with
//  a flow-specific `tokenContent` (hero card — coin display for
//  Send/QBTC/cosigner, from/to swap cards for Swap), a flow-specific
//  `detailContent` (hash row + "Transaction details" disclosure by
//  default, omitted by Swap which surfaces the same info inside its
//  summary card), and a `bottomBarContent` slot (default: a single
//  "Done" button; Swap supplies "Track" + "Done").
//
//  This is the SINGLE shared surface for the Send / Swap / QBTC claim
//  / keysign-cosigner "done" experience. Each upstream flow constructs
//  a `TransactionDonePayload` and a concrete
//  `TransactionDoneStatusSource`, hands them in, and supplies any
//  non-default slots.
//

import SwiftUI

struct DoneScreen<
    StatusSource: TransactionDoneStatusSource,
    TokenContent: View,
    DetailContent: View,
    BottomBar: View
>: View {
    let input: TransactionDonePayload
    @Binding var showAlert: Bool

    @ObservedObject var statusSource: StatusSource

    let tokenContent: () -> TokenContent
    let detailContent: () -> DetailContent
    let bottomBarContent: () -> BottomBar

    init(
        input: TransactionDonePayload,
        statusSource: StatusSource,
        showAlert: Binding<Bool>,
        @ViewBuilder tokenContent: @escaping () -> TokenContent,
        @ViewBuilder detailContent: @escaping () -> DetailContent,
        @ViewBuilder bottomBarContent: @escaping () -> BottomBar
    ) {
        self.input = input
        self.statusSource = statusSource
        self._showAlert = showAlert
        self.tokenContent = tokenContent
        self.detailContent = detailContent
        self.bottomBarContent = bottomBarContent
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    TransactionStatusHeaderView(status: statusSource.status, verb: input.verb)
                        .frame(minHeight: 150, maxHeight: 200)
                        .padding(.bottom, 36)

                    tokenContent()

                    detailContent()
                }
            }
            .scrollIndicators(.hidden)

            bottomBarContent()
        }
        .onAppear {
            statusSource.start()
            TransactionHistoryRecording.record(payload: input)
        }
        .onDisappear { statusSource.stop() }
    }
}

// MARK: - Default slot constructors

extension DoneScreen where TokenContent == DoneTokenContent,
                          DetailContent == DoneDetailContent,
                          BottomBar == DoneDefaultBottomBar {
    /// Send / QBTC / cosigner-Send convenience initializer that wires
    /// up the default slot content (coin display + hash row + Done CTA).
    init(
        input: TransactionDonePayload,
        statusSource: StatusSource,
        showAlert: Binding<Bool>
    ) {
        self.init(
            input: input,
            statusSource: statusSource,
            showAlert: showAlert,
            tokenContent: {
                DoneTokenContent(input: input)
            },
            detailContent: {
                DoneDetailContent(input: input, showAlert: showAlert)
            },
            bottomBarContent: {
                DoneDefaultBottomBar()
            }
        )
    }
}

// MARK: - Default slot implementations

/// Default token slot — renders the hero card with dApp banner +
/// Blockaid hero override + coin amount/fiat.
struct DoneTokenContent: View {
    let input: TransactionDonePayload

    var body: some View {
        VStack(spacing: 8) {
            if let metadata = input.dappMetadata, !metadata.isEmpty {
                DAppRequestBanner(metadata: metadata)
            }
            if let hero = input.hero {
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

    @ViewBuilder
    private var defaultCoinDisplay: some View {
        AsyncImageView(
            logo: input.coin.logo,
            size: CGSize(width: 32, height: 32),
            ticker: input.coin.ticker,
            tokenChainLogo: input.coin.tokenChainLogo
        )

        VStack(spacing: 4) {
            Text(input.amountCrypto)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(input.amountFiat.formatToFiat(includeCurrencySymbol: true))
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }
}

/// Default detail slot — renders the tx hash row + "Transaction details"
/// disclosure that routes into `SendCryptoSecondaryDoneView`.
struct DoneDetailContent: View {
    let input: TransactionDonePayload
    @Binding var showAlert: Bool

    @Environment(\.router) var router

    var body: some View {
        VStack(spacing: 16) {
            Group {
                TransactionDoneHashRowView(
                    hash: input.hash,
                    explorerLink: input.explorerLink,
                    showCopy: true,
                    showAlert: $showAlert
                )
                Separator()
                    .opacity(0.8)
            }
            .showIf(input.hash.isNotEmpty)

            transactionDetailsButton
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .foregroundStyle(Theme.colors.textSecondary)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.bgSurface2, lineWidth: 1)
        )
    }

    private var transactionDetailsButton: some View {
        Button {
            router.navigate(to: SendRoute.transactionDetails(input: input))
        } label: {
            HStack {
                Text(NSLocalizedString("transactionDetails", comment: ""))
                Spacer()
                Image(systemName: "chevron.right")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Default bottom bar — a single "Done" button that restarts the app.
struct DoneDefaultBottomBar: View {
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        PrimaryButton(title: "done") {
            appViewModel.restart()
        }
    }
}
