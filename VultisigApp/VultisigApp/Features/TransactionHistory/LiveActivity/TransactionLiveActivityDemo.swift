#if DEBUG && os(iOS)
import Foundation

/// Synthetic ActivityKit exercise: no vault, history write, network call, or funds.
@MainActor
final class TransactionLiveActivityDemo {
    static let shared = TransactionLiveActivityDemo()
    private let client = SystemTransactionActivityClient()
    private var didLaunch = false
    private var recordIDs = Set<UUID>()

    func owns(recordID: UUID) -> Bool { recordIDs.contains(recordID) }
    private var task: Task<Void, Never>?

    func runIfRequested() async {
        guard !didLaunch, CommandLine.arguments.contains("-transactionLiveActivityDemo") else { return }
        didLaunch = true
        // Wait for the first active scene; Activity.request rejects inactive launches.
        for _ in 0..<20 {
            if client.isForeground { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        run()
    }

    func run() {
        guard task == nil, client.isForeground, client.isAuthorized,
              client.activities.filter(\.isActive).count < TransactionActivityPolicy.maximumActivities else { return }
        let arguments = CommandLine.arguments
        let swap = arguments.contains("-transactionLiveActivitySwap")
        let privateMode = arguments.contains("-transactionLiveActivityPrivate")
        let stale = arguments.contains("-transactionLiveActivityStale")
        let failed = arguments.contains("-transactionLiveActivityFailure")
        let recordID = UUID()
        let date = Date().addingTimeInterval(stale ? -120 : 0)
        func state(_ phase: TransactionActivityState.Phase, revision: Int) -> TransactionActivityState {
            TransactionActivityState(
                phase: phase, observedAt: stale ? date : Date(), revision: revision,
                summary: swap ? "125.123456 USDC → ETH" : "125.123456 USDC",
                network: "Base", showDetails: !privateMode,
                operation: swap ? .swap : .send,
                recipient: "0x1234567890123456789012345678901234567890",
                fee: "0.000004 ETH", provider: swap ? "SwapKit" : nil,
                submittedAt: date.addingTimeInterval(-30),
                sourceAssetID: "usdc", destinationAssetID: swap ? "eth" : nil
            )
        }
        do {
            recordIDs.insert(recordID)
            let id = try client.request(recordID: recordID, state: state(.submitted, revision: 1))
            Log.wallet.other.info("Synthetic Live Activity requested")
            task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self else { return }
                await self.client.update(id: id, state: state(swap ? .sourceConfirmed : .pending, revision: 2))
                try? await Task.sleep(for: .seconds(37))
                guard !Task.isCancelled else { return }
                await self.client.end(id: id, state: state(failed ? .failed : swap ? .completed : .confirmed, revision: 3), immediately: false)
                // The ended card remains visible for the client's 60-second
                // recognition window and still belongs to this fixture.
                try? await Task.sleep(for: .seconds(60))
                self.recordIDs.remove(recordID)
                self.task = nil
            }
        } catch {
            recordIDs.remove(recordID)
            Log.wallet.other.info("Synthetic Live Activity request unavailable")
        }
    }
}
#endif
