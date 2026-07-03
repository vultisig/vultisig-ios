//
//  ZcashZip317PlanTests.swift
//  VultisigAppTests
//
//  Real-WalletCore regression for the Zcash ZIP-317 conventional-fee guard in
//  UTXOChainsHelper. WalletCore's zip0317 planner flat-sizes OP_RETURN and
//  ignores byteFee, so memo txs plan one logical action short; the helper
//  re-plans with zip0317 off until the fee clears the conventional fee.
//
//  Golden vectors were extracted from a live run of the SDK resolver
//  (getUtxoSigningInputs + planZcashConventionalFee in
//  packages/core/mpc/keysign/signingInputs/resolvers/utxo.ts, real
//  wallet-core WASM 4.7.0 — the same version walletcore-spm pins). The
//  planned fee/change must be byte-identical across platforms or MPC
//  co-signing devices derive different preimage digests and keysign fails.
//

import BigInt
@testable import VultisigApp
import WalletCore
import XCTest

final class ZcashZip317PlanTests: XCTestCase {
    private let zcashAddress = "t1PoLLLwEcVhqMBhk53tANtSepnPXAQJkPM"
    private let branchIdHex = "30f33754"

    // MARK: - Send path (getBitcoinPreSigningInputData / getBitcoinTransactionPlan)

    func testPlainSendKeepsTheZip0317PlanAtTheFloor() throws {
        let input = try presignInput(amount: 5_000_000, balance: 8_300_000, memo: nil)

        XCTAssertEqual(input.plan.fee, 10_000)
        XCTAssertEqual(input.plan.amount, 5_000_000)
        XCTAssertEqual(input.plan.change, 3_290_000)
        XCTAssertTrue(input.zip0317)
        XCTAssertEqual(input.byteFee, 100)
    }

    func testMemoSendReplansToMeetTheConventionalFee() throws {
        // SDK golden: reported live failure shape — zip0317 plans 15,000 where
        // ZIP-317 requires 20,000; the guard re-plans to 20,020 at byteFee 77.
        let input = try presignInput(amount: 5_000_000, balance: 8_300_000, memo: String(repeating: "m", count: 40))

        XCTAssertEqual(input.plan.fee, 20_020)
        XCTAssertEqual(input.plan.amount, 5_000_000)
        XCTAssertEqual(input.plan.change, 3_279_980)
        XCTAssertFalse(input.zip0317)
        XCTAssertEqual(input.byteFee, 77)
        XCTAssertEqual(input.plan.branchID.hexString, branchIdHex)
    }

    func testSendMaxMemoSendReplansToMeetTheConventionalFee() throws {
        let input = try presignInput(
            amount: 2_200_000,
            balance: 2_200_000,
            memo: String(repeating: "m", count: 40),
            sendMax: true
        )

        XCTAssertEqual(input.plan.fee, 15_142)
        XCTAssertEqual(input.plan.amount, 2_184_858)
        XCTAssertEqual(input.plan.change, 0)
        XCTAssertFalse(input.zip0317)
        XCTAssertEqual(input.byteFee, 67)
    }

    func testLongMemoSpanningExtraActionsClearsTheConventionalFee() throws {
        let input = try presignInput(amount: 5_000_000, balance: 8_300_000, memo: String(repeating: "m", count: 200))

        XCTAssertEqual(input.plan.fee, 45_240)
        XCTAssertEqual(input.plan.change, 3_254_760)
        XCTAssertFalse(input.zip0317)
        XCTAssertEqual(input.byteFee, 174)
    }

    func testMayaSwapShapedMemoReplansToMeetTheConventionalFee() throws {
        // Maya-native ZEC swaps ride the plain send path with the swap
        // instruction as the memo; this is the live shape the issue reports.
        let memo = "=:ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48:0x92009f858E52D5C48CBaBFE0EE9AB05EF5eEC865:1494322902:vi:35"
        let input = try presignInput(amount: 5_000_000, balance: 8_300_000, memo: memo)

        XCTAssertEqual(input.plan.fee, 30_160)
        XCTAssertEqual(input.plan.change, 3_269_840)
        XCTAssertFalse(input.zip0317)
        XCTAssertEqual(input.byteFee, 116)
    }

    func testInsufficientFundsPlanPassesThroughUntouched() throws {
        // Balance can't cover amount + fee + dust, so WalletCore selects no
        // UTXOs. The conventional-fee guard must not hijack this with a
        // ZIP-317 error — the send flow owns the insufficient-funds outcome.
        let helper = UTXOChainsHelper(coin: .zcash)
        let plan = try helper.getBitcoinTransactionPlan(
            keysignPayload: makePayload(amount: 90_000, balance: 100_000, memo: String(repeating: "m", count: 40))
        )

        XCTAssertTrue(plan.utxos.isEmpty)
        XCTAssertEqual(plan.fee, 0)
    }

    func testFeePreviewPlanMatchesTheSignedFee() throws {
        // KeysignPayloadFactory (UTXO selection), the send/swap fee displays,
        // and the co-signer gas view all read getBitcoinTransactionPlan; it
        // must agree with the plan that gets signed.
        let memo = String(repeating: "m", count: 40)
        let helper = UTXOChainsHelper(coin: .zcash)
        let previewPlan = try helper.getBitcoinTransactionPlan(
            keysignPayload: makePayload(amount: 5_000_000, balance: 8_300_000, memo: memo)
        )
        let signedInput = try presignInput(amount: 5_000_000, balance: 8_300_000, memo: memo)

        XCTAssertEqual(previewPlan.fee, signedInput.plan.fee)
        XCTAssertEqual(previewPlan.change, signedInput.plan.change)
    }

    // MARK: - Swap-input path (getSigningInputData)

    func testSwapSigningInputDataReplansToMeetTheConventionalFee() throws {
        let memo = String(repeating: "m", count: 40)
        let payload = makePayload(
            amount: 5_000_000,
            balance: 8_300_000,
            memo: memo,
            swapPayload: .thorchain(makeSwapPayload(amount: 5_000_000))
        )
        let helper = UTXOChainsHelper(coin: .zcash)
        let swapInput = try helper.getSwapPreSignedInputData(keysignPayload: payload)
        let inputData = try helper.getSigningInputData(keysignPayload: payload, signingInput: swapInput)
        let input = try BitcoinSigningInput(serializedBytes: inputData)

        // Same tx shape as the send-path memo golden vector, so the same plan.
        XCTAssertEqual(input.plan.fee, 20_020)
        XCTAssertEqual(input.plan.change, 3_279_980)
        XCTAssertFalse(input.zip0317)
        XCTAssertEqual(input.plan.branchID.hexString, branchIdHex)
    }

    // MARK: - Helpers

    private func presignInput(
        amount: BigInt,
        balance: Int64,
        memo: String?,
        sendMax: Bool = false
    ) throws -> BitcoinSigningInput {
        let helper = UTXOChainsHelper(coin: .zcash)
        let inputData = try helper.getBitcoinPreSigningInputData(
            keysignPayload: makePayload(amount: amount, balance: balance, memo: memo, sendMax: sendMax)
        )
        return try BitcoinSigningInput(serializedBytes: inputData)
    }

    private func makeZcashCoin() -> Coin {
        let meta = CoinMeta.make(chain: .zcash, ticker: "ZEC", decimals: 8, isNativeToken: true)
        return Coin(asset: meta, address: zcashAddress, hexPublicKey: "")
    }

    private func makeSwapPayload(amount: BigInt) -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: zcashAddress,
            fromCoin: makeZcashCoin(),
            toCoin: makeZcashCoin(),
            vaultAddress: zcashAddress,
            routerAddress: nil,
            fromAmount: amount,
            toAmountDecimal: 0,
            toAmountLimit: "0",
            streamingInterval: "1",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: false
        )
    }

    private func makePayload(
        amount: BigInt,
        balance: Int64,
        memo: String?,
        sendMax: Bool = false,
        swapPayload: SwapPayload? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: makeZcashCoin(),
            toAddress: zcashAddress,
            toAmount: amount,
            chainSpecific: BlockChainSpecific.UTXO(
                byteFee: 100,
                sendMaxAmount: sendMax,
                zcashBranchId: branchIdHex
            ),
            utxos: [UtxoInfo(hash: String(repeating: "00", count: 32), amount: balance, index: 0)],
            memo: memo,
            swapPayload: swapPayload,
            approvePayload: nil,
            vaultPubKeyECDSA: "ECDSAKey",
            vaultLocalPartyID: "localPartyID",
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
