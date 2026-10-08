//
//  EVMSwapTxGuardTests.swift
//  VultisigAppTests
//
//  Pins the router allowlist and tx.value bounds applied before an EVM
//  aggregator swap is signed. Mirrors the Android `EvmSwapTxGuard` and the
//  SDK `knownAggregatorRouters` so every platform refuses the same payloads.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class EVMSwapTxGuardTests: XCTestCase {

    private let oneInchV6 = "0x111111125421ca6dc452d289314280a0f8842a65"
    private let oneInchV5 = "0x1111111254eeb25477b68fb85ed929f73a960582"
    private let oneInchZkSync = "0x6fd4383cb451173d5f9304f041c7bcbf27d561ff"
    private let oneInchRobinhood = "0x5a705de8982235a7fa45bb83dcacf03a211389c7"
    private let kyber = "0x6131b5fae19ea4f9d964eac0408e4408b66337b5"
    private let lifi = "0x1231deb6f5749ef6ce6943a275a1d3e7486f4eae"
    private let lifiHyperliquid = "0x0a0758d937d1059c356d4714e57f5df0239bce1a"
    private let lifiRobinhood = "0xb477751b76cf82d00a686a1232f5fcd772414af3"
    private let lifiZkSync = "0x341e94069f53234fe6dabef707ad424830525715"
    private let attacker = "0x00000000000000000000000000000000deadbeef"

    // MARK: - 1inch routers

    func testOneInchAcceptsV6AndV5OnStandardChain() throws {
        try swapFor(payload(provider: .oneInch, to: oneInchV6))
        try swapFor(payload(provider: .oneInch, to: oneInchV5))
    }

    func testOneInchRouterComparisonIsCaseInsensitive() throws {
        try swapFor(payload(provider: .oneInch, to: oneInchV6.uppercased().replacingOccurrences(of: "0X", with: "0x")))
    }

    func testOneInchZkSyncRequiresItsOwnRouter() throws {
        try swapFor(payload(provider: .oneInch, chain: .zksync, to: oneInchZkSync))
        assertRouterRejected(payload(provider: .oneInch, chain: .zksync, to: oneInchV6))
    }

    func testOneInchRobinhoodRequiresItsOwnRouter() throws {
        try swapFor(payload(provider: .oneInch, chain: .robinhood, to: oneInchRobinhood))
        assertRouterRejected(payload(provider: .oneInch, chain: .robinhood, to: oneInchV6))
    }

    func testOneInchRejectsForeignRouter() {
        assertRouterRejected(payload(provider: .oneInch, to: attacker))
        assertRouterRejected(payload(provider: .oneInch, to: kyber))
    }

    // MARK: - Kyber routers

    func testKyberAcceptsItsRouterOnly() throws {
        try swapFor(payload(provider: .kyberSwap, to: kyber))
        assertRouterRejected(payload(provider: .kyberSwap, to: oneInchV6))
        assertRouterRejected(payload(provider: .kyberSwap, to: attacker))
    }

    // MARK: - LI.FI routers

    func testLiFiAcceptsDiamondOnStandardChain() throws {
        try swapFor(payload(provider: .lifi, to: lifi))
        assertRouterRejected(payload(provider: .lifi, to: attacker))
    }

    func testLiFiChainExceptionsRequireTheirOwnDiamond() throws {
        try swapFor(payload(provider: .lifi, chain: .hyperliquid, to: lifiHyperliquid))
        try swapFor(payload(provider: .lifi, chain: .robinhood, to: lifiRobinhood))
        try swapFor(payload(provider: .lifi, chain: .zksync, to: lifiZkSync))
        assertRouterRejected(payload(provider: .lifi, chain: .hyperliquid, to: lifi))
        assertRouterRejected(payload(provider: .lifi, chain: .robinhood, to: lifi))
        assertRouterRejected(payload(provider: .lifi, chain: .zksync, to: lifi))
    }

    // MARK: - SwapKit and providers

    func testSwapKitIsExemptFromRouterPin() throws {
        try swapFor(payload(provider: .swapkit, to: attacker))
    }

    func testUnrecognizedProviderIsRejected() {
        let swap = payload(provider: .unknown("shadyswap"), to: oneInchV6)
        XCTAssertThrowsError(try EVMSwapTxGuard.check(swap)) {
            XCTAssertEqual($0 as? EVMSwapTxGuardError, .unrecognizedProvider("shadyswap"))
        }
    }

    func testJupiterOnEvmChainIsRejected() {
        assertRouterRejected(payload(provider: .jupiter, to: oneInchV6))
    }

    func testEmptyProviderAcceptsKnownRoutersOnly() throws {
        try swapFor(payload(provider: .unknown(""), to: oneInchV6))
        try swapFor(payload(provider: .unknown(""), to: kyber))
        try swapFor(payload(provider: .unknown(""), to: lifi))
        assertRouterRejected(payload(provider: .unknown(""), to: attacker))
    }

    func testEmptyProviderAimedAtExactValueRouterStillBoundsValue() {
        let swap = payload(provider: .unknown(""), to: oneInchV6, value: "2000000000000000000")
        XCTAssertThrowsError(try EVMSwapTxGuard.check(swap)) {
            guard case .valueExceedsQuotedAmount = $0 as? EVMSwapTxGuardError else {
                return XCTFail("Expected valueExceedsQuotedAmount, got \($0)")
            }
        }
    }

    // MARK: - Value bounds

    func testNativeSourceMayNotSendMoreThanQuotedAmount() throws {
        try swapFor(payload(provider: .oneInch, to: oneInchV6, value: "1000000000000000000"))
        try swapFor(payload(provider: .kyberSwap, to: kyber, value: "999"))
        for swap in [
            payload(provider: .oneInch, to: oneInchV6, value: "1000000000000000001"),
            payload(provider: .kyberSwap, to: kyber, value: "1000000000000000001")
        ] {
            XCTAssertThrowsError(try EVMSwapTxGuard.check(swap)) {
                XCTAssertEqual(
                    $0 as? EVMSwapTxGuardError,
                    .valueExceedsQuotedAmount(value: "1000000000000000001", quoted: "1000000000000000000")
                )
            }
        }
    }

    func testTokenSourceMustSendZeroNativeValue() throws {
        try swapFor(payload(provider: .oneInch, to: oneInchV6, native: false, value: "0"))
        try swapFor(payload(provider: .kyberSwap, to: kyber, native: false, value: "0"))
        for swap in [
            payload(provider: .oneInch, to: oneInchV6, native: false, value: "1"),
            payload(provider: .kyberSwap, to: kyber, native: false, value: "1")
        ] {
            XCTAssertThrowsError(try EVMSwapTxGuard.check(swap)) {
                XCTAssertEqual($0 as? EVMSwapTxGuardError, .valueFromTokenSource(value: "1"))
            }
        }
    }

    func testLiFiAndSwapKitMayAttachBridgeFeeAboveQuotedAmount() throws {
        try swapFor(payload(provider: .lifi, to: lifi, value: "5000000000000000000"))
        try swapFor(payload(provider: .swapkit, to: attacker, native: false, value: "5"))
    }

    // MARK: - Malformed value

    func testMalformedValueIsRejectedForEveryProvider() {
        for raw in ["", "abc", "-1", "0x10", "1.5", " 1"] {
            for provider in [SwapProviderId.oneInch, .kyberSwap, .lifi, .swapkit] {
                let swap = payload(provider: provider, to: oneInchV6, value: raw)
                XCTAssertThrowsError(try EVMSwapTxGuard.check(swap), "\(provider.rawValue) value '\(raw)'") {
                    XCTAssertEqual($0 as? EVMSwapTxGuardError, .malformedValue(raw))
                }
            }
        }
    }

    func testValueAboveUint256IsRejected() {
        let tooBig = String(BigUInt(1) << 256)
        let swap = payload(provider: .lifi, to: lifi, value: tooBig)
        XCTAssertThrowsError(try EVMSwapTxGuard.check(swap)) {
            XCTAssertEqual($0 as? EVMSwapTxGuardError, .malformedValue(tooBig))
        }
        let max = String((BigUInt(1) << 256) - 1)
        XCTAssertNoThrow(try EVMSwapTxGuard.check(payload(provider: .lifi, to: lifi, value: max)))
    }

    // MARK: - Signing entry point

    func testSigningCoinMustMatchPayloadSourceCoin() {
        let swap = payload(provider: .oneInch, to: oneInchV6)
        let token = payload(provider: .oneInch, to: oneInchV6, native: false).fromCoin
        let otherChain = payload(provider: .oneInch, chain: .base, to: oneInchV6).fromCoin
        for coin in [token, otherChain] {
            XCTAssertThrowsError(try messages(signing: swap, as: coin)) {
                guard case .coinMismatch? = $0 as? SwapPayloadError else { return XCTFail("\($0)") }
            }
        }
    }

    func testNonEvmPayloadCoinCannotSkipGuardForEvmSigningCoin() {
        let swap = payload(provider: .oneInch, chain: .bitcoin, to: attacker)
        let evmCoin = payload(provider: .oneInch, to: oneInchV6).fromCoin
        XCTAssertThrowsError(try messages(signing: swap, as: evmCoin)) {
            guard case .coinMismatch? = $0 as? SwapPayloadError else { return XCTFail("\($0)") }
        }
    }

    func testSigningCoinMustShareTokenContractWithPayloadSourceCoin() throws {
        let swap = payload(provider: .oneInch, to: oneInchV6, native: false)
        let otherToken = Coin(
            asset: CoinMeta(chain: .ethereum, ticker: "USDT", logo: "logo", decimals: 6, priceProviderId: "guard-usdt", contractAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7", isNativeToken: false),
            address: "0xFrom",
            hexPublicKey: ""
        )
        XCTAssertThrowsError(try messages(signing: swap, as: otherToken)) {
            guard case .coinMismatch? = $0 as? SwapPayloadError else { return XCTFail("\($0)") }
        }

        let sameTokenUppercased = Coin(
            asset: CoinMeta(chain: .ethereum, ticker: "USDC", logo: "logo", decimals: 6, priceProviderId: "guard-false", contractAddress: swap.fromCoin.contractAddress.uppercased(), isNativeToken: false),
            address: "0xFrom",
            hexPublicKey: ""
        )
        XCTAssertNoThrow(try SwapPayload.generic(swap).requireSellsSigningCoin(sameTokenUppercased))
    }

    func testNativeThorchainAndMayaSwapsMustSellSigningCoin() {
        let eth = payload(provider: .oneInch, to: oneInchV6).fromCoin
        let usdc = payload(provider: .oneInch, to: oneInchV6, native: false).fromCoin
        let base = payload(provider: .oneInch, chain: .base, to: oneInchV6).fromCoin
        let native = THORChainSwapPayload(
            fromAddress: eth.address, fromCoin: eth, toCoin: usdc, vaultAddress: "vault", routerAddress: nil,
            fromAmount: 1, toAmountDecimal: 1, toAmountLimit: "0", streamingInterval: "0",
            streamingQuantity: "0", expirationTime: 0, isAffiliate: false
        )
        for swap in [SwapPayload.thorchain(native), .thorchainChainnet(native), .thorchainStagenet(native), .mayachain(native)] {
            XCTAssertNoThrow(try swap.requireSellsSigningCoin(eth))
            for other in [usdc, base] {
                XCTAssertThrowsError(try swap.requireSellsSigningCoin(other)) {
                    guard case .coinMismatch? = $0 as? SwapPayloadError else { return XCTFail("\($0)") }
                }
            }
        }
    }

    func testSignerRefusesBeforeBuildingInputForBadRouter() {
        let swap = payload(provider: .oneInch, to: attacker)
        XCTAssertThrowsError(try OneInchSwaps().getPreSignedImageHash(payload: swap, keysignPayload: keysign(swap, coin: swap.fromCoin), nonceOffset: 0)) {
            guard case .unknownRouter = $0 as? EVMSwapTxGuardError else {
                return XCTFail("Expected unknownRouter, got \($0)")
            }
        }
    }

    // MARK: - Fixtures

    /// The co-signer's messages for `swap` signed as `coin`, built the way every
    /// signer builds them.
    private func messages(signing swap: GenericSwapPayload, as coin: Coin) throws -> [String] {
        try KeysignMessageFactory(payload: keysign(swap, coin: coin), vaultPubKeyEdDSA: "").getKeysignMessages()
    }

    private func keysign(_ swap: GenericSwapPayload, coin: Coin) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: swap.quote.tx.to,
            toAmount: swap.fromAmount,
            chainSpecific: .Ethereum(maxFeePerGasWei: 1, priorityFeeWei: 1, nonce: 0, gasLimit: 100_000),
            utxos: [],
            memo: nil,
            swapPayload: .generic(swap),
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func swapFor(_ swap: GenericSwapPayload) throws {
        try EVMSwapTxGuard.check(swap)
    }

    private func assertRouterRejected(_ swap: GenericSwapPayload, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try EVMSwapTxGuard.check(swap), file: file, line: line) {
            guard case .unknownRouter = $0 as? EVMSwapTxGuardError else {
                return XCTFail("Expected unknownRouter, got \($0)", file: file, line: line)
            }
        }
    }

    private func payload(
        provider: SwapProviderId,
        chain: Chain = .ethereum,
        to: String,
        native: Bool = true,
        value: String = "0"
    ) -> GenericSwapPayload {
        let fromCoin = Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: native ? "ETH" : "USDC",
                logo: "logo",
                decimals: native ? 18 : 6,
                priceProviderId: "guard-\(native)",
                contractAddress: native ? "" : "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                isNativeToken: native
            ),
            address: "0xFrom",
            hexPublicKey: ""
        )
        let toCoin = Coin(
            asset: CoinMeta(chain: chain, ticker: "DAI", logo: "logo", decimals: 18, priceProviderId: "guard-dai", contractAddress: "0x6b175474e89094c44da98b954eedeac495271d0f", isNativeToken: false),
            address: "0xFrom",
            hexPublicKey: ""
        )
        return GenericSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: BigInt("1000000000000000000"),
            toAmountDecimal: 3000,
            quote: EVMQuote(
                dstAmount: "3000000000",
                tx: EVMQuote.Transaction(from: "0xFrom", to: to, data: "0x", value: value, gasPrice: "1", gas: 100_000)
            ),
            provider: provider
        )
    }
}
