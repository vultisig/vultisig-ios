//
//  SwapVerifyViewModel.swift
//  VultisigApp
//
//  Holds the immutable `SwapTransaction` handed off by SwapDetailsViewModel.
//  The transaction itself is `var` so the 60s refresh path can swap in an
//  updated copy with the latest quote/fees — fields like fromCoin/toCoin/
//  fromAmount stay pinned, but the price-sensitive parts re-fetch.
//

import BigInt
import Combine
import OSLog
import SwiftUI

@MainActor
@Observable
final class SwapVerifyViewModel {
    @ObservationIgnored private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-verify")
    @ObservationIgnored private let interactor: SwapInteractor
    @ObservationIgnored private let thorchainService: ThorchainService
    @ObservationIgnored private let mayachainService: MayachainService
    @ObservationIgnored private let securityScanViewModel = SecurityScannerViewModel()
    @ObservationIgnored private var securityScannerCancellable: AnyCancellable?

    var transaction: SwapTransaction

    var isAmountCorrect = false
    var isFeeCorrect = false
    var isApproveCorrect = false

    var showSecurityScannerSheet: Bool = false
    var securityScannerState: SecurityScannerState = .idle

    var error: Error?
    var isLoading = false
    var isLoadingFees = false
    var isLoadingTransaction = false
    var timer: Int = 59

    init(
        transaction: SwapTransaction,
        interactor: SwapInteractor = DefaultSwapInteractor.live,
        thorchainService: ThorchainService = .shared,
        mayachainService: MayachainService = .shared
    ) {
        self.transaction = transaction
        self.interactor = interactor
        self.thorchainService = thorchainService
        self.mayachainService = mayachainService
    }

    func onLoad() {
        // SecurityScannerViewModel stays an ObservableObject (used elsewhere),
        // so we bridge its @Published `state` into our @Observable property via Combine.
        securityScannerCancellable = securityScanViewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.securityScannerState = state
            }
    }

    func isValidForm(shouldApprove: Bool) -> Bool {
        if shouldApprove {
            return isAmountCorrect && isFeeCorrect && isApproveCorrect
        } else {
            return isAmountCorrect && isFeeCorrect
        }
    }

    func scan() async {
        await securityScanViewModel.scan(transaction: transaction)
    }

    func validateSecurityScanner() -> Bool {
        showSecurityScannerSheet = securityScannerState.shouldShowWarning
        return !securityScannerState.shouldShowWarning
    }

    func updateTimer(vault: Vault, referredCode: String) async {
        timer -= 1
        if timer < 1 {
            await refreshData(vault: vault, referredCode: referredCode)
            timer = 59
        }
    }

    func refreshData(vault: Vault, referredCode: String) async {
        isLoadingFees = true
        defer { isLoadingFees = false }

        do {
            let result = try await interactor.fetchQuote(
                amount: transaction.fromAmount,
                fromCoin: transaction.fromCoin,
                toCoin: transaction.toCoin,
                vault: vault,
                referredCode: referredCode
            )
            var updated = transaction
            if let result {
                updated = updated.with(
                    quote: result.quote,
                    vultDiscountBps: result.vultDiscountBps,
                    referralDiscountBps: result.referralDiscountBps
                )
            }
            if let balanceError = SwapCryptoLogic.balanceError(
                fromCoin: updated.fromCoin,
                feeCoin: updated.feeCoin,
                fromAmount: updated.fromAmount.description,
                fee: updated.fee
            ) {
                throw balanceError
            }
            let chainSpecific = try await interactor.fetchChainSpecific(
                fromCoin: updated.fromCoin,
                toCoin: updated.toCoin,
                fromAmount: updated.fromAmount,
                quote: updated.quote
            )
            updated = updated.with(
                gas: chainSpecific.gas,
                thorchainFee: try await interactor.computeThorchainFee(
                    chainSpecific: chainSpecific,
                    fromCoin: updated.fromCoin,
                    fromAmount: updated.fromAmount,
                    vault: vault
                )
            )
            transaction = updated
            error = nil
        } catch {
            guard (error as? URLError)?.code != .cancelled else { return }
            logger.warning("Refresh quote error: \(error.localizedDescription)")
            self.error = error
        }
    }

    /// Sign-time fund-safety gate: re-check the live inbound for the source chain
    /// immediately before building the keysign payload, BYPASSING the 5-minute
    /// cache. Returns `true` when it's safe to sign; on a halt it sets
    /// `error = .tradingHalted` and returns `false` so the caller does NOT build
    /// the payload or navigate. Fail-closed only on a confirmed live halt — a
    /// fetch failure (empty inbound) does not block, matching the screen path's
    /// fail-soft semantics. Routes are re-checked across BOTH native protocols.
    func isSourceChainSafeToSign() async -> Bool {
        let sourceChain = transaction.fromCoin.chain
        async let thorInbound = thorchainService.fetchThorchainInboundAddress(bypassCache: true)
        async let mayaInbound = mayachainService.fetchInboundAddress(bypassCache: true)
        let thor = await thorInbound
        let maya = await mayaInbound
        let halted = SwapHaltGate.isHalted(chain: sourceChain, in: thor)
            || SwapHaltGate.isHalted(chain: sourceChain, in: maya)
        if halted {
            error = SwapError.tradingHalted
            return false
        }
        return true
    }

    func buildSwapKeysignPayload(vault: Vault) async -> KeysignPayload? {
        isLoadingTransaction = true
        defer { isLoadingTransaction = false }

        do {
            return try await interactor.buildSwapKeysignPayload(transaction: transaction, vault: vault)
        } catch {
            self.error = error
            return nil
        }
    }
}
