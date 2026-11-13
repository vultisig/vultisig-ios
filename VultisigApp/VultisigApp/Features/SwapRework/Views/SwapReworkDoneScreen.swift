//
//  SwapReworkDoneScreen.swift
//  VultisigApp
//
//  The reworked post-broadcast screen: the stage tracker while the swap is in
//  flight, then the success summary. Status comes from the same
//  `DoneStatusServiceFactory.swap` pollers the existing done screen uses, and
//  `SwapDoneScreen` has already recorded the history row before this renders.
//

import SwiftUI

struct SwapReworkDoneScreen: View {
    let vault: Vault
    let hash: String
    let transaction: SwapTransaction
    let onTryAgain: (() -> Void)?
    let onDone: () -> Void

    @StateObject private var statusService: DoneStatusService
    @State private var startedAt = Date()
    @State private var now = Date()
    /// Frozen when the pollers first report completion, so "Took" stops.
    @State private var confirmedAt: Date?
    /// Read from the chain after completion; nil when the route does not
    /// state it, and the summary then shows no delivered row or difference.
    @State private var delivered: Decimal?
    /// A supported route whose delivered amount is not readable yet (receipt
    /// not mined, Midgard not indexed, an RPC hiccup): retried with backoff.
    @State private var isCheckingDelivered = false
    @State private var deliveredTask: Task<Void, Never>?
    /// When each stage was first seen done, for the tracker's time column.
    @State private var stageDoneAt: [SwapTrackerStage.Kind: Date] = [:]

    @State private var notifier: SwapLandingNotifier
    @Environment(\.router) private var router

    private let deliveredService = SwapDeliveredAmountService()

    init(
        vault: Vault,
        hash: String,
        transaction: SwapTransaction,
        statusService: @autoclosure @escaping () -> DoneStatusService,
        onTryAgain: (() -> Void)?,
        onDone: @escaping () -> Void
    ) {
        self.vault = vault
        self.hash = hash
        self.transaction = transaction
        self.onTryAgain = onTryAgain
        self.onDone = onDone
        _statusService = StateObject(wrappedValue: statusService())
        _notifier = State(initialValue: SwapLandingNotifier(hash: hash))
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    Group {
                        if statusService.status == .confirmed {
                            SwapReworkSuccessView(state: successState)
                        } else {
                            VStack(spacing: 16) {
                                SwapReworkTrackerView(state: trackerState)
                                SwapReworkNotifyCard(
                                    state: notifier.state,
                                    ticker: transaction.toCoin.ticker,
                                    onTurnOn: { Task { await turnOnNotify() } },
                                    onTurnOff: { notifier.turnOff() },
                                    onOpenSettings: { router.navigate(to: SettingsRoute.notifications) }
                                )
                            }
                        }
                    }
                    .padding(16)
                }
                HStack(spacing: 10) {
                    if let onTryAgain, case .failed = statusService.status {
                        PrimaryButton(title: "tryAgain".localized, type: .secondary, action: onTryAgain)
                    }
                    PrimaryButton(title: (statusService.status == .confirmed ? "done" : "swapReworkBackToVault").localized, action: onDone)
                }
                .padding(16)
            }
        }
        .screenTitle("swap".localized)
        .screenBackButtonHidden()
        .onAppear { statusService.start() }
        .onDisappear {
            statusService.stop()
            deliveredTask?.cancel()
        }
        .swapRefreshTick { now = Date() }
        .onChange(of: statusService.status) { _, status in
            recordStageTimes(status: status)
            guard status == .confirmed, confirmedAt == nil else { return }
            confirmedAt = Date()
            loadDelivered()
        }
    }

    private var isCrossChain: Bool {
        transaction.fromCoin.chain != transaction.toCoin.chain
    }

    private var providerName: String {
        transaction.quote?.displayName ?? transaction.quote?.kind.displayName ?? ""
    }

    private var receiveText: String {
        SwapReworkFormat.amount(transaction.toAmountDecimal, ticker: transaction.toCoin.ticker)
    }

    private var trackerState: SwapReworkTrackerState {
        let status = statusService.status
        let estimate = transaction.quote?.totalSwapSeconds.map(TimeInterval.init)
        let elapsed = now.timeIntervalSince(startedAt)
        return SwapReworkTrackerState(
            pay: SwapReworkViewModel.asset(transaction.fromCoin),
            receive: SwapReworkViewModel.asset(transaction.toCoin),
            receiveAmountText: receiveText,
            providerName: providerName,
            stages: SwapTrackerModel.stages(status: status, isCrossChain: isCrossChain),
            phase: SwapTrackerModel.phase(status: status, elapsed: elapsed, estimate: estimate),
            remainingText: SwapTrackerModel.remainingRange(elapsed: elapsed, estimate: estimate)
                .map { String(format: "swapReworkUsuallyMore".localized, $0.lowerBound, $0.upperBound) },
            sentDetail: "\(SwapReworkFormat.amount(transaction.fromAmount, ticker: transaction.fromCoin.ticker)) · \(SwapTokenTrust.shortContract(hash))",
            swappedDetail: "\(transaction.fromCoin.ticker) → \(transaction.toCoin.ticker)",
            receivedDetail: "\(receiveText) → \(SwapTokenTrust.shortContract(transaction.recipientAddress))",
            isCrossChain: isCrossChain,
            stageTimes: stageTimes,
            legNotes: SwapTrackerLegNotes.make(
                stages: SwapTrackerModel.stages(status: status, isCrossChain: isCrossChain),
                times: transaction.quote?.legTimes,
                sourceChain: transaction.fromCoin.chain.name,
                providerName: providerName,
                destinationIsBitcoin: transaction.toCoin.chain == .bitcoin
            )
        )
    }

    private func recordStageTimes(status: TransactionStatus) {
        let now = Date()
        for stage in SwapTrackerModel.stages(status: status, isCrossChain: isCrossChain)
        where stage.status == .done && stageDoneAt[stage.kind] == nil {
            stageDoneAt[stage.kind] = now
        }
    }

    private var stageTimes: [SwapTrackerStage.Kind: String] {
        var times = stageDoneAt.mapValues { $0.formatted(date: .omitted, time: .shortened) }
        if let active = SwapTrackerModel.stages(status: statusService.status, isCrossChain: isCrossChain)
            .first(where: { $0.status == .active }) {
            times[active.kind] = "swapReworkNow".localized
        }
        return times
    }

    /// The watcher gets its own poller, so the notification still comes after
    /// the user leaves this screen. Neutral copy: posted on completion, before
    /// any delivered amount is known, and never naming a destination.
    private func turnOnNotify() async {
        await notifier.turnOn(
            makeService: { DoneStatusServiceFactory.swap(txHash: hash, transaction: transaction, vault: vault) },
            title: "swapReworkNotifyDoneTitle".localized,
            body: String(format: "swapReworkNotifyDoneBody".localized, transaction.fromCoin.ticker, transaction.toCoin.ticker)
        )
    }

    /// Unsupported routes stop here ("doesn't report"). Supported ones are
    /// read again on `SwapDeliveredRetry.delays` until a figure comes back.
    private func loadDelivered() {
        guard let request = SwapDeliveredAmountService.request(for: transaction, hash: hash) else { return }
        isCheckingDelivered = true
        deliveredTask = Task {
            for delay in SwapDeliveredRetry.delays {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { break }
                if let amount = await deliveredService.deliveredAmount(request) {
                    delivered = amount
                    break
                }
            }
            isCheckingDelivered = false
        }
    }

    /// With a delivered amount from the chain: quoted against delivered. Without
    /// one: "Received", the quote marked approximate, and no difference.
    private var successState: SwapReworkSuccessState {
        let end = confirmedAt ?? now
        let minutes = max(1, Int((end.timeIntervalSince(startedAt) / 60).rounded(.up)))
        let toCoin = transaction.toCoin
        let outcome = delivered.map { SwapOutcome(quoted: transaction.toAmountDecimal, delivered: $0) }
        return SwapReworkSuccessState(
            receive: SwapReworkViewModel.asset(toCoin),
            // An external recipient is named by its address, never as the vault.
            vaultName: transaction.hasExternalRecipient
                ? SwapTokenTrust.shortContract(transaction.recipientAddress)
                : vault.name,
            isDeliveredKnown: outcome != nil,
            isCheckingDelivered: isCheckingDelivered && outcome == nil,
            deliveredText: delivered.map { "+" + SwapReworkFormat.amount($0, ticker: toCoin.ticker) } ?? "≈ " + receiveText,
            deliveredFiatText: delivered.map { toCoin.fiat(decimal: $0).formatToFiat() } ?? transaction.toFiatAmount,
            quotedText: receiveText,
            outcome: outcome,
            differenceText: outcome.flatMap { SwapReworkDoneScreen.differenceText($0, ticker: toCoin.ticker) },
            tookText: String(format: "swapReworkMinutes".localized, minutes),
            feesText: transaction.totalFeeString,
            tierName: VultDiscountTier.from(bpsDiscount: transaction.vultDiscountBps)?.name,
            tierSavedText: nil
        )
    }

    /// "+0.0000019 BTC · +0.01%"
    static func differenceText(_ outcome: SwapOutcome, ticker: String) -> String? {
        guard let share = outcome.differenceShareText else { return nil }
        let sign = outcome.difference < 0 ? "-" : "+"
        return "\(sign)\(SwapReworkFormat.amount(abs(outcome.difference), ticker: ticker)) · \(share)"
    }
}
