//
//  JoinKeysignSwapFeeLabelTests.swift
//  VultisigAppTests
//
//  Pins which chain the co-signer's swap confirm keys its fee-row labels on:
//  the payload coin, the same coin `getCalculatedNetworkFee` prices the fee
//  on. An ERC-20 source is still an EVM fee, so it reads as a maximum.
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class JoinKeysignSwapFeeLabelTests: XCTestCase {

    func testSwapFeeLabelKeysAreMaximumForErc20Source() {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: "0xusdc")
        let vm = makeViewModel(payload: makePayload(
            coin: usdc,
            chainSpecific: .Ethereum(maxFeePerGasWei: 0, priorityFeeWei: 0, nonce: 0, gasLimit: 21000)
        ))

        XCTAssertEqual(vm.swapFeeLabelKeys, .maximum)
    }

    func testSwapFeeLabelKeysAreExactForThorchainSource() {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let vm = makeViewModel(payload: makePayload(
            coin: rune,
            chainSpecific: .THORChain(accountNumber: 0, sequence: 0, fee: 2_000_000, isDeposit: true)
        ))

        XCTAssertEqual(vm.swapFeeLabelKeys, .exact)
    }

    func testSwapFeeLabelKeysAreExactWithoutPayload() {
        XCTAssertEqual(JoinKeysignViewModel().swapFeeLabelKeys, .exact)
    }

    // MARK: - Helpers

    private func makeViewModel(payload: KeysignPayload) -> JoinKeysignViewModel {
        let vm = JoinKeysignViewModel()
        vm.keysignPayload = payload
        return vm
    }

    private func makePayload(coin: Coin, chainSpecific: BlockChainSpecific) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "recipient",
            toAmount: BigInt(1),
            chainSpecific: chainSpecific,
            utxos: [],
            memo: nil,
            swapPayload: nil,
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
}
