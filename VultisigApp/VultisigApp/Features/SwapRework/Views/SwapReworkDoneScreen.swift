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
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    Group {
                        if statusService.status == .confirmed {
                            SwapReworkSuccessView(state: successState)
                        } else {
                            SwapReworkTrackerView(state: trackerState)
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
        .onDisappear { statusService.stop() }
        .swapRefreshTick { now = Date() }
        .onChange(of: statusService.status) { _, status in
            if status == .confirmed, confirmedAt == nil { confirmedAt = Date() }
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
            receivedDetail: "\(receiveText) → \(SwapTokenTrust.shortContract(transaction.toCoin.address))",
            isCrossChain: isCrossChain
        )
    }

    /// The pollers report completion, not the delivered amount, so the summary
    /// shows the quoted amount as expected and never calls it delivered.
    private var successState: SwapReworkSuccessState {
        let end = confirmedAt ?? now
        let minutes = max(1, Int((end.timeIntervalSince(startedAt) / 60).rounded(.up)))
        return SwapReworkSuccessState(
            receive: SwapReworkViewModel.asset(transaction.toCoin),
            vaultName: vault.name,
            isDeliveredKnown: false,
            deliveredText: "≈ " + receiveText,
            deliveredFiatText: transaction.toFiatAmount,
            quotedText: receiveText,
            outcome: nil,
            differenceText: nil,
            tookText: String(format: "swapReworkMinutes".localized, minutes),
            feesText: transaction.totalFeeString,
            tierName: VultDiscountTier.from(bpsDiscount: transaction.vultDiscountBps)?.name,
            tierSavedText: nil
        )
    }
}
