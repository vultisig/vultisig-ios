//
//  JoinKeysignGasSwapFeeTests.swift
//  VultisigAppTests
//
//  Pins the co-signer network-fee display for EVM aggregator swaps. The
//  transmitted `chainSpecific` carries the native-ETH gas floor (40,000), but
//  the transaction is SIGNED with `max(routeGas, gasLimit)` (see OneInchSwaps),
//  where the route gas wins. `JoinKeysignGasViewModel` must value the fee at the
//  signed gas, otherwise the co-signer under-reports the fee ~9x — the dangerous
//  direction (shows cheap, charges more).
//
//  A plain (non-swap) EVM send has no route gas and must keep valuing the fee at
//  `chainSpecific.fee` (maxFeePerGas x gasLimit).
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

    // MARK: - Helpers

    /// Mirrors the production formatting so the comparison is locale-independent:
    /// native ETH has 18 decimals (resolved from TokensStore), rounded down.
    private func expectedFeeCrypto(weiFee: BigInt) -> String {
        let amount = Decimal(weiFee) / pow(10, 18)
        return "\(amount.formatToDecimal(digits: 18)) ETH"
    }

    private func makeCoin(ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: .ethereum, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "0xtest-\(ticker)", hexPublicKey: "")
    }

    private func makeGenericSwapPayload(routeGas: Int64) -> SwapPayload {
        let quote = EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(
                from: "0xfrom",
                to: "0xrouter",
                data: "0xdeadbeef",
                value: "1000000000000000",
                gasPrice: "568000000",
                gas: routeGas
            )
        )
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
