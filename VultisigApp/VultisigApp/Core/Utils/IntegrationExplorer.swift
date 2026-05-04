//
//  IntegrationExplorer.swift
//  VultisigApp
//

import Foundation

/// Single source of truth for "View on Explorer" / "View Progress" URLs across
/// the app. Maps an integration identity (a stored provider string, a runtime
/// `SwapProvider`, or a keysign `SwapPayload`) to the appropriate tracker URL
/// (LI.FI scanner, THORChain RuneScan, MayaChain explorer) — or falls back to
/// the canonical chain explorer via `Endpoint.getExplorerURL` so behaviour stays
/// consistent everywhere a tx URL is shown.
enum IntegrationExplorer {

    // MARK: - High-level overloads

    static func url(for transaction: TransactionHistoryData) -> URL? {
        url(
            provider: transaction.swapProvider,
            txHash: transaction.txHash,
            chainRawValue: transaction.chainRawValue,
            fallbackExplorerLink: transaction.explorerLink
        )
    }

    /// Used by `SwapCryptoLogic.progressLink` (and any post-swap success view).
    /// Returns a `String?` to match the existing call-site signature.
    static func progressLink(quote: SwapQuote?, txHash: String, fromChain: Chain) -> String? {
        switch quote {
        case .thorchain:
            return thorchainTracker(txid: txHash)
        case .thorchainChainnet, .thorchainStagenet:
            return thorchainStagenetTracker(txid: txHash)
        case .mayachain:
            return mayaTracker(txid: txHash)
        case .lifi:
            return lifiTracker(txid: txHash)
        case .oneinch, .kyberswap, .none:
            return Endpoint.getExplorerURL(chain: fromChain, txid: txHash)
        }
    }

    /// Used by `KeysignViewModel.getSwapProgressURL`.
    /// Returns a `String?` to match the existing call-site signature.
    static func progressLink(swapPayload: SwapPayload?, txHash: String) -> String? {
        switch swapPayload {
        case .thorchain:
            return thorchainTracker(txid: txHash)
        case .thorchainChainnet, .thorchainStagenet:
            return thorchainStagenetTracker(txid: txHash)
        case .mayachain:
            return mayaTracker(txid: txHash)
        case .generic(let payload):
            if payload.provider == .lifi {
                return lifiTracker(txid: txHash)
            }
            return Endpoint.getExplorerURL(chain: payload.fromCoin.chain, txid: txHash)
        case .none:
            return nil
        }
    }

    // MARK: - Lower-level resolver (used by tx-history sheet + tests)

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
                return URL(string: lifiTracker(txid: txHash))
            case "maya", "mayachain":
                return URL(string: mayaTracker(txid: txHash))
            case "thorchain", "thorswap":
                if chainRawValue == Chain.thorChainStagenet.rawValue {
                    return URL(string: thorchainStagenetTracker(txid: txHash))
                }
                return URL(string: thorchainTracker(txid: txHash))
            default:
                break
            }
        }
        if let chain = Chain(rawValue: chainRawValue) {
            return URL(string: Endpoint.getExplorerURL(chain: chain, txid: txHash))
        }
        return URL(string: fallbackExplorerLink)
    }

    // MARK: - Private tracker URL builders
    // Hosts and path shapes match the canonical chain-explorer URLs in
    // `Endpoint.getExplorerURL`; LI.FI is unique because it's a cross-chain
    // aggregator scanner with no chain-explorer equivalent.

    private static func lifiTracker(txid: String) -> String {
        "https://scan.li.fi/tx/\(txid)"
    }

    private static func mayaTracker(txid: String) -> String {
        "https://www.explorer.mayachain.info/tx/\(txid.stripHexPrefix())"
    }

    private static func thorchainTracker(txid: String) -> String {
        "https://runescan.io/tx/\(txid.stripHexPrefix())"
    }

    private static func thorchainStagenetTracker(txid: String) -> String {
        "https://runescan.io/tx/\(txid.stripHexPrefix())?network=stagenet"
    }
}
