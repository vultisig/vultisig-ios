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
        case .thorchainChainnet:
            return thorchainChainnetTracker(txid: txHash)
        case .thorchainStagenet:
            return thorchainStagenetTracker(txid: txHash)
        case .mayachain:
            return mayaTracker(txid: txHash)
        case .lifi:
            return lifiTracker(txid: txHash)
        case .swapkit:
            // Phase 1 ships the explorer-link fallback; `/track` polling is
            // covered by the follow-up tx-history plan. `track.swapkit.dev`
            // accepts on-chain hashes for the source chain.
            return "https://track.swapkit.dev/?hash=\(txHash)"
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
        case .thorchainChainnet:
            return thorchainChainnetTracker(txid: txHash)
        case .thorchainStagenet:
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
            // Aliases cover every value SwapQuote.displayName and
            // SwapPayload.providerName can produce, plus the legacy
            // "thorswap" string from older history entries.
            switch normalized {
            case "lifi":
                return URL(string: lifiTracker(txid: txHash))
            case "maya", "mayachain", "mayaprotocol":
                return URL(string: mayaTracker(txid: txHash))
            case "thorchainstagenet":
                return URL(string: thorchainStagenetTracker(txid: txHash))
            case "thorchainchainnet":
                return URL(string: thorchainChainnetTracker(txid: txHash))
            case "thorchain", "thorswap":
                if chainRawValue == Chain.thorChainChainnet.rawValue {
                    return URL(string: thorchainChainnetTracker(txid: txHash))
                }
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
            return "https://qbtc-explorer.vercel.app/qbtc/tx/\(txid)"
        }
    }

    // MARK: - Chain address explorer URL

    static func getExplorerByAddressURL(chain: Chain, address: String) -> String? {
        switch chain {
        case .bitcoin:
            return "https://mempool.space/address/\(address)"
        case .bitcoinCash:
            return "https://blockchair.com/bitcoin-cash/address/\(address)"
        case .litecoin:
            return "https://blockchair.com/litecoin/address/\(address)"
        case .dogecoin:
            return "https://blockchair.com/dogecoin/address/\(address)"
        case .dash:
            return "https://blockchair.com/dash/address/\(address)"
        case .zcash:
            return "https://blockchair.com/zcash/address/\(address)"
        case .thorChain:
            return "https://runescan.io/address/\(address)"
        case .thorChainChainnet:
            return "https://runescan.io/address/\(address)?network=chainnet"
        case .thorChainStagenet:
            return "https://runescan.io/address/\(address)?network=stagenet"
        case .solana:
            return "https://orb.helius.dev/address/\(address)"
        case .ethereum:
            return "https://etherscan.io/address/\(address)"
        case .ethereumSepolia:
            return "https://sepolia.etherscan.io/address/\(address)"
        case .gaiaChain:
            return "https://www.mintscan.io/cosmos/address/\(address)"
        case .dydx:
            return "https://www.mintscan.io/dydx/address/\(address)"
        case .kujira:
            return "https://finder.kujira.network/kaiyo-1/address/\(address)"
        case .avalanche:
            return "https://snowtrace.io/address/\(address)"
        case .bscChain:
            return "https://bscscan.com/address/\(address)"
        case .mayaChain:
            return "https://www.explorer.mayachain.info/address/\(address)"
        case .arbitrum:
            return "https://arbiscan.io/address/\(address)"
        case .base:
            return "https://basescan.org/address/\(address)"
        case .optimism:
            return "https://optimistic.etherscan.io/address/\(address)"
        case .polygon, .polygonV2:
            return "https://polygonscan.com/address/\(address)"
        case .blast:
            return "https://blastscan.io/address/\(address)"
        case .cronosChain:
            return "https://cronoscan.com/address/\(address)"
        case .sui:
            return "https://suiscan.xyz/mainnet/address/\(address)"
        case .polkadot:
            return "https://assethub-polkadot.subscan.io/account/\(address)"
        case .zksync:
            return "https://explorer.zksync.io/address/\(address)"
        case .ton:
            return "https://tonviewer.com/\(address)"
        case .osmosis:
            return "https://www.mintscan.io/osmosis/address/\(address)"
        case .terra:
            return "https://www.mintscan.io/terra/address/\(address)"
        case .terraClassic:
            return "https://finder.terra.money/classic/address/\(address)"
        case .noble:
            return "https://www.mintscan.io/noble/address/\(address)"
        case .ripple:
            return "https://xrpscan.com/account/\(address)"
        case .akash:
            return "https://www.mintscan.io/akash/address/\(address)"
        case .tron:
            return "https://tronscan.org/#/address/\(address)"
        case .cardano:
            return "https://cardanoscan.io/address/\(address)"
        case .mantle:
            return "https://mantlescan.xyz/address/\(address)"
        case .hyperliquid:
            return "https://liquidscan.io/address/\(address)"
        case .sei:
            return "https://seiscan.io/address/\(address)"
        case .bittensor:
            return "https://taostats.io/account/\(address)"
        case .qbtc:
            return nil
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

    private static func thorchainChainnetTracker(txid: String) -> String {
        "https://runescan.io/tx/\(txid.stripHexPrefix())?network=chainnet"
    }

    private static func thorchainStagenetTracker(txid: String) -> String {
        "https://runescan.io/tx/\(txid.stripHexPrefix())?network=stagenet"
    }
}
