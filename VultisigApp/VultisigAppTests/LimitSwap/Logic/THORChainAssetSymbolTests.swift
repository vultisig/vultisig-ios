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
