//
//  ExplorerLinkBuilder.swift
//  VultisigApp
//

import Foundation

/// Single source of truth for "View on Explorer" / "View Progress" URLs across
/// the app. Maps either an integration identity (a stored provider string, a
/// runtime `SwapQuote`, or a keysign `SwapPayload`) to the appropriate tracker
/// URL — LI.FI scanner, THORChain RuneScan, MayaChain explorer — or falls back
/// to the canonical chain explorer (`getExplorerURL`) so behaviour stays
/// consistent everywhere a tx URL is shown.
enum ExplorerLinkBuilder {

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
            return getExplorerURL(chain: fromChain, txid: txHash)
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
            return getExplorerURL(chain: payload.fromCoin.chain, txid: txHash)
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
            return URL(string: getExplorerURL(chain: chain, txid: txHash))
        }
        return URL(string: fallbackExplorerLink)
    }

    // MARK: - Chain explorer URL

    static func getExplorerURL(chain: Chain, txid: String) -> String {
        switch chain {
        case .bitcoin:
            return "https://mempool.space/tx/\(txid)"
        case .bitcoinCash:
            return "https://blockchair.com/bitcoin-cash/transaction/\(txid)"
        case .litecoin:
            return "https://blockchair.com/litecoin/transaction/\(txid)"
        case .dogecoin:
            return "https://blockchair.com/dogecoin/transaction/\(txid)"
        case .dash:
            return "https://blockchair.com/dash/transaction/\(txid)"
        case .zcash:
            return "https://blockchair.com/zcash/transaction/\(txid)"
        case .thorChain:
            return "https://runescan.io/tx/\(txid.stripHexPrefix())"
        case .thorChainChainnet:
            return "https://runescan.io/tx/\(txid.stripHexPrefix())?network=chainnet"
        case .thorChainStagenet:
            return "https://runescan.io/tx/\(txid.stripHexPrefix())?network=stagenet"
        case .solana:
            return "https://orb.helius.dev/tx/\(txid)"
        case .ethereum:
            return "https://etherscan.io/tx/\(txid)"
        case .gaiaChain:
            return "https://www.mintscan.io/cosmos/tx/\(txid)"
        case .dydx:
            return "https://www.mintscan.io/dydx/tx/\(txid)"
        case .kujira:
            return "https://finder.kujira.network/kaiyo-1/tx/\(txid)"
        case .avalanche:
            return "https://snowtrace.io/tx/\(txid)"
        case .bscChain:
            return "https://bscscan.com/tx/\(txid)"
        case .mayaChain:
            return "https://www.explorer.mayachain.info/tx/\(txid)"
        case .arbitrum:
            return "https://arbiscan.io/tx/\(txid)"
        case .base:
            return "https://basescan.org/tx/\(txid)"
        case .optimism:
            return "https://optimistic.etherscan.io/tx/\(txid)"
        case .polygon, .polygonV2:
            return "https://polygonscan.com/tx/\(txid)"
        case .blast:
            return "https://blastscan.io/tx/\(txid)"
        case .cronosChain:
            return "https://cronoscan.com/tx/\(txid)"
        case .sui:
            return "https://suiscan.xyz/mainnet/tx/\(txid)"
        case .polkadot:
            return "https://assethub-polkadot.subscan.io/extrinsic/\(txid)"
        case .bittensor:
            let hash = txid.hasPrefix("0x") ? txid : "0x\(txid)"
            return "https://taostats.io/extrinsic/\(hash)"
        case .zksync:
            return "https://explorer.zksync.io/tx/\(txid)"
        case .ton:
            return "https://tonviewer.com/transaction/\(txid)"
        case .osmosis:
            return "https://www.mintscan.io/osmosis/tx/\(txid)"
        case .terra:
            return "https://www.mintscan.io/terra/tx/\(txid)"
        case .terraClassic:
            return "https://finder.terra.money/classic/tx/\(txid)"
        case .noble:
            return "https://www.mintscan.io/noble/tx/\(txid)"
        case .ripple:
            return "https://xrpscan.com/tx/\(txid)"
        case .akash:
            return "https://www.mintscan.io/akash/tx/\(txid)"
        case .tron:
            return "https://tronscan.org/#/transaction/\(txid)"
        case .ethereumSepolia:
            return "https://sepolia.etherscan.io/tx/\(txid)"
        case .cardano:
            return "https://cardanoscan.io/transaction/\(txid)"
        case .mantle:
            return "https://explorer.mantle.xyz/tx/\(txid)"
        case .hyperliquid:
            return "https://liquidscan.io/tx/\(txid)"
        case .sei:
            return "https://seiscan.io/tx/\(txid)"
        case .qbtc:
            return ""
        }
    }

    // MARK: - Private integration tracker URL builders
    // Hosts and path shapes match the canonical chain-explorer URLs above;
    // LI.FI is unique because it's a cross-chain aggregator scanner with no
    // chain-explorer equivalent.

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
