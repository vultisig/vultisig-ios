//
//  DoneScreen.swift
//  VultisigApp
//
//  Screen-rooted entry point for every "done" surface in the app —
//  Send / Swap / QBTC claim / cosigner-Send / cosigner-Swap / signed
//  message. Mirrors Android's `TxDoneScaffold`. Composes the status
//  header (built-in from the status source) with three flow-supplied
//  slots:
//
//    - `tokenContent`  — hero card. Default = coin display.
//    - `detailContent` — hash row + "Transaction details" disclosure
//                        by default; Swap supplies `EmptyView()` since
//                        the summary card above covers it.
//    - `bottomBar`     — default = single "Done" CTA; Swap supplies
//                        "Track" + "Done".
//
//  Owns the `hashCopied` toast state internally and routes it via the
//  `notifyHashCopied` environment callback — slot consumers (the hash
//  row, the swap summary card) call `notifyHashCopied()` when the user
//  copies a hash and the popup fires on this screen. Wraps everything
//  in `Screen { … }.screenTitle("done").screenBackButtonHidden()` so
//  consumers don't redo the chrome.
//

import SwiftUI

struct DoneScreen<
    StatusSource: TransactionDoneStatusSource,
    TokenContent: View,
    DetailContent: View,
    BottomBar: View
>: View {
    let input: TransactionDonePayload

    @ObservedObject var statusSource: StatusSource

    let tokenContent: () -> TokenContent
    let detailContent: () -> DetailContent
    let bottomBarContent: () -> BottomBar

    @State private var showAlert = false

    init(
        input: TransactionDonePayload,
        statusSource: StatusSource,
        @ViewBuilder tokenContent: @escaping () -> TokenContent,
        @ViewBuilder detailContent: @escaping () -> DetailContent,
        @ViewBuilder bottomBarContent: @escaping () -> BottomBar
    ) {
        self.input = input
        self.statusSource = statusSource
        self.tokenContent = tokenContent
        self.detailContent = detailContent
        self.bottomBarContent = bottomBarContent
    }

    var body: some View {
        Screen {
            content
                .overlay(PopupCapsule(text: "hashCopied", showPopup: $showAlert))
        }
        .screenTitle("done".localized)
        .screenBackButtonHidden()
        .environment(\.notifyHashCopied) { showAlert = true }
    }

    private var content: some View {
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
        statusSource: StatusSource
    ) {
        self.init(
            input: input,
            statusSource: statusSource,
            tokenContent: {
                DoneTokenContent(input: input)
            },
            detailContent: {
                DoneDetailContent(input: input)
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

    @Environment(\.router) var router

    var body: some View {
        VStack(spacing: 16) {
            Group {
                TransactionDoneHashRowView(
                    hash: input.hash,
                    explorerLink: input.explorerLink,
                    showCopy: true
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
                Text("transactionDetails".localized)
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

// MARK: - Hash-copied alert environment

private struct NotifyHashCopiedKey: EnvironmentKey {
    static let defaultValue: () -> Void = { }
}

extension EnvironmentValues {
    /// Called by slot subviews (hash row, swap summary card) when the
    /// user copies a tx hash. `DoneScreen` flips its internal toast
    /// state when this fires; default no-op means previews and
    /// detached usages stay silent.
    var notifyHashCopied: () -> Void {
        get { self[NotifyHashCopiedKey.self] }
        set { self[NotifyHashCopiedKey.self] = newValue }
    }
}
