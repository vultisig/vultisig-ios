//
//  BRUNEStakeTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the Rujira bRUNE / ybRUNE DeFi stake (bond) and unstake (unbond)
//  transaction builders. These move money through a wasm-execute keysign, so the
//  exact `executeMsg` JSON, the liquid-bond contract address, and the funds denom
//  (`x/brune` to bond, `x/staking-x/brune` to unbond) are byte-pinned here.
//

@testable import VultisigApp
import XCTest

final class BRUNEStakeTransactionBuilderTests: XCTestCase {

    private static func makeBRuneCoin(rawBalance: String = "10000000000") -> Coin {
        let coin = Coin(
            asset: TokensStore.brune,
            address: "thor1fixturebrunevaultaddress000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = rawBalance
        return coin
    }

    /// Parses `executeMsg` and asserts the `{ "<outer>": { "<inner>": {} } }`
    /// shape (whitespace-independent) so the test survives formatting changes.
    private func assertLiquidMessage(_ executeMsg: String, outer: String, inner: String) throws {
        let data = Data(executeMsg.utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Array(json.keys), [outer], "executeMsg must have exactly one top-level key")
        let liquid = try XCTUnwrap(json[outer] as? [String: Any])
        XCTAssertEqual(Array(liquid.keys), [inner], "executeMsg \(outer) must contain exactly \(inner)")
        let action = try XCTUnwrap(liquid[inner] as? [String: Any])
        XCTAssertTrue(action.isEmpty, "\(inner) must be an empty object")
    }

    // MARK: - Stake (bond)

    func testStakeBuilderEmitsLiquidBondMessage() throws {
        let builder = BRUNEStakeTransactionBuilder(coin: Self.makeBRuneCoin(), amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        try assertLiquidMessage(payload.executeMsg, outer: "liquid", inner: "bond")
    }

    func testStakeBuilderUsesLiquidBondContract() throws {
        let builder = BRUNEStakeTransactionBuilder(coin: Self.makeBRuneCoin(), amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        XCTAssertEqual(payload.contractAddress, BRUNEStakingConstants.contract)
        XCTAssertEqual(payload.contractAddress, "thor179fex2rxd45caedmz4hxsnu42sw20lu0djyh4yukyh965sq8muuqptru2g")
    }

    func testStakeBuilderFundsWithBRuneDenom() throws {
        let builder = BRUNEStakeTransactionBuilder(coin: Self.makeBRuneCoin(), amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(payload.coins.count, 1)
        XCTAssertEqual(funds.denom, "x/brune")
        XCTAssertEqual(funds.denom, TokensStore.brune.contractAddress)
        // 10 bRUNE at 8 decimals → 1_000_000_000 base units.
        XCTAssertEqual(funds.amount, "1000000000")
    }

    func testStakeBuilderSenderIsCoinAddress() throws {
        let coin = Self.makeBRuneCoin()
        let builder = BRUNEStakeTransactionBuilder(coin: coin, amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        XCTAssertEqual(payload.senderAddress, coin.address)
    }

    func testStakeBuilderIsGenericContractType() {
        let builder = BRUNEStakeTransactionBuilder(coin: Self.makeBRuneCoin(), amount: "10", sendMaxAmount: false)
        XCTAssertEqual(builder.transactionType, .genericContract)
    }

    // MARK: - Unstake (unbond)

    func testUnstakeBuilderEmitsLiquidUnbondMessage() throws {
        let builder = BRUNEUnstakeTransactionBuilder(
            coin: Self.makeBRuneCoin(),
            percentage: 100,
            autoCompoundAmount: Decimal(string: "5")!,
            sendMaxAmount: true
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        try assertLiquidMessage(payload.executeMsg, outer: "liquid", inner: "unbond")
    }

    func testUnstakeBuilderUsesLiquidBondContract() throws {
        let builder = BRUNEUnstakeTransactionBuilder(
            coin: Self.makeBRuneCoin(),
            percentage: 100,
            autoCompoundAmount: Decimal(string: "5")!,
            sendMaxAmount: true
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        XCTAssertEqual(payload.contractAddress, BRUNEStakingConstants.contract)
    }

    func testUnstakeBuilderFundsWithReceiptDenomFull() throws {
        let builder = BRUNEUnstakeTransactionBuilder(
            coin: Self.makeBRuneCoin(),
            percentage: 100,
            autoCompoundAmount: Decimal(string: "5")!,
            sendMaxAmount: true
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(payload.coins.count, 1)
        XCTAssertEqual(funds.denom, "x/staking-x/brune")
        XCTAssertEqual(funds.denom, TokensStore.ybrune.contractAddress)
        // 100% of 5 ybRUNE at 8 decimals → 500_000_000 receipt units.
        XCTAssertEqual(funds.amount, "500000000")
    }

    func testUnstakeBuilderScalesByPercentage() throws {
        let builder = BRUNEUnstakeTransactionBuilder(
            coin: Self.makeBRuneCoin(),
            percentage: 50,
            autoCompoundAmount: Decimal(string: "5")!,
            sendMaxAmount: false
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        let funds = try XCTUnwrap(payload.coins.first)
        // 50% of 5 ybRUNE at 8 decimals → 250_000_000 receipt units.
        XCTAssertEqual(funds.amount, "250000000")
    }

    func testUnstakeBuilderReturnsNilForSubUnitWithdrawal() {
        // 100% of an amount that scales below one base unit must not emit a payload.
        let builder = BRUNEUnstakeTransactionBuilder(
            coin: Self.makeBRuneCoin(),
            percentage: 100,
            autoCompoundAmount: Decimal(string: "0.000000001")!, // < 1e-8
            sendMaxAmount: true
        )
        XCTAssertNil(builder.wasmContractPayload)
    }
}
