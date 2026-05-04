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
        if let normalized = provider?
            .lowercased()
            .filter({ $0.isLetter || $0.isNumber }) {
            switch normalized {
            case "lifi":
                return URL(string: Endpoint.getLifiSwapTracker(txid: txHash))
            case "maya", "mayachain":
                return URL(string: Endpoint.getMayaSwapTracker(txid: txHash))
            case "thorchain", "thorswap":
                if chainRawValue == Chain.thorChainStagenet.rawValue {
                    return URL(string: Endpoint.getStagenetSwapProgressURL(txid: txHash))
                }
                return URL(string: Endpoint.getSwapProgressURL(txid: txHash))
            default:
                break
            }
        }
        if let chain = Chain(rawValue: chainRawValue) {
            return URL(string: Endpoint.getExplorerURL(chain: chain, txid: txHash))
        }
        return URL(string: fallbackExplorerLink)
    }
}
