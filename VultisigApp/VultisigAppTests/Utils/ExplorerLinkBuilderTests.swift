//
//  ExplorerLinkBuilderTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class ExplorerLinkBuilderTests: XCTestCase {

    private let mainnetChain = Chain.thorChain.rawValue
    private let stagenetChain = Chain.thorChainStagenet.rawValue
    private let fallback = "https://etherscan.io/tx/0xfallback"
    private let txHash = "0xABCDEF1234567890"

    // MARK: - Provider-specific routing

    func testLifiProviderReturnsLifiTracker() {
        let url = ExplorerLinkBuilder.url(
            provider: "LI.FI",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, "https://scan.li.fi/tx/\(txHash)")
    }

    func testMayaProviderReturnsMayaExplorer() {
        let url = ExplorerLinkBuilder.url(
            provider: "MayaChain",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        // Maya tracker strips the hex prefix.
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.explorer.mayachain.info/tx/ABCDEF1234567890"
        )
    }

    func testThorChainMainnetReturnsRuneScan() {
        let url = ExplorerLinkBuilder.url(
            provider: "THORChain",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        // RuneScan tracker strips the hex prefix.
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890"
        )
    }

    func testThorChainAliasWithChainnetChainRawValueReturnsChainnetTracker() {
        // Cross-chain swap *into* THORChain chainnet: provider is "THORChain"
        // but chainRawValue carries .thorChainChainnet. Must route to chainnet.
        let url = ExplorerLinkBuilder.url(
            provider: "THORChain",
            txHash: txHash,
            chainRawValue: Chain.thorChainChainnet.rawValue,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890?network=chainnet"
        )
    }

    func testThorChainStagenetReturnsStagenetRuneScan() {
        let url = ExplorerLinkBuilder.url(
            provider: "THORChain",
            txHash: txHash,
            chainRawValue: stagenetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890?network=stagenet"
        )
    }

    func testThorSwapAliasIsTreatedAsThorChain() {
        let url = ExplorerLinkBuilder.url(
            provider: "THORSwap",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890"
        )
    }

    // MARK: - Fallback behaviour

    func testUnknownProviderFallsBackToChainExplorer() {
        // chainRawValue resolves to .thorChain — fallback derives the URL from
        // ExplorerLinkBuilder.getExplorerURL, NOT the stored explorerLink, so it stays in
        // sync with the rest of the app even if the stored link is stale.
        let url = ExplorerLinkBuilder.url(
            provider: "1Inch",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            ExplorerLinkBuilder.getExplorerURL(chain: .thorChain, txid: txHash)
        )
    }

    func testKyberSwapFallsBackToChainExplorer() {
        let ethereumChain = Chain.ethereum.rawValue
        let url = ExplorerLinkBuilder.url(
            provider: "KyberSwap",
            txHash: txHash,
            chainRawValue: ethereumChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            ExplorerLinkBuilder.getExplorerURL(chain: .ethereum, txid: txHash)
        )
    }

    func testNilProviderFallsBackToChainExplorer() {
        let ethereumChain = Chain.ethereum.rawValue
        let url = ExplorerLinkBuilder.url(
            provider: nil,
            txHash: txHash,
            chainRawValue: ethereumChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            ExplorerLinkBuilder.getExplorerURL(chain: .ethereum, txid: txHash)
        )
    }

    func testUnresolvableChainRawValueFallsBackToStoredExplorerLink() {
        // Last-ditch safety net: if chainRawValue can't be parsed back to a
        // Chain (e.g. legacy data, deprecated chain), use the stored link.
        let url = ExplorerLinkBuilder.url(
            provider: nil,
            txHash: txHash,
            chainRawValue: "not-a-real-chain",
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, fallback)
    }

    // MARK: - Case- and spacing-insensitive matching

    func testLifiMatchingIsCaseInsensitive() {
        let variants = ["LI.FI", "li.fi", "Lifi", "LIFI", "Li.Fi", "li fi"]
        for variant in variants {
            let url = ExplorerLinkBuilder.url(
                provider: variant,
                txHash: txHash,
                chainRawValue: mainnetChain,
                fallbackExplorerLink: fallback
            )
            XCTAssertEqual(
                url?.absoluteString,
                "https://scan.li.fi/tx/\(txHash)",
                "Expected LiFi tracker for variant \(variant)"
            )
        }
    }

    func testThorChainMatchingIsCaseInsensitive() {
        let variants = ["thorchain", "THORCHAIN", "ThorChain", "THOR Chain"]
        for variant in variants {
            let url = ExplorerLinkBuilder.url(
                provider: variant,
                txHash: txHash,
                chainRawValue: mainnetChain,
                fallbackExplorerLink: fallback
            )
            XCTAssertEqual(
                url?.absoluteString,
                "https://runescan.io/tx/ABCDEF1234567890",
                "Expected RuneScan for variant \(variant)"
            )
        }
    }

    func testMayaMatchingIsCaseInsensitive() {
        let variants = ["maya", "MAYA", "Maya", "MayaChain", "maya chain"]
        for variant in variants {
            let url = ExplorerLinkBuilder.url(
                provider: variant,
                txHash: txHash,
                chainRawValue: mainnetChain,
                fallbackExplorerLink: fallback
            )
            XCTAssertEqual(
                url?.absoluteString,
                "https://www.explorer.mayachain.info/tx/ABCDEF1234567890",
                "Expected Maya explorer for variant \(variant)"
            )
        }
    }

    // MARK: - Real-world displayName / providerName values

    /// `SwapQuote.displayName` returns "Maya protocol" (lowercase p) and
    /// `SwapPayload.providerName` returns "Maya Protocol" (capital P). For a
    /// cross-chain swap (e.g. BTC→Maya) `chainRawValue` is the from-chain, so
    /// without an explicit alias the fallback would route to the wrong chain
    /// explorer (mempool.space for BTC). Lock the alias in.
    func testMayaProtocolDisplayNameRoutesToMayaExplorer() {
        let bitcoinChain = Chain.bitcoin.rawValue
        let lowercase = ExplorerLinkBuilder.url(
            provider: "Maya protocol",
            txHash: txHash,
            chainRawValue: bitcoinChain,
            fallbackExplorerLink: fallback
        )
        let capital = ExplorerLinkBuilder.url(
            provider: "Maya Protocol",
            txHash: txHash,
            chainRawValue: bitcoinChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            lowercase?.absoluteString,
            "https://www.explorer.mayachain.info/tx/ABCDEF1234567890"
        )
        XCTAssertEqual(
            capital?.absoluteString,
            "https://www.explorer.mayachain.info/tx/ABCDEF1234567890"
        )
    }

    func testThorChainStagenetDisplayNameRoutesToStagenetTracker() {
        // Stagenet alias must work even when chainRawValue isn't the stagenet
        // raw value (e.g. cross-chain stagenet swap).
        let url = ExplorerLinkBuilder.url(
            provider: "THORChain-Stagenet",
            txHash: txHash,
            chainRawValue: Chain.bitcoin.rawValue,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890?network=stagenet"
        )
    }

    func testThorChainChainnetDisplayNameRoutesToChainnetTracker() {
        let url = ExplorerLinkBuilder.url(
            provider: "THORChain-Chainnet",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890?network=chainnet"
        )
    }

    // MARK: - Chain coverage (regression guard)

    /// Every Chain case must produce a non-empty transaction URL. This catches
    /// the case where a new Chain is added to the enum without a corresponding
    /// `getExplorerURL` arm — previously silent because the switch is exhaustive
    /// but a forgotten arm could return the empty string and ship without
    /// complaint.
    func testGetExplorerURLProducesNonEmptyURLForEveryChain() {
        for chain in Chain.allCases {
            let url = ExplorerLinkBuilder.getExplorerURL(chain: chain, txid: txHash)
            XCTAssertFalse(
                url.isEmpty,
                "Chain \(chain.rawValue) returned an empty transaction URL"
            )
        }
    }

    func testGetExplorerURLReturnsQbtcExplorerURL() {
        XCTAssertEqual(
            ExplorerLinkBuilder.getExplorerURL(chain: .qbtc, txid: txHash),
            "https://explorer.qbtc.net/qbtc/tx/\(txHash)"
        )
    }

    func testGetExplorerByAddressURLProducesNonEmptyURLForEveryChain() {
        let address = "test-address"
        for chain in Chain.allCases {
            let url = ExplorerLinkBuilder.getExplorerByAddressURL(chain: chain, address: address)
            XCTAssertNotNil(url, "Chain \(chain.rawValue) returned nil for address URL")
            XCTAssertFalse(
                url?.isEmpty ?? true,
                "Chain \(chain.rawValue) returned an empty address URL"
            )
        }
    }

    func testGetExplorerByAddressURLReturnsQbtcExplorerURL() {
        XCTAssertEqual(
            ExplorerLinkBuilder.getExplorerByAddressURL(chain: .qbtc, address: "addr"),
            "https://explorer.qbtc.net/qbtc/account/addr"
        )
    }

    // MARK: - Registry parity (behaviour-preserving refactor)

    /// Expected URLs captured from the pre-refactor `switch` statements, so the
    /// table-driven registry can be asserted byte-for-byte against them.
    /// `token` is the `Endpoint.getExplorerByCoinURL` result for a *non-native*
    /// token (holder address = `Self.sampleAddress`, contract = `Self.sampleContract`).
    private struct ExplorerExpectation {
        let tx: String
        let address: String
        let token: String?
    }

    private static let sampleTx = "0xDEADBEEF"
    private static let sampleAddress = "ADDR"
    private static let sampleContract = "CONTRACT"

    // swiftlint:disable:next line_length
    private static let expectations: [Chain: ExplorerExpectation] = [
        .bitcoin: .init(tx: "https://mempool.space/tx/0xDEADBEEF", address: "https://mempool.space/address/ADDR", token: "https://mempool.space/address/ADDR"),
        .bitcoinCash: .init(tx: "https://blockchair.com/bitcoin-cash/transaction/0xDEADBEEF", address: "https://blockchair.com/bitcoin-cash/address/ADDR", token: "https://blockchair.com/bitcoin-cash/address/ADDR"),
        .litecoin: .init(tx: "https://blockchair.com/litecoin/transaction/0xDEADBEEF", address: "https://blockchair.com/litecoin/address/ADDR", token: "https://blockchair.com/litecoin/address/ADDR"),
        .dogecoin: .init(tx: "https://blockchair.com/dogecoin/transaction/0xDEADBEEF", address: "https://blockchair.com/dogecoin/address/ADDR", token: "https://blockchair.com/dogecoin/address/ADDR"),
        .dash: .init(tx: "https://blockchair.com/dash/transaction/0xDEADBEEF", address: "https://blockchair.com/dash/address/ADDR", token: "https://blockchair.com/dash/address/ADDR"),
        .zcash: .init(tx: "https://blockchair.com/zcash/transaction/0xDEADBEEF", address: "https://blockchair.com/zcash/address/ADDR", token: "https://blockchair.com/zcash/address/ADDR"),
        .thorChain: .init(tx: "https://runescan.io/tx/DEADBEEF", address: "https://runescan.io/address/ADDR", token: "https://runescan.io/address/ADDR"),
        .thorChainChainnet: .init(tx: "https://runescan.io/tx/DEADBEEF?network=chainnet", address: "https://runescan.io/address/ADDR?network=chainnet", token: "https://runescan.io/address/ADDR?network=chainnet"),
        .thorChainStagenet: .init(tx: "https://runescan.io/tx/DEADBEEF?network=stagenet", address: "https://runescan.io/address/ADDR?network=stagenet", token: "https://runescan.io/address/ADDR?network=stagenet"),
        .solana: .init(tx: "https://orb.helius.dev/tx/0xDEADBEEF", address: "https://orb.helius.dev/address/ADDR", token: "https://orb.helius.dev/address/CONTRACT"),
        .ethereum: .init(tx: "https://etherscan.io/tx/0xDEADBEEF", address: "https://etherscan.io/address/ADDR", token: "https://etherscan.io/token/CONTRACT"),
        .ethereumSepolia: .init(tx: "https://sepolia.etherscan.io/tx/0xDEADBEEF", address: "https://sepolia.etherscan.io/address/ADDR", token: "https://sepolia.etherscan.io/token/CONTRACT"),
        .gaiaChain: .init(tx: "https://www.mintscan.io/cosmos/tx/0xDEADBEEF", address: "https://www.mintscan.io/cosmos/address/ADDR", token: "https://www.mintscan.io/cosmos/address/ADDR"),
        .dydx: .init(tx: "https://www.mintscan.io/dydx/tx/0xDEADBEEF", address: "https://www.mintscan.io/dydx/address/ADDR", token: "https://www.mintscan.io/dydx/address/ADDR"),
        .kujira: .init(tx: "https://finder.kujira.network/kaiyo-1/tx/0xDEADBEEF", address: "https://finder.kujira.network/kaiyo-1/address/ADDR", token: "https://finder.kujira.network/kaiyo-1/address/ADDR"),
        .avalanche: .init(tx: "https://snowtrace.io/tx/0xDEADBEEF", address: "https://snowtrace.io/address/ADDR", token: "https://snowtrace.io/token/CONTRACT"),
        .bscChain: .init(tx: "https://bscscan.com/tx/0xDEADBEEF", address: "https://bscscan.com/address/ADDR", token: "https://bscscan.com/token/CONTRACT"),
        .mayaChain: .init(tx: "https://www.explorer.mayachain.info/tx/0xDEADBEEF", address: "https://www.explorer.mayachain.info/address/ADDR", token: "https://www.explorer.mayachain.info/address/ADDR"),
        .arbitrum: .init(tx: "https://arbiscan.io/tx/0xDEADBEEF", address: "https://arbiscan.io/address/ADDR", token: "https://arbiscan.io/token/CONTRACT"),
        .base: .init(tx: "https://basescan.org/tx/0xDEADBEEF", address: "https://basescan.org/address/ADDR", token: "https://basescan.org/token/CONTRACT"),
        .optimism: .init(tx: "https://optimistic.etherscan.io/tx/0xDEADBEEF", address: "https://optimistic.etherscan.io/address/ADDR", token: "https://optimistic.etherscan.io/token/CONTRACT"),
        .polygon: .init(tx: "https://polygonscan.com/tx/0xDEADBEEF", address: "https://polygonscan.com/address/ADDR", token: "https://polygonscan.com/token/CONTRACT"),
        .polygonV2: .init(tx: "https://polygonscan.com/tx/0xDEADBEEF", address: "https://polygonscan.com/address/ADDR", token: "https://polygonscan.com/token/CONTRACT"),
        .blast: .init(tx: "https://blastscan.io/tx/0xDEADBEEF", address: "https://blastscan.io/address/ADDR", token: "https://blastscan.io/token/CONTRACT"),
        .cronosChain: .init(tx: "https://cronoscan.com/tx/0xDEADBEEF", address: "https://cronoscan.com/address/ADDR", token: "https://cronoscan.com/token/CONTRACT"),
        .sui: .init(tx: "https://suiscan.xyz/mainnet/tx/0xDEADBEEF", address: "https://suiscan.xyz/mainnet/address/ADDR", token: "https://suiscan.xyz/mainnet/coin/CONTRACT"),
        .polkadot: .init(tx: "https://assethub-polkadot.subscan.io/extrinsic/0xDEADBEEF", address: "https://assethub-polkadot.subscan.io/account/ADDR", token: "https://assethub-polkadot.subscan.io/account/ADDR"),
        .bittensor: .init(tx: "https://taostats.io/extrinsic/0xDEADBEEF", address: "https://taostats.io/account/ADDR", token: "https://taostats.io/account/ADDR"),
        .zksync: .init(tx: "https://explorer.zksync.io/tx/0xDEADBEEF", address: "https://explorer.zksync.io/address/ADDR", token: "https://explorer.zksync.io/token/CONTRACT"),
        .ton: .init(tx: "https://tonviewer.com/transaction/0xDEADBEEF", address: "https://tonviewer.com/ADDR", token: "https://tonviewer.com/CONTRACT"),
        .osmosis: .init(tx: "https://www.mintscan.io/osmosis/tx/0xDEADBEEF", address: "https://www.mintscan.io/osmosis/address/ADDR", token: "https://www.mintscan.io/osmosis/address/ADDR"),
        .terra: .init(tx: "https://www.mintscan.io/terra/tx/0xDEADBEEF", address: "https://www.mintscan.io/terra/address/ADDR", token: "https://www.mintscan.io/terra/address/ADDR"),
        .terraClassic: .init(tx: "https://finder.terra.money/classic/tx/0xDEADBEEF", address: "https://finder.terra.money/classic/address/ADDR", token: "https://finder.terra.money/classic/address/ADDR"),
        .noble: .init(tx: "https://www.mintscan.io/noble/tx/0xDEADBEEF", address: "https://www.mintscan.io/noble/address/ADDR", token: "https://www.mintscan.io/noble/address/ADDR"),
        .ripple: .init(tx: "https://xrpscan.com/tx/0xDEADBEEF", address: "https://xrpscan.com/account/ADDR", token: "https://xrpscan.com/account/ADDR"),
        .akash: .init(tx: "https://www.mintscan.io/akash/tx/0xDEADBEEF", address: "https://www.mintscan.io/akash/address/ADDR", token: "https://www.mintscan.io/akash/address/ADDR"),
        .tron: .init(tx: "https://tronscan.org/#/transaction/0xDEADBEEF", address: "https://tronscan.org/#/address/ADDR", token: "https://tronscan.org/#/token20/CONTRACT"),
        .cardano: .init(tx: "https://cardanoscan.io/transaction/0xDEADBEEF", address: "https://cardanoscan.io/address/ADDR", token: "https://cardanoscan.io/token/CONTRACT"),
        .mantle: .init(tx: "https://explorer.mantle.xyz/tx/0xDEADBEEF", address: "https://mantlescan.xyz/address/ADDR", token: "https://mantlescan.xyz/token/CONTRACT"),
        .hyperliquid: .init(tx: "https://hypurrscan.io/tx/0xDEADBEEF", address: "https://hypurrscan.io/address/ADDR", token: "https://hypurrscan.io/token/CONTRACT"),
        .sei: .init(tx: "https://seiscan.io/tx/0xDEADBEEF", address: "https://seiscan.io/address/ADDR", token: "https://seiscan.io/token/CONTRACT"),
        .qbtc: .init(tx: "https://explorer.qbtc.net/qbtc/tx/0xDEADBEEF", address: "https://explorer.qbtc.net/qbtc/account/ADDR", token: nil)
    ]

    private func makeNonNativeCoin(chain: Chain) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: "TKN",
            logo: "logo",
            decimals: 8,
            priceProviderId: "tkn",
            contractAddress: Self.sampleContract,
            isNativeToken: false
        )
        return Coin(asset: asset, address: Self.sampleAddress, hexPublicKey: "")
    }

    /// The expectation table must stay exhaustive so the parametric assertions
    /// below actually cover every chain and the registry never falls through to
    /// the empty-string fallback in `getExplorerURL`.
    func testExpectationsCoverEveryChain() {
        for chain in Chain.allCases {
            XCTAssertNotNil(
                Self.expectations[chain],
                "Missing expected explorer URLs for \(chain.rawValue)"
            )
            XCTAssertNotNil(
                ExplorerLinkBuilder.explorers[chain],
                "Missing registry entry for \(chain.rawValue)"
            )
        }
    }

    func testEveryChainTransactionURLMatchesPreRefactorOutput() {
        for chain in Chain.allCases {
            guard let expected = Self.expectations[chain] else { continue }
            XCTAssertEqual(
                ExplorerLinkBuilder.getExplorerURL(chain: chain, txid: Self.sampleTx),
                expected.tx,
                "tx URL drifted for \(chain.rawValue)"
            )
        }
    }

    func testEveryChainAddressURLMatchesPreRefactorOutput() {
        for chain in Chain.allCases {
            guard let expected = Self.expectations[chain] else { continue }
            XCTAssertEqual(
                ExplorerLinkBuilder.getExplorerByAddressURL(chain: chain, address: Self.sampleAddress),
                expected.address,
                "address URL drifted for \(chain.rawValue)"
            )
        }
    }

    func testEveryChainTokenURLMatchesPreRefactorOutput() {
        for chain in Chain.allCases {
            guard let expected = Self.expectations[chain] else { continue }
            let coin = makeNonNativeCoin(chain: chain)
            XCTAssertEqual(
                Endpoint.getExplorerByCoinURL(coin: coin),
                expected.token,
                "token URL drifted for \(chain.rawValue)"
            )
        }
    }

    /// `getExplorerByAddressURLByGroup` is now a thin delegate over
    /// `getExplorerByAddressURL`, so it must agree for every chain (this also
    /// pins the Bitcoin Cash consistency fix — it previously drifted onto
    /// `explorer.bitcoin.com/bch`).
    func testAddressURLByGroupMatchesAddressURLForEveryChain() {
        for chain in Chain.allCases {
            XCTAssertEqual(
                Endpoint.getExplorerByAddressURLByGroup(chain: chain, address: Self.sampleAddress),
                ExplorerLinkBuilder.getExplorerByAddressURL(chain: chain, address: Self.sampleAddress),
                "byGroup/byAddress mismatch for \(chain.rawValue)"
            )
        }
    }

    func testAddressURLByGroupReturnsNilForNilChain() {
        XCTAssertNil(Endpoint.getExplorerByAddressURLByGroup(chain: nil, address: Self.sampleAddress))
    }

    // MARK: - Bitcoin Cash consistency (supersedes the explorer.bitcoin.com drift)

    /// Bitcoin Cash must resolve to blockchair.com for the transaction page and
    /// for BOTH address lookups (`getExplorerByAddressURL` and the grouped
    /// variant), matching every other UTXO chain.
    func testBitcoinCashResolvesToBlockchairForTxAndBothAddressPaths() {
        let tx = ExplorerLinkBuilder.getExplorerURL(chain: .bitcoinCash, txid: Self.sampleTx)
        let address = ExplorerLinkBuilder.getExplorerByAddressURL(chain: .bitcoinCash, address: Self.sampleAddress)
        let grouped = Endpoint.getExplorerByAddressURLByGroup(chain: .bitcoinCash, address: Self.sampleAddress)

        XCTAssertEqual(tx, "https://blockchair.com/bitcoin-cash/transaction/0xDEADBEEF")
        XCTAssertEqual(address, "https://blockchair.com/bitcoin-cash/address/ADDR")
        XCTAssertEqual(grouped, "https://blockchair.com/bitcoin-cash/address/ADDR")

        for url in [tx, address, grouped].compactMap({ $0 }) {
            XCTAssertTrue(
                url.hasPrefix("https://blockchair.com/"),
                "Bitcoin Cash URL should be on blockchair.com, got \(url)"
            )
        }
        XCTAssertFalse(
            (grouped ?? "").contains("explorer.bitcoin.com"),
            "Bitcoin Cash grouped address URL must no longer use explorer.bitcoin.com"
        )
    }
}
