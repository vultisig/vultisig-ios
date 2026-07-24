//
//  ChainConfigParityTests.swift
//  VultisigAppTests
//
//  Pins the full per-chain data table that `ChainConfig` now backs. Before the
//  refactor these values lived in ~9 parallel 42-case switches on `Chain`
//  (`name`, `ticker`, `feeUnit`, `swapAsset`, `logo`, `chainID`, `coinType`,
//  `chainType`, `banxaBlockchainCode`) plus `minimumSendAmount`. This ledger is
//  an INDEPENDENT transcription of those pre-refactor switch outputs, so any
//  drift between the table and the historical values fails here.
//
//  `coinType` feeds address derivation and signing — its per-chain assertions
//  are the load-bearing ones. The coverage guard forces a new `Chain` case to
//  gain a row here (mirroring the compile-time guard: `ChainConfig.makeConfig`
//  is an exhaustive switch, so a new case cannot compile without a row).
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class ChainConfigParityTests: XCTestCase {

    private struct ExpectedConfig {
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

    // Hard-coded ledger — one row per `Chain`, transcribed from the
    // pre-refactor switch statements. Do NOT derive from `ChainConfig`; that
    // would make the parity check circular.
    private static let expected: [Chain: ExpectedConfig] = [
        .thorChain: ExpectedConfig(name: "THORChain", ticker: "RUNE", feeUnit: "RUNE", swapAsset: "THOR", logo: "rune", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "THORCHAIN", minimumSendAmount: nil),
        .thorChainChainnet: ExpectedConfig(name: "THORChain-Chainnet", ticker: "RUNE", feeUnit: "RUNE", swapAsset: "THOR", logo: "rune", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "THORCHAIN-CHAINNET", minimumSendAmount: nil),
        .thorChainStagenet: ExpectedConfig(name: "THORChain-Stagenet", ticker: "RUNE", feeUnit: "RUNE", swapAsset: "THOR", logo: "rune", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "THORCHAIN-STAGENET", minimumSendAmount: nil),
        .solana: ExpectedConfig(name: "Solana", ticker: "SOL", feeUnit: "SOL", swapAsset: "SOL", logo: "solana", chainID: 1_151_111_081_099_710, coinType: .solana, chainType: .Solana, banxaBlockchainCode: "SOL", minimumSendAmount: nil),
        .ethereum: ExpectedConfig(name: "Ethereum", ticker: "ETH", feeUnit: "Gwei", swapAsset: "ETH", logo: "eth", chainID: 1, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "ETH", minimumSendAmount: nil),
        .avalanche: ExpectedConfig(name: "Avalanche", ticker: "AVAX", feeUnit: "Gwei", swapAsset: "AVAX", logo: "avax", chainID: 43114, coinType: .avalancheCChain, chainType: .EVM, banxaBlockchainCode: "AVAX-C", minimumSendAmount: nil),
        .base: ExpectedConfig(name: "Base", ticker: "BASE", feeUnit: "Gwei", swapAsset: "BASE", logo: "base", chainID: 8453, coinType: .base, chainType: .EVM, banxaBlockchainCode: "BASE", minimumSendAmount: nil),
        .blast: ExpectedConfig(name: "Blast", ticker: "BLAST", feeUnit: "Gwei", swapAsset: "BLAST", logo: "blast", chainID: 81457, coinType: .blast, chainType: .EVM, banxaBlockchainCode: "BLAST", minimumSendAmount: nil),
        .arbitrum: ExpectedConfig(name: "Arbitrum", ticker: "ARB", feeUnit: "Gwei", swapAsset: "ARB", logo: "arbitrum", chainID: 42161, coinType: .arbitrum, chainType: .EVM, banxaBlockchainCode: "ARB", minimumSendAmount: nil),
        .polygon: ExpectedConfig(name: "Polygon", ticker: "MATIC", feeUnit: "Gwei", swapAsset: "MATIC", logo: "matic", chainID: 137, coinType: .polygon, chainType: .EVM, banxaBlockchainCode: "MATIC", minimumSendAmount: nil),
        .polygonV2: ExpectedConfig(name: "Polygon", ticker: "POL", feeUnit: "Gwei", swapAsset: "POL", logo: "matic", chainID: 137, coinType: .polygon, chainType: .EVM, banxaBlockchainCode: "MATIC", minimumSendAmount: nil),
        .optimism: ExpectedConfig(name: "Optimism", ticker: "OP", feeUnit: "Gwei", swapAsset: "OP", logo: "optimism", chainID: 10, coinType: .optimism, chainType: .EVM, banxaBlockchainCode: "OPTIMISM", minimumSendAmount: nil),
        .bscChain: ExpectedConfig(name: "BSC", ticker: "BNB", feeUnit: "Gwei", swapAsset: "BSC", logo: "bsc", chainID: 56, coinType: .smartChain, chainType: .EVM, banxaBlockchainCode: "BSC", minimumSendAmount: nil),
        .bitcoin: ExpectedConfig(name: "Bitcoin", ticker: "BTC", feeUnit: "BTC/vbyte", swapAsset: "BTC", logo: "btc", chainID: nil, coinType: .bitcoin, chainType: .UTXO, banxaBlockchainCode: "BTC", minimumSendAmount: nil),
        .bitcoinCash: ExpectedConfig(name: "Bitcoin-Cash", ticker: "BCH", feeUnit: "BCH/vbyte", swapAsset: "BCH", logo: "bch", chainID: nil, coinType: .bitcoinCash, chainType: .UTXO, banxaBlockchainCode: "BCH", minimumSendAmount: nil),
        .litecoin: ExpectedConfig(name: "Litecoin", ticker: "LTC", feeUnit: "LTC/vbyte", swapAsset: "LTC", logo: "ltc", chainID: nil, coinType: .litecoin, chainType: .UTXO, banxaBlockchainCode: "LTC", minimumSendAmount: nil),
        .dogecoin: ExpectedConfig(name: "Dogecoin", ticker: "DOGE", feeUnit: "DOGE/vbyte", swapAsset: "DOGE", logo: "doge", chainID: nil, coinType: .dogecoin, chainType: .UTXO, banxaBlockchainCode: "DOGE", minimumSendAmount: nil),
        .dash: ExpectedConfig(name: "Dash", ticker: "DASH", feeUnit: "DASH/vbyte", swapAsset: "DASH", logo: "dash", chainID: nil, coinType: .dash, chainType: .UTXO, banxaBlockchainCode: "DASH", minimumSendAmount: nil),
        .cardano: ExpectedConfig(name: "Cardano", ticker: "ADA", feeUnit: "ADA/vbyte", swapAsset: "ADA", logo: "ada", chainID: nil, coinType: .cardano, chainType: .Cardano, banxaBlockchainCode: "ADA", minimumSendAmount: BigInt(1_400_000)),
        .gaiaChain: ExpectedConfig(name: "Cosmos", ticker: "UATOM", feeUnit: "uatom", swapAsset: "GAIA", logo: "atom", chainID: nil, coinType: .cosmos, chainType: .Cosmos, banxaBlockchainCode: "ATOM", minimumSendAmount: nil),
        .kujira: ExpectedConfig(name: "Kujira", ticker: "UKUJI", feeUnit: "ukuji", swapAsset: "KUJI", logo: "kuji", chainID: nil, coinType: .kujira, chainType: .Cosmos, banxaBlockchainCode: "KUJIRA", minimumSendAmount: nil),
        .mayaChain: ExpectedConfig(name: "MayaChain", ticker: "CACAO", feeUnit: "CACAO", swapAsset: "MAYA", logo: "maya", chainID: nil, coinType: .thorchain, chainType: .THORChain, banxaBlockchainCode: "MAYACHAIN", minimumSendAmount: nil),
        .cronosChain: ExpectedConfig(name: "CronosChain", ticker: "CRO", feeUnit: "Gwei", swapAsset: "CRO", logo: "cro", chainID: 25, coinType: .cronosChain, chainType: .EVM, banxaBlockchainCode: "CRO", minimumSendAmount: nil),
        .sui: ExpectedConfig(name: "Sui", ticker: "SUI", feeUnit: "SUI", swapAsset: "SUI", logo: "sui", chainID: nil, coinType: .sui, chainType: .Sui, banxaBlockchainCode: "SUI", minimumSendAmount: nil),
        .polkadot: ExpectedConfig(name: "Polkadot", ticker: "DOT", feeUnit: "DOT", swapAsset: "DOT", logo: "dot", chainID: nil, coinType: .polkadot, chainType: .Polkadot, banxaBlockchainCode: "DOT", minimumSendAmount: nil),
        .zksync: ExpectedConfig(name: "Zksync", ticker: "ZK", feeUnit: "Gwei", swapAsset: "ZK", logo: "zsync_era", chainID: 324, coinType: .zksync, chainType: .EVM, banxaBlockchainCode: "ZKSYNC", minimumSendAmount: nil),
        .dydx: ExpectedConfig(name: "Dydx", ticker: "ADYDX", feeUnit: "adydx", swapAsset: "DYDX", logo: "dydx", chainID: nil, coinType: .dydx, chainType: .Cosmos, banxaBlockchainCode: "DYDX", minimumSendAmount: nil),
        .ton: ExpectedConfig(name: "Ton", ticker: "TON", feeUnit: "TON", swapAsset: "TON", logo: "ton", chainID: nil, coinType: .ton, chainType: .Ton, banxaBlockchainCode: "TON", minimumSendAmount: nil),
        .osmosis: ExpectedConfig(name: "Osmosis", ticker: "UOSMO", feeUnit: "uosmo", swapAsset: "OSMO", logo: "osmo", chainID: nil, coinType: .osmosis, chainType: .Cosmos, banxaBlockchainCode: "OSMOSIS", minimumSendAmount: nil),
        .terra: ExpectedConfig(name: "Terra", ticker: "ULUNA", feeUnit: "uluna", swapAsset: "LUNA", logo: "luna", chainID: nil, coinType: .terraV2, chainType: .Cosmos, banxaBlockchainCode: "LUNA", minimumSendAmount: nil),
        .terraClassic: ExpectedConfig(name: "TerraClassic", ticker: "ULUNC", feeUnit: "uluna", swapAsset: "LUNC", logo: "lunc", chainID: nil, coinType: .terra, chainType: .Cosmos, banxaBlockchainCode: "LUNC", minimumSendAmount: nil),
        .noble: ExpectedConfig(name: "Noble", ticker: "UUSDC", feeUnit: "uusdc", swapAsset: "USDC", logo: "noble", chainID: nil, coinType: .noble, chainType: .Cosmos, banxaBlockchainCode: "NOBLE", minimumSendAmount: nil),
        .ripple: ExpectedConfig(name: "Ripple", ticker: "XRP", feeUnit: "XRP", swapAsset: "XRP", logo: "xrp", chainID: nil, coinType: .xrp, chainType: .Ripple, banxaBlockchainCode: "XRP", minimumSendAmount: nil),
        .akash: ExpectedConfig(name: "Akash", ticker: "UAKT", feeUnit: "uakt", swapAsset: "AKT", logo: "akash", chainID: nil, coinType: .akash, chainType: .Cosmos, banxaBlockchainCode: "AKASH", minimumSendAmount: nil),
        .tron: ExpectedConfig(name: "Tron", ticker: "TRX", feeUnit: "TRX", swapAsset: "TRON", logo: "tron", chainID: nil, coinType: .tron, chainType: .Tron, banxaBlockchainCode: "TRON", minimumSendAmount: nil),
        .ethereumSepolia: ExpectedConfig(name: "Ethereum-Sepolia", ticker: "ETH", feeUnit: "Gwei", swapAsset: "ETH", logo: "eth", chainID: 11_155_111, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "ETH", minimumSendAmount: nil),
        .zcash: ExpectedConfig(name: "Zcash", ticker: "ZEC", feeUnit: "ZEC/vbyte", swapAsset: "ZEC", logo: "zec", chainID: nil, coinType: .zcash, chainType: .UTXO, banxaBlockchainCode: "ZEC", minimumSendAmount: nil),
        .mantle: ExpectedConfig(name: "Mantle", ticker: "MNT", feeUnit: "Gwei", swapAsset: "MANTLE", logo: "mantle", chainID: 5000, coinType: .mantle, chainType: .EVM, banxaBlockchainCode: "MNT", minimumSendAmount: nil),
        .hyperliquid: ExpectedConfig(name: "Hyperliquid", ticker: "HYPE", feeUnit: "Gwei", swapAsset: "HYPE", logo: "hyperliquid", chainID: 999, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "HYPE", minimumSendAmount: nil),
        .sei: ExpectedConfig(name: "Sei", ticker: "SEI", feeUnit: "Gwei", swapAsset: "SEI", logo: "sei", chainID: 1329, coinType: .ethereum, chainType: .EVM, banxaBlockchainCode: "SEI", minimumSendAmount: nil),
        .qbtc: ExpectedConfig(name: "QBTC", ticker: "QBTC", feeUnit: "qbtc", swapAsset: "QBTC", logo: "qbtc", chainID: nil, coinType: .cosmos, chainType: .Cosmos, banxaBlockchainCode: "QBTC", minimumSendAmount: nil),
        .bittensor: ExpectedConfig(name: "Bittensor", ticker: "TAO", feeUnit: "RAO", swapAsset: "TAO", logo: "bittensor", chainID: nil, coinType: .polkadot, chainType: .Polkadot, banxaBlockchainCode: "TAO", minimumSendAmount: nil)
    ]

    // MARK: - Coverage guard

    func testExpectedTableCoversEveryChain() {
        let covered = Set(Self.expected.keys)
        let all = Set(Chain.allCases)
        let missing = all.subtracting(covered)
        let extra = covered.subtracting(all)

        XCTAssertTrue(
            missing.isEmpty,
            "Chain case(s) missing from the parity ledger: \(missing). Add a row (and a ChainConfig row)."
        )
        XCTAssertTrue(extra.isEmpty, "Parity ledger references unknown Chain case(s): \(extra).")
        XCTAssertEqual(Chain.allCases.count, Self.expected.count, "Parity ledger drifted from Chain.allCases.count.")
        XCTAssertEqual(Chain.allCases.count, 42, "Expected 42 chains; update this test if the roster changed intentionally.")
    }

    // MARK: - Per-accessor parity (all 42 chains)

    func testNameParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.name, expected.name, "name mismatch for \(chain)")
        }
    }

    func testTickerParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.ticker, expected.ticker, "ticker mismatch for \(chain)")
        }
    }

    func testFeeUnitParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.feeUnit, expected.feeUnit, "feeUnit mismatch for \(chain)")
        }
    }

    func testSwapAssetParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.swapAsset, expected.swapAsset, "swapAsset mismatch for \(chain)")
        }
    }

    func testLogoParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.logo, expected.logo, "logo mismatch for \(chain)")
        }
    }

    func testChainIDParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.chainID, expected.chainID, "chainID mismatch for \(chain)")
        }
    }

    func testCoinTypeParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.coinType, expected.coinType, "coinType mismatch for \(chain)")
        }
    }

    func testChainTypeParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.chainType, expected.chainType, "chainType mismatch for \(chain)")
        }
    }

    func testBanxaBlockchainCodeParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.banxaBlockchainCode, expected.banxaBlockchainCode, "banxaBlockchainCode mismatch for \(chain)")
        }
    }

    func testMinimumSendAmountParity() {
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.minimumSendAmount, expected.minimumSendAmount, "minimumSendAmount mismatch for \(chain)")
        }
    }

    // MARK: - type is a single-source alias of chainType

    func testTypeAliasEqualsChainType() {
        for chain in Chain.allCases {
            XCTAssertEqual(chain.type, chain.chainType, "type/chainType diverged for \(chain)")
        }
        for (chain, expected) in Self.expected {
            XCTAssertEqual(chain.type, expected.chainType, "type mismatch for \(chain)")
        }
    }

    // MARK: - Spot checks: coinType mappings that are easy to get wrong
    //
    // These are the derivation-critical mappings where the chain name and the
    // WalletCore CoinType diverge — a regression here corrupts addresses.

    func testCoinTypeSpotChecks() {
        XCTAssertEqual(Chain.terra.coinType, .terraV2, "Terra (LUNA) must map to CoinType.terraV2")
        XCTAssertEqual(Chain.terraClassic.coinType, .terra, "TerraClassic (LUNC) must map to CoinType.terra")
        XCTAssertEqual(Chain.mayaChain.coinType, .thorchain, "MayaChain reuses CoinType.thorchain")
        XCTAssertEqual(Chain.avalanche.coinType, .avalancheCChain)
        XCTAssertEqual(Chain.bscChain.coinType, .smartChain)
        XCTAssertEqual(Chain.hyperliquid.coinType, .ethereum, "Hyperliquid derives via CoinType.ethereum")
        XCTAssertEqual(Chain.sei.coinType, .ethereum, "Sei derives via CoinType.ethereum")
        XCTAssertEqual(Chain.qbtc.coinType, .cosmos, "QBTC derives via CoinType.cosmos")
        XCTAssertEqual(Chain.bittensor.coinType, .polkadot, "Bittensor reuses CoinType.polkadot")
        XCTAssertEqual(Chain.ripple.coinType, .xrp)
    }

    // MARK: - minimumSendAmount: only Cardano has a floor

    func testOnlyCardanoHasMinimumSendAmount() {
        XCTAssertEqual(Chain.cardano.minimumSendAmount, CardanoHelper.defaultMinUTXOValue)
        for chain in Chain.allCases where chain != .cardano {
            XCTAssertNil(chain.minimumSendAmount, "\(chain) unexpectedly has a minimumSendAmount")
        }
    }
}
