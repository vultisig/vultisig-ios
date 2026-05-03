//
//  IntegrationExplorer.swift
//  VultisigApp
//

import Foundation

/// Resolves the best "View on Explorer" URL for a transaction history entry,
/// preferring an integration-specific tracker (LI.FI scanner, THORChain RuneScan,
/// MayaChain explorer) when the transaction was routed through a known integration,
/// and falling back to the chain explorer otherwise.
enum IntegrationExplorer {
    static func url(for transaction: TransactionHistoryData) -> URL? {
        url(
            provider: transaction.swapProvider,
            txHash: transaction.txHash,
            chainRawValue: transaction.chainRawValue,
            fallbackExplorerLink: transaction.explorerLink
        )
    }

    static func url(
        provider: String?,
        txHash: String,
        chainRawValue: String,
        fallbackExplorerLink: String
    ) -> URL? {
        if let normalized = provider?.lowercased().replacingOccurrences(of: " ", with: "") {
            if normalized.contains("lifi") || normalized.contains("li.fi") {
                return URL(string: Endpoint.getLifiSwapTracker(txid: txHash))
            }
            if normalized.contains("maya") {
                return URL(string: Endpoint.getMayaSwapTracker(txid: txHash))
            }
            if normalized.contains("thorchain") || normalized.contains("thorswap") {
                if chainRawValue == Chain.thorChainStagenet.rawValue {
                    return URL(string: Endpoint.getStagenetSwapProgressURL(txid: txHash))
                }
                return URL(string: Endpoint.getSwapProgressURL(txid: txHash))
            }
        }
        return URL(string: fallbackExplorerLink)
    }
}
