#if os(iOS)
import Foundation
import SwiftData

/// Runs after positive broadcast evidence, independently of the Done view lifecycle.
@MainActor
enum TransactionLiveActivityBroadcast {
    static func record(hash: String, approveHash: String?, payload: KeysignPayload, vault: Vault, isInitiator: Bool) {
        guard isInitiator, !hash.isEmpty, TransactionActivityPolicy.isEligible(payload) else { return }
        TransactionLiveActivityCoordinator.shared.start()
        if let swap = payload.swapPayload {
            guard let chainID = SwapKitChainIdentifier.chainId(for: payload.coin.chain) else { return }
            let tracking = SwapTrackingMetadataData(
                providerKind: SwapKitTrackingService.providerKind, broadcastHash: hash, sourceChainId: chainID
            )
            TransactionHistoryRecorder.shared.recordSwap(
                txHash: hash, approveTxHash: approveHash, pubKeyECDSA: vault.pubKeyECDSA,
                fromCoin: swap.fromCoin, toCoin: swap.toCoin,
                fromAmountCrypto: payload.fromAmountString, fromAmountFiat: payload.fromAmountFiatString,
                toAmountCrypto: "\(swap.toAmountDecimal.formatForDisplay()) \(swap.toCoin.ticker)",
                toAmountFiat: payload.toSwapAmountFiatString,
                fromAddress: payload.coin.address, toAddress: swap.toCoin.address,
                feeCrypto: "", feeFiat: "", chain: payload.coin.chain,
                explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: payload.coin.chain, txid: hash),
                provider: swap.providerName, swapTracking: tracking
            )
        } else {
            TransactionHistoryRecorder.shared.recordFromKeysignPayload(
                txHash: hash, approveTxHash: approveHash, vault: vault, keysignPayload: payload
            )
        }
        do {
            let rows = try TransactionHistoryStorage.shared.fetchByChain(pubKeyECDSA: vault.pubKeyECDSA,
                                                                        chainRawValue: payload.coin.chain.rawValue)
            guard let row = rows.first(where: { $0.txHash == hash }) else { return }
            TransactionLiveActivityCoordinator.shared.trackBroadcast(row)
        } catch {
            Log.wallet.other.info("Live Activity could not read the saved receipt")
        }
    }

    static func vaultExists(pubKey: String) throws -> Bool {
        guard let context = Storage.shared.modelContext else { throw LookupError.unavailable }
        let predicate = #Predicate<Vault> { $0.pubKeyECDSA == pubKey }
        return try context.fetchCount(FetchDescriptor(predicate: predicate)) > 0
    }
    private enum LookupError: Error { case unavailable }
}
#endif
