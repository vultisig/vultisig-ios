import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class TransactionActivityEligibilityTests: XCTestCase {
    func testOrdinaryEvmTransferIsEligibleButContractAndUnbroadcastShapesAreNot() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload()))
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(memo: "0xa9059cbb")))
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(skipBroadcast: true)))
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(qbtc: true)))
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(maxSend: true)))
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(memo: "=<:ETH.ETH:recipient:100")))
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(memo: "m=<:hash:0")))
    }

    func testUnsupportedMarketSwapAndApprovalCannotMasqueradeAsSend() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let approval = ERC20ApprovePayload(amount: BigInt(1), spender: "contract")
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(approve: approval)))
        let coin = SendFormFixture.makeBTC()
        let nativeSwap = THORChainSwapPayload(fromAddress: "from", fromCoin: coin, toCoin: SendFormFixture.makeETH(),
                                              vaultAddress: "vault", routerAddress: nil, fromAmount: 1,
                                              toAmountDecimal: 1, toAmountLimit: "1", streamingInterval: "0",
                                              streamingQuantity: "0", expirationTime: 1, isAffiliate: false)
        XCTAssertFalse(TransactionActivityPolicy.isEligible(payload(swap: .thorchain(nativeSwap))))
        let swapKit = SwapKitSwapPayload(fromCoin: coin, toCoin: SendFormFixture.makeETH(), fromAmount: 1,
                                         toAmountDecimal: 1, txType: "PSBT", txPayload: Data(), targetAddress: "target",
                                         inboundAddress: nil, memo: nil, subProvider: "CHAINFLIP", swapID: "fixture")
        XCTAssertTrue(TransactionActivityPolicy.isEligible(payload(swap: .swapkit(swapKit))))
    }

    private func payload(memo: String? = nil, skipBroadcast: Bool = false, qbtc: Bool = false,
                         approve: ERC20ApprovePayload? = nil, swap: SwapPayload? = nil, maxSend: Bool = false) -> KeysignPayload {
        KeysignPayload(
            coin: swap?.fromCoin ?? SendFormFixture.makeETH(), toAddress: "0x1234567890123456789012345678901234567890",
            toAmount: BigInt(1_000_000_000_000_000_000),
            chainSpecific: maxSend ? .UTXO(byteFee: 1, sendMaxAmount: true)
                : .Ethereum(maxFeePerGasWei: 1, priorityFeeWei: 1, nonce: 0, gasLimit: 21_000),
            utxos: [], memo: memo, swapPayload: swap, approvePayload: approve,
            vaultPubKeyECDSA: "fixture", vaultLocalPartyID: "fixture", libType: "DKLS",
            wasmExecuteContractPayload: nil, tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil, tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil, isQbtcClaim: qbtc, skipBroadcast: skipBroadcast, signData: nil
        )
    }
}
