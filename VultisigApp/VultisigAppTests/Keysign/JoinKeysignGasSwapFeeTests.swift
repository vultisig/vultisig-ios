//
//  JoinKeysignGasSwapFeeTests.swift
//  VultisigAppTests
//
//  Pins the co-signer network-fee display for EVM aggregator/SwapKit swaps.
//  The transaction is SIGNED with the `EVMSwapFee` reconciliation — quote gas
//  price bumped to the oracle ceiling, route gas floored by the transmitted
//  gasLimit (with the 600k zero-gas fallback) — and `JoinKeysignGasViewModel`
//  must value the fee identically, otherwise the co-signer under-reports the
//  fee (the dangerous direction: shows cheap, charges more). The equality
//  tests at the bottom pin initiator display == co-signer display for
//  identical inputs across every `.generic` provider, including SwapKit EVM.
//
//  A plain (non-swap) EVM send has no route gas and must keep valuing the fee
//  at `chainSpecific.fee` (maxFeePerGas x gasLimit).
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class JoinKeysignGasSwapFeeTests: XCTestCase {

    private let maxFeePerGasWei = BigInt(592_930_334) // 0.592930334 Gwei
    private let gasLimitFloor = BigInt(40_000)        // native-ETH swap floor in chainSpecific
    private let routeGas = BigInt(359_942)            // signed gasLimit per Etherscan

    func testGenericSwapFeeUsesSignedRouteGasNotTheFloor() {
        let payload = makeEvmPayload(
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: gasLimitFloor
            ),
            swapPayload: makeGenericSwapPayload(routeGas: Int64(routeGas))
        )

        let result = JoinKeysignGasViewModel().getCalculatedNetworkFee(payload: payload)

        XCTAssertEqual(
            result.feeCrypto,
            expectedFeeCrypto(weiFee: maxFeePerGasWei * routeGas),
            "Aggregator swap fee must be valued at the signed route gas (~0.000213 ETH)"
        )
        XCTAssertNotEqual(
            result.feeCrypto,
            expectedFeeCrypto(weiFee: maxFeePerGasWei * gasLimitFloor),
            "Fee must NOT be valued at the 40k gas floor (the buggy ~0.0000237 ETH)"
        )
    }

    func testNonSwapEvmFeeStillUsesChainSpecificFee() {
        let gasLimit = BigInt(21_000)
        let payload = makeEvmPayload(
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: gasLimit
            ),
            swapPayload: nil
        )

        let result = JoinKeysignGasViewModel().getCalculatedNetworkFee(payload: payload)

        XCTAssertEqual(
            result.feeCrypto,
            expectedFeeCrypto(weiFee: payload.chainSpecific.fee),
            "A plain EVM send has no route gas and must keep chainSpecific.fee (maxFee x gasLimit)"
        )
        XCTAssertEqual(payload.chainSpecific.fee, maxFeePerGasWei * gasLimit)
    }

    func testGenericSwapFeeUsesGasLimitWhenRouteGasBelowIt() {
        // Floor branch: when the transmitted gasLimit exceeds the route gas, the
        // fee must be valued at the larger gasLimit so the co-signer never
        // under-reports (`max(routeGas, gasLimit)`).
        let gasLimitAboveRoute = BigInt(500_000) // > routeGas (359,942)
        let payload = makeEvmPayload(
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: gasLimitAboveRoute
            ),
            swapPayload: makeGenericSwapPayload(routeGas: Int64(routeGas))
        )

        let result = JoinKeysignGasViewModel().getCalculatedNetworkFee(payload: payload)

        XCTAssertEqual(
            result.feeCrypto,
            expectedFeeCrypto(weiFee: maxFeePerGasWei * gasLimitAboveRoute),
            "When gasLimit exceeds routeGas the fee must be valued at gasLimit, not the route gas"
        )
    }

    func testGenericSwapFeeUsesQuoteGasPriceWhenAboveOracle() {
        // The signer takes max(quote gasPrice, maxFeePerGas); when a provider
        // prices ABOVE our oracle, the co-signer must value the fee at the
        // provider's gas price, not the smaller oracle ceiling.
        let quoteGasPrice = BigInt(2_000_000_000) // 2 Gwei > 0.593 Gwei oracle
        let payload = makeEvmPayload(
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: gasLimitFloor
            ),
            swapPayload: makeGenericSwapPayload(routeGas: Int64(routeGas), gasPrice: "2000000000")
        )

        let result = JoinKeysignGasViewModel().getCalculatedNetworkFee(payload: payload)

        XCTAssertEqual(
            result.feeCrypto,
            expectedFeeCrypto(weiFee: quoteGasPrice * routeGas),
            "A provider gas price above the oracle wins the signed max and must be displayed"
        )
    }

    func testGenericSwapFeeZeroRouteGasFallsBackToSignedDefault() {
        // The signer normalizes a zero route gas to the 600k default before the
        // gasLimit floor — the co-signer must reproduce that, not value the fee
        // at the bare floor.
        let payload = makeEvmPayload(
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: gasLimitFloor
            ),
            swapPayload: makeGenericSwapPayload(routeGas: 0)
        )

        let result = JoinKeysignGasViewModel().getCalculatedNetworkFee(payload: payload)

        XCTAssertEqual(
            result.feeCrypto,
            expectedFeeCrypto(weiFee: maxFeePerGasWei * BigInt(EVMHelper.defaultETHSwapGasUnit)),
            "A zero route gas is signed with the 600k default and must be displayed at it"
        )
    }

    // MARK: - Initiator/co-signer equality (identical inputs, same displayed fee)

    func testCosignerFeeMatchesInitiatorDisplayedFeeForAggregatorProviders() {
        let eth = makeCoin(ticker: "ETH", decimals: 18, isNative: true)
        let evmQuote = makeEVMQuote(routeGas: Int64(routeGas), gasPrice: "568000000")
        let quotes: [(String, SwapQuote)] = [
            ("oneinch", .oneinch(evmQuote, fee: nil)),
            ("kyberswap", .kyberswap(evmQuote, fee: nil)),
            ("lifi", .lifi(evmQuote, fee: nil, integratorFee: nil))
        ]

        for (name, quote) in quotes {
            let initiatorFeeWei = SwapCryptoLogic.displayedSwapNetworkFeeWei(
                quote: quote, feeCoin: eth, gas: maxFeePerGasWei, gasLimit: gasLimitFloor, fee: .zero
            )
            let payload = makeEvmPayload(
                chainSpecific: .Ethereum(
                    maxFeePerGasWei: maxFeePerGasWei,
                    priorityFeeWei: BigInt(1),
                    nonce: 0,
                    gasLimit: gasLimitFloor
                ),
                swapPayload: makeGenericSwapPayload(quote: evmQuote)
            )
            let cosigner = JoinKeysignGasViewModel().getCalculatedNetworkFee(payload: payload)

            XCTAssertEqual(
                cosigner.feeCrypto,
                expectedFeeCrypto(weiFee: initiatorFeeWei),
                "Initiator and co-signer must display the same network fee for \(name)"
            )
        }
    }

    func testCosignerFeeMatchesInitiatorDisplayedFeeForSwapKitEvm() throws {
        // The FLASHNET EVM fixture is a real captured SwapKit response (hex
        // gas/gasPrice). The initiator reads the raw response; the co-signer
        // reads the EVMQuote the payload builder bakes from it. Both must
        // reconcile to the same signed bond.
        let eth = makeCoin(ticker: "ETH", decimals: 18, isNative: true)
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-flashnet-evm-usdc-btc-swap"
        )
        let quote: SwapQuote = .swapkit(response, fee: nil, subProvider: "FLASHNET")

        let initiatorFeeWei = SwapCryptoLogic.displayedSwapNetworkFeeWei(
            quote: quote, feeCoin: eth, gas: maxFeePerGasWei, gasLimit: gasLimitFloor, fee: .zero
        )

        let evmQuote = try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)
        let payload = makeEvmPayload(
            chainSpecific: .Ethereum(
                maxFeePerGasWei: maxFeePerGasWei,
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: gasLimitFloor
            ),
            swapPayload: makeGenericSwapPayload(quote: evmQuote)
        )
        let cosigner = JoinKeysignGasViewModel().getCalculatedNetworkFee(payload: payload)

        XCTAssertEqual(
            cosigner.feeCrypto,
            expectedFeeCrypto(weiFee: initiatorFeeWei),
            "Initiator and co-signer must display the same network fee for SwapKit EVM routes"
        )
        // The fixture's 1 Gwei gasPrice is above the 0.593 Gwei oracle and its
        // 210k gas beats the 40k floor — pin the reconciled bond explicitly.
        XCTAssertEqual(initiatorFeeWei, BigInt(1_000_000_000) * BigInt(210_000))
    }

    // MARK: - Helpers

    /// Mirrors the production formatting so the comparison is locale-independent:
    /// native ETH has 18 decimals (resolved from TokensStore), rounded down.
    private func expectedFeeCrypto(weiFee: BigInt) -> String {
        let amount = (Decimal(string: weiFee.description) ?? .zero) / pow(10, 18)
        return "\(amount.formatToDecimal(digits: 18)) ETH"
    }

    private func makeCoin(ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: .ethereum, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "0xtest-\(ticker)", hexPublicKey: "")
    }

    private func makeEVMQuote(routeGas: Int64, gasPrice: String) -> EVMQuote {
        EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(
                from: "0xfrom",
                to: "0xrouter",
                data: "0xdeadbeef",
                value: "1000000000000000",
                gasPrice: gasPrice,
                gas: routeGas
            )
        )
    }

    private func makeGenericSwapPayload(routeGas: Int64, gasPrice: String = "568000000") -> SwapPayload {
        makeGenericSwapPayload(quote: makeEVMQuote(routeGas: routeGas, gasPrice: gasPrice))
    }

    private func makeGenericSwapPayload(quote: EVMQuote) -> SwapPayload {
        let generic = GenericSwapPayload(
            fromCoin: makeCoin(ticker: "ETH", decimals: 18, isNative: true),
            toCoin: makeCoin(ticker: "USDT", decimals: 6, isNative: false),
            fromAmount: BigInt(1_000_000_000_000_000),
            toAmountDecimal: Decimal(1),
            quote: quote,
            provider: .oneInch
        )
        return .generic(generic)
    }

    private func makeEvmPayload(chainSpecific: BlockChainSpecific, swapPayload: SwapPayload?) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(ticker: "ETH", decimals: 18, isNative: true),
            toAddress: "0xrouter",
            toAmount: BigInt(1_000_000_000_000_000),
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: swapPayload,
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
}
