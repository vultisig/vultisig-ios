//
//  ChainConfig.swift
//  VultisigApp
//

import Foundation
import BigInt
import WalletCore

extension Chain {
    /// Immutable, static per-chain data. Replaces the parallel per-accessor
    /// switch statements (`name`, `ticker`, `feeUnit`, `swapAsset`, `logo`,
    /// `chainID`, `coinType`, `chainType`, `banxaBlockchainCode`,
    /// `minimumSendAmount`) with a single row per chain. Each accessor is now a
    /// keypath read into `configs`, so a value can only be defined in one place.
    struct ChainConfig {
        let name: String
        let ticker: String
        let feeUnit: String
        let swapAsset: String
        let logo: String
        let chainID: Int?
        let coinType: CoinType
        let chainType: ChainType
        let banxaBlockchainCode: String
        let minimumSendAmount: BigInt?
    }

    /// Lookup table built from an exhaustive switch (`makeConfig()`), so adding a
    /// new `Chain` case fails to compile until its row is defined. Built once
    /// from `Chain.allCases`, guaranteeing a row for every case.
    private static let configs: [Chain: ChainConfig] = Dictionary(
        uniqueKeysWithValues: Chain.allCases.map { ($0, $0.makeConfig()) }
    )

    private var config: ChainConfig {
        guard let config = Self.configs[self] else {
            // Unreachable: `configs` is seeded from every `Chain.allCases` case.
            fatalError("Missing ChainConfig for chain \(self)")
        }
        return config
    }

    // MARK: - Data accessors (keypath reads into the table)

    var name: String { config.name }
    var ticker: String { config.ticker }
    var feeUnit: String { config.feeUnit }
    var swapAsset: String { config.swapAsset }
    var logo: String { config.logo }
    var chainID: Int? { config.chainID }
    var coinType: CoinType { config.coinType }

    /// The chain family this chain belongs to. Single source of truth; `type`
    /// is a deprecated alias kept for existing call sites.
    var chainType: ChainType { config.chainType }

    /// Deprecated alias for `chainType`. Retained so existing call sites keep
    /// compiling; both return the same family.
    var type: ChainType { chainType }

    var banxaBlockchainCode: String { config.banxaBlockchainCode }

    /// Protocol-enforced minimum value (in the chain's base units) that every
    /// native output must carry, or `nil` when the chain imposes no such floor.
    /// Cardano requires ~1.4 ADA per UTXO; a smaller output is accepted by the
    /// wallet but silently dropped by the node.
    var minimumSendAmount: BigInt? { config.minimumSendAmount }

    // MARK: - Row definitions
    //
    // One row per chain, in `Chain` declaration order. These are the single
    // source of truth for the accessors above — every value here must stay
    // byte-identical to what the removed switch statements returned.

    private func makeConfig() -> ChainConfig {
        switch self {
        case .thorChain:
            return ChainConfig(name: "THORChain", ticker: "RUNE", feeUnit: "RUNE", swapAsset: "THOR", logo: "rune", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "THORCHAIN", minimumSendAmount: nil)
        case .thorChainChainnet:
            return ChainConfig(name: "THORChain-Chainnet", ticker: "RUNE", feeUnit: "RUNE", swapAsset: "THOR", logo: "rune", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "THORCHAIN-CHAINNET", minimumSendAmount: nil)
        case .thorChainStagenet:
            return ChainConfig(name: "THORChain-Stagenet", ticker: "RUNE", feeUnit: "RUNE", swapAsset: "THOR", logo: "rune", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "THORCHAIN-STAGENET", minimumSendAmount: nil)
        case .solana:
            return ChainConfig(name: "Solana", ticker: "SOL", feeUnit: "SOL", swapAsset: "SOL", logo: "solana", chainID: 1_151_111_081_099_710, coinType: .solana, chainType: .Solana, banxaBlockchainCode: "SOL", minimumSendAmount: nil)
        case .ethereum:
            return ChainConfig(name: "Ethereum", ticker: "ETH", feeUnit: "Gwei", swapAsset: "ETH", logo: "eth", chainID: 1, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "ETH", minimumSendAmount: nil)
        case .avalanche:
            return ChainConfig(name: "Avalanche", ticker: "AVAX", feeUnit: "Gwei", swapAsset: "AVAX", logo: "avax", chainID: 43114, coinType: .avalancheCChain, chainType: .EVM, banxaBlockchainCode: "AVAX-C", minimumSendAmount: nil)
        case .base:
            return ChainConfig(name: "Base", ticker: "BASE", feeUnit: "Gwei", swapAsset: "BASE", logo: "base", chainID: 8453, coinType: .base, chainType: .EVM, banxaBlockchainCode: "BASE", minimumSendAmount: nil)
        case .blast:
            return ChainConfig(name: "Blast", ticker: "BLAST", feeUnit: "Gwei", swapAsset: "BLAST", logo: "blast", chainID: 81457, coinType: .blast, chainType: .EVM, banxaBlockchainCode: "BLAST", minimumSendAmount: nil)
        case .arbitrum:
            return ChainConfig(name: "Arbitrum", ticker: "ARB", feeUnit: "Gwei", swapAsset: "ARB", logo: "arbitrum", chainID: 42161, coinType: .arbitrum, chainType: .EVM, banxaBlockchainCode: "ARB", minimumSendAmount: nil)
        case .polygon:
            return ChainConfig(name: "Polygon", ticker: "MATIC", feeUnit: "Gwei", swapAsset: "MATIC", logo: "matic", chainID: 137, coinType: .polygon, chainType: .EVM, banxaBlockchainCode: "MATIC", minimumSendAmount: nil)
        case .polygonV2:
            return ChainConfig(name: "Polygon", ticker: "POL", feeUnit: "Gwei", swapAsset: "POL", logo: "matic", chainID: 137, coinType: .polygon, chainType: .EVM, banxaBlockchainCode: "MATIC", minimumSendAmount: nil)
        case .optimism:
            return ChainConfig(name: "Optimism", ticker: "OP", feeUnit: "Gwei", swapAsset: "OP", logo: "optimism", chainID: 10, coinType: .optimism, chainType: .EVM, banxaBlockchainCode: "OPTIMISM", minimumSendAmount: nil)
        case .bscChain:
            return ChainConfig(name: "BSC", ticker: "BNB", feeUnit: "Gwei", swapAsset: "BSC", logo: "bsc", chainID: 56, coinType: .smartChain, chainType: .EVM, banxaBlockchainCode: "BSC", minimumSendAmount: nil)
        case .bitcoin:
            return ChainConfig(name: "Bitcoin", ticker: "BTC", feeUnit: "BTC/vbyte", swapAsset: "BTC", logo: "btc", chainID: nil, coinType: .bitcoin, chainType: .UTXO, banxaBlockchainCode: "BTC", minimumSendAmount: nil)
        case .bitcoinCash:
            return ChainConfig(name: "Bitcoin-Cash", ticker: "BCH", feeUnit: "BCH/vbyte", swapAsset: "BCH", logo: "bch", chainID: nil, coinType: .bitcoinCash, chainType: .UTXO, banxaBlockchainCode: "BCH", minimumSendAmount: nil)
        case .litecoin:
            return ChainConfig(name: "Litecoin", ticker: "LTC", feeUnit: "LTC/vbyte", swapAsset: "LTC", logo: "ltc", chainID: nil, coinType: .litecoin, chainType: .UTXO, banxaBlockchainCode: "LTC", minimumSendAmount: nil)
        case .dogecoin:
            return ChainConfig(name: "Dogecoin", ticker: "DOGE", feeUnit: "DOGE/vbyte", swapAsset: "DOGE", logo: "doge", chainID: nil, coinType: .dogecoin, chainType: .UTXO, banxaBlockchainCode: "DOGE", minimumSendAmount: nil)
        case .dash:
            return ChainConfig(name: "Dash", ticker: "DASH", feeUnit: "DASH/vbyte", swapAsset: "DASH", logo: "dash", chainID: nil, coinType: .dash, chainType: .UTXO, banxaBlockchainCode: "DASH", minimumSendAmount: nil)
        case .cardano:
            return ChainConfig(name: "Cardano", ticker: "ADA", feeUnit: "ADA/vbyte", swapAsset: "ADA", logo: "ada", chainID: nil, coinType: .cardano, chainType: .Cardano, banxaBlockchainCode: "ADA", minimumSendAmount: CardanoHelper.defaultMinUTXOValue)
        case .gaiaChain:
            return ChainConfig(name: "Cosmos", ticker: "UATOM", feeUnit: "uatom", swapAsset: "GAIA", logo: "atom", chainID: nil, coinType: .cosmos, chainType: .Cosmos, banxaBlockchainCode: "ATOM", minimumSendAmount: nil)
        case .kujira:
            return ChainConfig(name: "Kujira", ticker: "UKUJI", feeUnit: "ukuji", swapAsset: "KUJI", logo: "kuji", chainID: nil, coinType: .kujira, chainType: .Cosmos, banxaBlockchainCode: "KUJIRA", minimumSendAmount: nil)
        case .mayaChain:
            return ChainConfig(name: "MayaChain", ticker: "CACAO", feeUnit: "CACAO", swapAsset: "MAYA", logo: "maya", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "MAYACHAIN", minimumSendAmount: nil)
        case .cronosChain:
            return ChainConfig(name: "CronosChain", ticker: "CRO", feeUnit: "Gwei", swapAsset: "CRO", logo: "cro", chainID: 25, coinType: .cronosChain, chainType: .EVM, banxaBlockchainCode: "CRO", minimumSendAmount: nil)
        case .sui:
            return ChainConfig(name: "Sui", ticker: "SUI", feeUnit: "SUI", swapAsset: "SUI", logo: "sui", chainID: nil, coinType: .sui, chainType: .Sui, banxaBlockchainCode: "SUI", minimumSendAmount: nil)
        case .polkadot:
            return ChainConfig(name: "Polkadot", ticker: "DOT", feeUnit: "DOT", swapAsset: "DOT", logo: "dot", chainID: nil, coinType: .polkadot, chainType: .Polkadot, banxaBlockchainCode: "DOT", minimumSendAmount: nil)
        case .zksync:
            return ChainConfig(name: "Zksync", ticker: "ZK", feeUnit: "Gwei", swapAsset: "ZK", logo: "zsync_era", chainID: 324, coinType: .zksync, chainType: .EVM, banxaBlockchainCode: "ZKSYNC", minimumSendAmount: nil)
        case .dydx:
            return ChainConfig(name: "Dydx", ticker: "ADYDX", feeUnit: "adydx", swapAsset: "DYDX", logo: "dydx", chainID: nil, coinType: .dydx, chainType: .Cosmos, banxaBlockchainCode: "DYDX", minimumSendAmount: nil)
        case .ton:
            return ChainConfig(name: "Ton", ticker: "TON", feeUnit: "TON", swapAsset: "TON", logo: "ton", chainID: nil, coinType: .ton, chainType: .Ton, banxaBlockchainCode: "TON", minimumSendAmount: nil)
        case .osmosis:
            return ChainConfig(name: "Osmosis", ticker: "UOSMO", feeUnit: "uosmo", swapAsset: "OSMO", logo: "osmo", chainID: nil, coinType: .osmosis, chainType: .Cosmos, banxaBlockchainCode: "OSMOSIS", minimumSendAmount: nil)
        case .terra:
            return ChainConfig(name: "Terra", ticker: "ULUNA", feeUnit: "uluna", swapAsset: "LUNA", logo: "luna", chainID: nil, coinType: .terraV2, chainType: .Cosmos, banxaBlockchainCode: "LUNA", minimumSendAmount: nil)
        case .terraClassic:
            return ChainConfig(name: "TerraClassic", ticker: "ULUNC", feeUnit: "uluna", swapAsset: "LUNC", logo: "lunc", chainID: nil, coinType: .terra, chainType: .Cosmos, banxaBlockchainCode: "LUNC", minimumSendAmount: nil)
        case .noble:
            return ChainConfig(name: "Noble", ticker: "UUSDC", feeUnit: "uusdc", swapAsset: "USDC", logo: "noble", chainID: nil, coinType: .noble, chainType: .Cosmos, banxaBlockchainCode: "NOBLE", minimumSendAmount: nil)
        case .ripple:
            return ChainConfig(name: "Ripple", ticker: "XRP", feeUnit: "XRP", swapAsset: "XRP", logo: "xrp", chainID: nil, coinType: .xrp, chainType: .Ripple, banxaBlockchainCode: "XRP", minimumSendAmount: nil)
        case .akash:
            return ChainConfig(name: "Akash", ticker: "UAKT", feeUnit: "uakt", swapAsset: "AKT", logo: "akash", chainID: nil, coinType: .akash, chainType: .Cosmos, banxaBlockchainCode: "AKASH", minimumSendAmount: nil)
        case .tron:
            return ChainConfig(name: "Tron", ticker: "TRX", feeUnit: "TRX", swapAsset: "TRON", logo: "tron", chainID: nil, coinType: .tron, chainType: .Tron, banxaBlockchainCode: "TRON", minimumSendAmount: nil)
        case .ethereumSepolia:
            return ChainConfig(name: "Ethereum-Sepolia", ticker: "ETH", feeUnit: "Gwei", swapAsset: "ETH", logo: "eth", chainID: 11_155_111, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "ETH", minimumSendAmount: nil)
        case .zcash:
            return ChainConfig(name: "Zcash", ticker: "ZEC", feeUnit: "ZEC/vbyte", swapAsset: "ZEC", logo: "zec", chainID: nil, coinType: .zcash, chainType: .UTXO, banxaBlockchainCode: "ZEC", minimumSendAmount: nil)
        case .mantle:
            return ChainConfig(name: "Mantle", ticker: "MNT", feeUnit: "Gwei", swapAsset: "MANTLE", logo: "mantle", chainID: 5000, coinType: .mantle, chainType: .EVM, banxaBlockchainCode: "MNT", minimumSendAmount: nil)
        case .hyperliquid:
            return ChainConfig(name: "Hyperliquid", ticker: "HYPE", feeUnit: "Gwei", swapAsset: "HYPE", logo: "hyperliquid", chainID: 999, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "HYPE", minimumSendAmount: nil)
        case .sei:
            return ChainConfig(name: "Sei", ticker: "SEI", feeUnit: "Gwei", swapAsset: "SEI", logo: "sei", chainID: 1329, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "SEI", minimumSendAmount: nil)
        case .qbtc:
            return ChainConfig(name: "QBTC", ticker: "QBTC", feeUnit: "qbtc", swapAsset: "QBTC", logo: "qbtc", chainID: nil, coinType: .cosmos, chainType: .Cosmos, banxaBlockchainCode: "QBTC", minimumSendAmount: nil)
        case .bittensor:
            return ChainConfig(name: "Bittensor", ticker: "TAO", feeUnit: "RAO", swapAsset: "TAO", logo: "bittensor", chainID: nil, coinType: .polkadot, chainType: .Polkadot, banxaBlockchainCode: "TAO", minimumSendAmount: nil)
        }
    }
}
