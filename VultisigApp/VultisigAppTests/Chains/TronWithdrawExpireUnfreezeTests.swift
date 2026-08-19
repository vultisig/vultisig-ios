//
//  TronWithdrawExpireUnfreezeTests.swift
//  VultisigAppTests
//
//  `TronHelper` routes a self-addressed native TRX payload carrying the
//  `WITHDRAW_EXPIRE_UNFREEZE` memo to `WithdrawExpireUnfreezeContract` — the
//  Stake 2.0 claim that returns every expired `UnfreezeBalanceV2` entry to the
//  spendable balance. The contract has no amount and the memo is a routing
//  marker only, so neither may leak into the signed transaction.
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

final class TronWithdrawExpireUnfreezeTests: XCTestCase {

    private let witness = "41e0e0f1a3a3f3e2d1c0b0a0908070605040302010"
    private let hash32 = "e63d3f0f2a3a3f3e2d1c0b0a09080706050403020100ffeeddccbbaa99887766"

    func testSelfAddressedMemoBuildsWithdrawExpireUnfreezeContract() throws {
        let coin = makeTrx()
        let payload = makePayload(coin: coin, toAddress: coin.address, memo: TronHelper.withdrawExpireUnfreezeMemo)

        let input = try TronSigningInput(serializedBytes: TronHelper.getPreSignedInputData(keysignPayload: payload))

        guard case .withdrawExpireUnfreeze(let contract) = input.transaction.contractOneof else {
            return XCTFail("expected withdrawExpireUnfreeze contract, got \(String(describing: input.transaction.contractOneof))")
        }
        XCTAssertEqual(contract.ownerAddress, coin.address)
        XCTAssertTrue(input.transaction.memo.isEmpty, "the routing memo must not be written into the signed transaction")
        XCTAssertEqual(input.transaction.timestamp, 1_700_000_000_000)
        XCTAssertEqual(input.transaction.expiration, 1_700_000_060_000)
        XCTAssertEqual(input.transaction.feeLimit, 1_000_000)
        XCTAssertEqual(input.transaction.blockHeader.number, 50_000_000)
    }

    func testClaimIgnoresPayloadAmount() throws {
        let coin = makeTrx()
        let zeroAmount = makePayload(coin: coin, toAddress: coin.address, memo: TronHelper.withdrawExpireUnfreezeMemo, toAmount: .zero)
        let someAmount = makePayload(coin: coin, toAddress: coin.address, memo: TronHelper.withdrawExpireUnfreezeMemo, toAmount: BigInt(12_500_000))

        XCTAssertEqual(
            try TronHelper.getPreSignedInputData(keysignPayload: zeroAmount),
            try TronHelper.getPreSignedInputData(keysignPayload: someAmount),
            "the contract carries no amount, so toAmount must not change the bytes to sign"
        )
    }

    func testPreSignedImageHashIsSingleHash() throws {
        let coin = makeTrx()
        let payload = makePayload(coin: coin, toAddress: coin.address, memo: TronHelper.withdrawExpireUnfreezeMemo)

        let hashes = try TronHelper.getPreSignedImageHash(keysignPayload: payload)

        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(hashes[0].count, 64)
    }

    func testNonSelfDestinationWithClaimMemoThrows() {
        let coin = makeTrx()
        let payload = makePayload(
            coin: coin,
            toAddress: SigningGoldenFactory.recipient(.tron),
            memo: TronHelper.withdrawExpireUnfreezeMemo
        )

        XCTAssertThrowsError(try TronHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testTokenCoinWithClaimMemoThrows() {
        let usdt = SigningGoldenFactory.coin(
            chain: .tron,
            ticker: "USDT",
            decimals: 6,
            contractAddress: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            isNativeToken: false,
            curve: .secp256k1,
            uncompressedSecp: true
        )
        let payload = makePayload(coin: usdt, toAddress: usdt.address, memo: TronHelper.withdrawExpireUnfreezeMemo)

        XCTAssertThrowsError(try TronHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testNearMissMemoFallsThroughToTransfer() throws {
        let coin = makeTrx()
        let payload = makePayload(coin: coin, toAddress: coin.address, memo: "WITHDRAW_EXPIRE_UNFREEZE:BANDWIDTH")

        let input = try TronSigningInput(serializedBytes: TronHelper.getPreSignedInputData(keysignPayload: payload))

        guard case .transfer = input.transaction.contractOneof else {
            return XCTFail("a memo that is not exactly the claim marker must not be treated as a claim")
        }
    }

    // MARK: - Fixtures

    private func makeTrx() -> Coin {
        SigningGoldenFactory.coin(chain: .tron, ticker: "TRX", decimals: 6, curve: .secp256k1, uncompressedSecp: true)
    }

    private func makePayload(coin: Coin, toAddress: String, memo: String?, toAmount: BigInt = BigInt(1_000_000)) -> KeysignPayload {
        SigningGoldenFactory.payload(
            coin: coin,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Tron(
                timestamp: 1_700_000_000_000,
                expiration: 1_700_000_060_000,
                blockHeaderTimestamp: 1_700_000_000_000,
                blockHeaderNumber: 50_000_000,
                blockHeaderVersion: 30,
                blockHeaderTxTrieRoot: hash32,
                blockHeaderParentHash: hash32,
                blockHeaderWitnessAddress: witness,
                gasFeeEstimation: 1_000_000
            ),
            memo: memo
        )
    }
}
