//
//  JoinKeysignAmountFiatTests.swift
//  VultisigAppTests
//
//  Pins `JoinKeysignViewModel.getAmountFiat()` — the co-sign "Send overview"
//  amount fiat that renders under the send amount, consistent with the network
//  fee. Display-only: `getAmountFiat` derives from the already-signed
//  `toAmount` + the shared `RateProvider` price and never affects signing
//  bytes. The helper must produce a fiat string only for a plain, priced coin
//  send and stay empty for swaps, contract-call/approval decodes, zero-value
//  sends, and coins without a rate — so nothing misleading renders.
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class JoinKeysignAmountFiatTests: XCTestCase {

    func testAmountFiatUsesCoinPriceAndAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        // 3 ETH at $2 = $6.
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("3000000000000000000")))

        let fiat = vm.getAmountFiat()
        XCTAssertFalse(fiat.isEmpty, "A seeded rate should produce a fiat string")
        XCTAssertTrue(fiat.contains("6"), "3 ETH at $2 should render as 6, got \(fiat)")
    }

    func testAmountFiatScalesWithAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        // 5 ETH at $2 = $10.
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("5000000000000000000")))

        let fiat = vm.getAmountFiat()
        XCTAssertTrue(fiat.contains("10"), "5 ETH at $2 should render as 10, got \(fiat)")
    }

    func testAmountFiatEmptyWithoutRate() {
        // Unique ticker → unique priceProviderId that nothing seeds a rate for.
        let coin = makeCoin(.ethereum, ticker: "NORATEZZ", decimals: 18, isNative: true)
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("1000000000000000000")))
        XCTAssertEqual(vm.getAmountFiat(), "", "No rate → empty, never a misleading $0.00")
    }

    func testAmountFiatEmptyForZeroAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: 0))
        XCTAssertEqual(vm.getAmountFiat(), "", "A zero-value send maps to no meaningful fiat")
    }

    func testAmountFiatEmptyForContractCallTokenDisplay() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("3000000000000000000")))
        // A resolved contract-call / approval token display means the amount row
        // shows a decoded token, not the native coin transfer.
        vm.decodedTokenDisplay = "0.3 USDC"
        XCTAssertEqual(vm.getAmountFiat(), "", "Contract-call decodes carry their own display, not amount fiat")
    }

    func testAmountFiatEmptyForSwap() {
        let from = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: from)
        let swap = SwapPayload.generic(makeGenericSwapPayload(from: from))
        let vm = makeViewModel(payload: makePayload(
            coin: from,
            toAmount: BigInt("3000000000000000000"),
            swapPayload: swap
        ))
        XCTAssertEqual(vm.getAmountFiat(), "", "Swaps show fiat on the hero from/to rows, not the amount field")
    }

    // MARK: - Helpers

    private func makeViewModel(payload: KeysignPayload) -> JoinKeysignViewModel {
        let vm = JoinKeysignViewModel()
        vm.keysignPayload = payload
        return vm
    }

    private func makePayload(coin: Coin, toAmount: BigInt, swapPayload: SwapPayload? = nil) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "0xrecipient",
            toAmount: toAmount,
            chainSpecific: .Ethereum(maxFeePerGasWei: 0, priorityFeeWei: 0, nonce: 0, gasLimit: 21000),
            utxos: [],
            memo: nil,
            swapPayload: swapPayload,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
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

    private func makeGenericSwapPayload(from: Coin) -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: from,
            toCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: "0xusdc"),
            fromAmount: BigInt("3000000000000000000"),
            toAmountDecimal: 3000,
            quote: EVMQuote(
                dstAmount: "3000000000",
                tx: EVMQuote.Transaction(
                    from: "0xFrom",
                    to: "0xRouter",
                    data: "0x",
                    value: "0",
                    gasPrice: "1",
                    gas: 100_000,
                    swapFee: "0",
                    swapFeeTokenContract: ""
                )
            ),
            provider: .oneInch,
            swapFeeChain: nil,
            swapFeeTokenId: nil,
            swapFeeDecimals: nil
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, contract: String = "") -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "test-\(ticker)", hexPublicKey: "")
    }

    private func setPrice(_ value: Double, for coin: Coin) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        try? RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
        ])
    }
}
