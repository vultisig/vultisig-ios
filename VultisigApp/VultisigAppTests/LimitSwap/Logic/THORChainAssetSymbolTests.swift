//
//  THORChainAssetSymbolTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class THORChainAssetSymbolTests: XCTestCase {

    // MARK: - Native assets

    func testNativeBitcoinMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .bitcoin, ticker: "BTC", contractAddress: "", isNativeToken: true),
            "BTC.BTC"
        )
    }

    func testNativeEthereumMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .ethereum, ticker: "ETH", contractAddress: "", isNativeToken: true),
            "ETH.ETH"
        )
    }

    func testNativeRuneMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .thorChain, ticker: "RUNE", contractAddress: "", isNativeToken: true),
            "THOR.RUNE"
        )
    }

    func testNativeRuneOnChainnetUsesSamePrefix() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .thorChainChainnet, ticker: "RUNE", contractAddress: "", isNativeToken: true),
            "THOR.RUNE"
        )
    }

    func testNativeRuneOnStagenetUsesSamePrefix() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .thorChainStagenet, ticker: "RUNE", contractAddress: "", isNativeToken: true),
            "THOR.RUNE"
        )
    }

    func testNativeLitecoinMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .litecoin, ticker: "LTC", contractAddress: "", isNativeToken: true),
            "LTC.LTC"
        )
    }

    func testNativeDogecoinMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .dogecoin, ticker: "DOGE", contractAddress: "", isNativeToken: true),
            "DOGE.DOGE"
        )
    }

    func testNativeBitcoinCashMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .bitcoinCash, ticker: "BCH", contractAddress: "", isNativeToken: true),
            "BCH.BCH"
        )
    }

    func testNativeAvalancheMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .avalanche, ticker: "AVAX", contractAddress: "", isNativeToken: true),
            "AVAX.AVAX"
        )
    }

    func testNativeBnbOnBscMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .bscChain, ticker: "BNB", contractAddress: "", isNativeToken: true),
            "BSC.BNB"
        )
    }

    func testNativeAtomOnGaiaMemoAsset() {
        XCTAssertEqual(
            thorchainMemoAsset(chain: .gaiaChain, ticker: "ATOM", contractAddress: "", isNativeToken: true),
            "GAIA.ATOM"
        )
    }

    // MARK: - Tokens (last 6 chars of contract, uppercased)

    func testUsdcOnEthereumTokenMemoAsset() {
        // USDC contract: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 → suffix "606EB48"…
        // Take the last 6: "06EB48"
        XCTAssertEqual(
            thorchainMemoAsset(
                chain: .ethereum,
                ticker: "USDC",
                contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                isNativeToken: false
            ),
            "ETH.USDC-06EB48"
        )
    }

    func testUsdtOnEthereumTokenMemoAsset() {
        // USDT contract: 0xdAC17F958D2ee523a2206206994597C13D831ec7 → last 6: "831EC7"
        XCTAssertEqual(
            thorchainMemoAsset(
                chain: .ethereum,
                ticker: "USDT",
                contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                isNativeToken: false
            ),
            "ETH.USDT-831EC7"
        )
    }

    func testTokenSuffixIsUppercasedRegardlessOfInput() {
        XCTAssertEqual(
            thorchainMemoAsset(
                chain: .ethereum,
                ticker: "FOO",
                contractAddress: "0xabcdef0123456789abcdef0123456789abcdef01",
                isNativeToken: false
            ),
            "ETH.FOO-CDEF01"
        )
    }

    // MARK: - THOR secured assets (raw denom, matching Coin.swapAsset)

    func testThorSecuredAssetMemoUsesRawDenom() {
        // A THOR secured asset's denom (`<l1>-<symbol>-<contract>`) is the memo
        // asset verbatim — the same string Coin.swapAsset emits. Encoding it as a
        // normal token (`THOR.USDC-<last6>`) would target the wrong pool.
        let denom = "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        XCTAssertEqual(
            thorchainMemoAsset(chain: .thorChain, ticker: "USDC", contractAddress: denom, isNativeToken: false),
            denom
        )
    }

    func testThorSecuredAssetOnStagenetUsesRawDenom() {
        let denom = "btc-btc"
        XCTAssertEqual(
            thorchainMemoAsset(chain: .thorChainStagenet, ticker: "BTC", contractAddress: denom, isNativeToken: false),
            denom
        )
    }

    func testThorSecuredAssetMatchesCanonicalCoinSwapAsset() throws {
        // Parity with the canonical encoder the market path uses.
        let meta = CoinMeta(
            chain: .thorChain, ticker: "USDC",
            logo: "", decimals: 8,
            priceProviderId: "", contractAddress: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNativeToken: false
        )
        let coin = Coin(asset: meta, address: "thor1xyz", hexPublicKey: "")
        XCTAssertTrue(THORChainHelper.isSecuredAsset(coin: coin))
        XCTAssertEqual(thorchainMemoAsset(for: coin), coin.swapAsset)
    }

    func testEthereumTokenIsNotTreatedAsSecuredAsset() {
        // The secured-asset branch is THOR-only: an EVM token keeps the last-6 form.
        XCTAssertEqual(
            thorchainMemoAsset(
                chain: .ethereum, ticker: "USDC",
                contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", isNativeToken: false
            ),
            "ETH.USDC-06EB48"
        )
    }

    // MARK: - THOR-native L1 tokens (TCY / RUJI) — bare `THOR.<TICKER>`

    func testThorTcyTokenUsesBareThorPrefix() {
        // TCY is a non-native THOR token (denom "tcy") whose memo asset is
        // `THOR.TCY`, NOT the EVM last-6-of-contract suffix. Previously the
        // 3-char denom fell through the 6-char guard and returned nil — the
        // RUNE→TCY dead tap. THOR.TCY pool is Available on THORChain, so it's
        // genuinely placeable.
        XCTAssertEqual(
            thorchainMemoAsset(chain: .thorChain, ticker: "TCY", contractAddress: "tcy", isNativeToken: false),
            "THOR.TCY"
        )
    }

    func testThorNativeTokenMatchesCanonicalCoinSwapAsset() {
        // Parity with the canonical encoder the market path uses: a non-secured
        // THOR token encodes as `THOR.<TICKER>`.
        let meta = CoinMeta(
            chain: .thorChain, ticker: "TCY",
            logo: "", decimals: 8,
            priceProviderId: "", contractAddress: "tcy",
            isNativeToken: false
        )
        let coin = Coin(asset: meta, address: "thor1xyz", hexPublicKey: "")
        XCTAssertFalse(THORChainHelper.isSecuredAsset(coin: coin))
        XCTAssertEqual(coin.swapAsset, "THOR.TCY")
        XCTAssertEqual(thorchainMemoAsset(for: coin), coin.swapAsset)
    }

    // MARK: - Unsupported chains return nil

    func testSolanaIsNotRoutableInPhase1() {
        XCTAssertNil(
            thorchainMemoAsset(chain: .solana, ticker: "SOL", contractAddress: "", isNativeToken: true)
        )
    }

    func testPolkadotIsNotRoutableInPhase1() {
        XCTAssertNil(
            thorchainMemoAsset(chain: .polkadot, ticker: "DOT", contractAddress: "", isNativeToken: true)
        )
    }

    func testTronIsNotRoutableInPhase1() {
        XCTAssertNil(
            thorchainMemoAsset(chain: .tron, ticker: "TRX", contractAddress: "", isNativeToken: true)
        )
    }

    func testTonIsNotRoutableInPhase1() {
        XCTAssertNil(
            thorchainMemoAsset(chain: .ton, ticker: "TON", contractAddress: "", isNativeToken: true)
        )
    }

    func testRippleIsNotRoutableInPhase1() {
        XCTAssertNil(
            thorchainMemoAsset(chain: .ripple, ticker: "XRP", contractAddress: "", isNativeToken: true)
        )
    }

    func testCardanoIsNotRoutableInPhase1() {
        XCTAssertNil(
            thorchainMemoAsset(chain: .cardano, ticker: "ADA", contractAddress: "", isNativeToken: true)
        )
    }

    // MARK: - Malformed input is rejected

    func testEmptyOrWhitespaceTickerReturnsNil() {
        XCTAssertNil(thorchainMemoAsset(chain: .bitcoin, ticker: "", contractAddress: "", isNativeToken: true))
        XCTAssertNil(thorchainMemoAsset(chain: .bitcoin, ticker: "   ", contractAddress: "", isNativeToken: true))
    }

    func testTokenWithShortContractReturnsNil() {
        // A contract shorter than 6 chars can't form a valid 6-char suffix.
        XCTAssertNil(
            thorchainMemoAsset(chain: .ethereum, ticker: "X", contractAddress: "0xabc", isNativeToken: false)
        )
    }

    // MARK: - Reverse lookup: chainFromThorchainSymbol

    func testChainFromSymbolResolvesKnownChains() {
        XCTAssertEqual(chainFromThorchainSymbol("BTC"), .bitcoin)
        XCTAssertEqual(chainFromThorchainSymbol("ETH"), .ethereum)
        XCTAssertEqual(chainFromThorchainSymbol("eth"), .ethereum, "Case-insensitive")
        XCTAssertEqual(chainFromThorchainSymbol(" LTC "), .litecoin, "Trims whitespace")
    }

    func testChainFromSymbolThorPinsToMainnet() {
        // "THOR" matches three Chain cases; it must resolve to canonical mainnet.
        XCTAssertEqual(chainFromThorchainSymbol("THOR"), .thorChain)
    }

    func testChainFromSymbolUnknownOrEmptyReturnsNil() {
        XCTAssertNil(chainFromThorchainSymbol("XRP"))
        XCTAssertNil(chainFromThorchainSymbol(""))
        XCTAssertNil(chainFromThorchainSymbol("   "))
    }

    func testIsThorchainRoutable() {
        XCTAssertTrue(isThorchainRoutable(chain: .bitcoin))
        XCTAssertTrue(isThorchainRoutable(chain: .thorChain))
        XCTAssertFalse(isThorchainRoutable(chain: .solana))
    }
}
