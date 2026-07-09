//
//  DoneScreen.swift
//  VultisigApp
//
//  Screen-rooted entry point for every "done" surface in the app —
//  Send / Swap / QBTC claim / cosigner-Send / cosigner-Swap / signed
//  message. Mirrors Android's `TxDoneScaffold`. Composes the status
//  header (driven by the injected `DoneStatusService`) with three
//  flow-supplied slots:
//
//    - `tokenContent`  — hero card. Default = coin display.
//    - `detailContent` — hash row + an expandable "Transaction details"
//                        section by default; Swap supplies `EmptyView()`
//                        since the summary card above covers it.
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
    TokenContent: View,
    DetailContent: View,
    BottomBar: View
>: View {
    let input: TransactionDonePayload

    @StateObject private var statusService: DoneStatusService

    /// Nav-bar title for the screen. Defaults to "Done"; the initiator
    /// Send/Swap flows pass "Overview" so the in-place keysign→overview
    /// container reads as one continuous "Overview" screen (Figma).
    let navigationTitle: String

    let tokenContent: () -> TokenContent
    let detailContent: () -> DetailContent
    let bottomBarContent: () -> BottomBar

    @State private var showAlert = false

    /// Two-phase arrival. `.hero` shows only the status animation + title,
    /// vertically centered (continuing the full-bleed keysign animation that
    /// crossfades in). After `revealDelay` the header settles to the top and
    /// the card / details / bottom bar reveal beneath it (`.expanded`).
    /// Reduce Motion seeds `.expanded` so there's no staged beat.
    @State private var revealPhase: RevealPhase = .hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum RevealPhase { case hero, expanded }
    private var isExpanded: Bool { revealPhase == .expanded }

    /// Hold the centered hero before settling up. Sized so the #4777
    /// keysign→overview crossfade (0.35s opacity fade-in) finishes first,
    /// then the hero holds ~0.8s — so the crossfade and the settle-up read
    /// as two sequential beats instead of overlapping into one blur.
    private let revealDelay: UInt64 = 1_150_000_000 // ≈ 0.35s crossfade + 0.8s hold

    /// Construct via `DoneStatusServiceFactory`. The
    /// `statusService` autoclosure is evaluated lazily by `@StateObject`
    /// the first time the view appears — subsequent re-renders re-call
    /// the autoclosure but SwiftUI retains the original instance, so the
    /// polling task stays alive across body refreshes.
    init(
        input: TransactionDonePayload,
        statusService: @autoclosure @escaping () -> DoneStatusService,
        navigationTitle: String = "done".localized,
        @ViewBuilder tokenContent: @escaping () -> TokenContent,
        @ViewBuilder detailContent: @escaping () -> DetailContent,
        @ViewBuilder bottomBarContent: @escaping () -> BottomBar
    ) {
        self.input = input
        _statusService = StateObject(wrappedValue: statusService())
        self.navigationTitle = navigationTitle
        self.tokenContent = tokenContent
        self.detailContent = detailContent
        self.bottomBarContent = bottomBarContent
    }

    var body: some View {
        Screen {
            content
                .overlay(PopupCapsule(text: "hashCopied", showPopup: $showAlert))
        }
        .screenTitle(navigationTitle)
        .screenBackButtonHidden()
        .environment(\.notifyHashCopied) { showAlert = true }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Top spacer — present only in the hero phase; collapses to 0 on
            // expand so the header rises from center to top.
            Spacer(minLength: 0)
                .frame(maxHeight: isExpanded ? 0 : .infinity)

            TransactionStatusHeaderView(status: statusService.status, verb: input.verb)
                .frame(minHeight: 150, maxHeight: 200)
                .padding(.bottom, isExpanded ? 36 : 0)

            // Body — laid out only once expanded; fades + slides up.
            if isExpanded {
                ScrollView {
                    VStack(spacing: 8) {
                        tokenContent()

                        detailContent()
                    }
                }
                .scrollIndicators(.hidden)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                bottomBarContent()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Bottom spacer — mirrors the top spacer to center the hero.
            Spacer(minLength: 0)
                .frame(maxHeight: isExpanded ? 0 : .infinity)
        }
        .onAppear {
            statusService.start()
            TransactionHistoryRecording.record(payload: input)
        }
        .onDisappear { statusService.stop() }
        .task { await revealAfterHold() }
    }

    /// Holds the centered hero for `revealDelay`, then springs to the
    /// expanded layout. Reduce Motion skips the hold and the animation.
    private func revealAfterHold() async {
        guard !reduceMotion else {
            revealPhase = .expanded
            return
        }
        try? await Task.sleep(nanoseconds: revealDelay)
        // Respect `.task` cancellation on disappear — don't flip state /
        // animate a view that's already gone (e.g. after `restart()`).
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            revealPhase = .expanded
        }
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
        statusService: @autoclosure @escaping () -> DoneStatusService,
        navigationTitle: String = "done".localized
    ) {
        self.init(
            input: input,
            statusService: statusService(),
            navigationTitle: navigationTitle,
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

/// Default detail slot — renders the tx hash row + a "Transaction
/// details" section that expands the full detail rows in place.
struct DoneDetailContent: View {
    let input: TransactionDonePayload

    @State private var isTransactionDetailsExpanded = false

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

            transactionDetailsSection
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

    private var transactionDetailsSection: some View {
        VStack(spacing: 18) {
            Button {
                withAnimation {
                    isTransactionDetailsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("transactionDetails".localized)
                    Spacer()
                    Icon(named: "chevron-down", color: Theme.colors.textSecondary, size: 16)
                        .rotationEffect(.degrees(isTransactionDetailsExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isTransactionDetailsExpanded {
                TransactionDetailsCard(input: input)
                    .transition(.verticalGrowAndFade)
            }
        }
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

// MARK: - Previews

#if DEBUG
/// Preview-only status backend — surfaces a fixed status and never polls,
/// so the staged reveal can be exercised in the canvas without a live tx.
private struct PreviewDoneStatusPoller: DoneStatusPoller {
    let initialStatus: TransactionStatus
    func start(onStatus _: @escaping (TransactionStatus) -> Void) { }
    func stop() { }
}

private func previewDonePayload() -> TransactionDonePayload {
    TransactionDonePayload(
        coin: .example,
        amountCrypto: "0.5 ETH",
        amountFiat: "1234.56",
        hash: "0x8f3ac1b29e7d5640",
        explorerLink: "",
        memo: "",
        isSend: true,
        fromAddress: "0x1A2b3C4d5E6f7089",
        toAddress: "0x90aB81cD72eF6350",
        fee: FeeDisplay(crypto: "0.00021 ETH", fiat: "$0.62"),
        keysignPayload: nil,
        pubKeyECDSA: ""
    )
}

@MainActor
private func previewDoneScreen(_ status: TransactionStatus) -> some View {
    DoneScreen(
        input: previewDonePayload(),
        statusService: DoneStatusService(poller: PreviewDoneStatusPoller(initialStatus: status)),
        navigationTitle: "overview".localized
    )
    .environmentObject(AppViewModel())
}

// Re-run the preview (⌘-Option-P / the refresh button) to replay the
// hero → settle-up reveal.
#Preview("Staged reveal · broadcasted") {
    previewDoneScreen(.broadcasted(estimatedTime: "~5 sec"))
}

#Preview("Staged reveal · confirmed") {
    previewDoneScreen(.confirmed)
}
#endif
