//
//  SolanaStakingBuilderAmountTests.swift
//  VultisigAppTests
//
//  Regression: the staking transaction builders must convert a human-decimal
//  SOL amount ("0.02889795") into the correct lamports. A prior bug fed the
//  human-decimal string straight to `String.toBigInt(decimals:)` — which expects
//  an already-scaled integer string — collapsing any fractional amount to 0
//  lamports and surfacing as "Solana staking payload missing required field:
//  lamports" at Verify. These pin the conversion at the builder layer (the
//  resolver/byte-parity tests build payloads directly and so never exercised it).
//

@testable import VultisigApp
import XCTest

final class SolanaStakingBuilderAmountTests: XCTestCase {

    private func solCoin() -> Coin {
        let meta = CoinMeta(
            chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
            priceProviderId: "solana", contractAddress: "", isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: "D5e2rzjfcmtin4i3p7gj9k4q2x8wq7w8q9w8q9w8q9w8",
            hexPublicKey: "00"
        )
    }

    private let votePubkey = "CertusDeBmqN8ZawdkxK5kFGMwBXdudvWHYwtNgNhvLu"

    func testDelegateConvertsFractionalAmountToLamports() throws {
        let builder = SolanaDelegateTransactionBuilder(
            coin: solCoin(), amount: "0.02889795", sendMaxAmount: false, votePubkey: votePubkey
        )
        let payload = try XCTUnwrap(builder.solanaStakingPayload)
        XCTAssertEqual(payload.opType, .delegate)
        XCTAssertEqual(payload.lamports, 28_897_950, "0.02889795 SOL must be 28,897,950 lamports, not 0")
    }

    func testDelegateConvertsWholeAmount() throws {
        let builder = SolanaDelegateTransactionBuilder(
            coin: solCoin(), amount: "1", sendMaxAmount: false, votePubkey: votePubkey
        )
        let payload = try XCTUnwrap(builder.solanaStakingPayload)
        XCTAssertEqual(payload.lamports, 1_000_000_000)
    }

    func testWithdrawConvertsFractionalAmountToLamports() throws {
        let builder = SolanaWithdrawTransactionBuilder(
            coin: solCoin(), stakeAccount: "Stake11111111111111111111111111111111111111", amount: "1.5"
        )
        let payload = try XCTUnwrap(builder.solanaStakingPayload)
        XCTAssertEqual(payload.opType, .withdraw)
        XCTAssertEqual(payload.lamports, 1_500_000_000)
    }
}
