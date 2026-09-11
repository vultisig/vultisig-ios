#if os(iOS)
import Foundation

/// One cancellable network observation; no polling loop and no ActivityKit admission.
@MainActor
final class TransactionActivityStatusRefresher {
    typealias Lookup = @MainActor (UUID) -> TransactionHistoryData?
    typealias SwapRefresh = @MainActor (TransactionHistoryData, @escaping @MainActor () -> Bool) async -> Void

    private let storage: TransactionHistoryStorage
    private let checker: any TransactionStatusChecking
    private let lookup: Lookup
    private let refreshSwap: SwapRefresh
    private let didCompleteSend: () -> Void

    init(storage: TransactionHistoryStorage, checker: any TransactionStatusChecking,
         lookup: @escaping Lookup, refreshSwap: @escaping SwapRefresh, didCompleteSend: @escaping () -> Void = {}) {
        self.storage = storage
        self.checker = checker
        self.lookup = lookup
        self.refreshSwap = refreshSwap
        self.didCompleteSend = didCompleteSend
    }

    func refresh(_ original: TransactionHistoryData) async {
        guard !Task.isCancelled, let row = current(original) else { return }
        if row.type == .swap {
            guard row.swapTracking?.providerKind == SwapKitTrackingService.providerKind else { return }
            await refreshSwap(row) { [weak self] in
                guard !Task.isCancelled, let fresh = self?.current(row) else { return false }
                return fresh.swapTracking?.broadcastHash == row.swapTracking?.broadcastHash
                    && fresh.swapTracking?.sourceChainId == row.swapTracking?.sourceChainId
                    && fresh.swapTracking?.providerKind == SwapKitTrackingService.providerKind
            }
            return
        }
        guard row.type == .send, row.swapTracking == nil, let chain = Chain(rawValue: row.chainRawValue) else { return }
        do {
            let result = try await checker.checkTransactionStatus(txHash: row.txHash, chain: chain)
            guard !Task.isCancelled, let fresh = current(row), fresh.type == .send, fresh.swapTracking == nil else { return }
            switch result.status {
            case .confirmed:
                if try storage.updateActivitySendStatus(id: fresh.id, status: .successful, errorMessage: nil, observedAt: Date()) {
                    didCompleteSend()
                }
            case .failed(let reason):
                if try storage.updateActivitySendStatus(id: fresh.id, status: .error, errorMessage: reason, observedAt: Date()) {
                    didCompleteSend()
                }
            case .pending:
                storage.publishObservation(txHash: fresh.txHash, pubKeyECDSA: fresh.pubKeyECDSA, chain: chain, isPending: true)
            case .notFound:
                storage.publishObservation(txHash: fresh.txHash, pubKeyECDSA: fresh.pubKeyECDSA, chain: chain, isPending: false)
            }
        } catch {
            guard !Task.isCancelled, let fresh = current(row) else { return }
            // Network/processing expiry conveys freshness only, never a failed transaction.
            storage.publishObservation(txHash: fresh.txHash, pubKeyECDSA: fresh.pubKeyECDSA, chain: chain, isPending: false)
        }
    }

    private func current(_ row: TransactionHistoryData) -> TransactionHistoryData? {
        guard let fresh = lookup(row.id),
              TransactionActivityPolicy.identity(fresh) == TransactionActivityPolicy.identity(row),
              !TransactionActivityPolicy.phase(for: fresh).isTerminal else { return nil }
        return fresh
    }
}
#endif
