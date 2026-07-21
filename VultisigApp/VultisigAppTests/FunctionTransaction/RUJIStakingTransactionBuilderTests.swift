//
//  RUJIStakingTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the RUJI staking transaction builders. RUJI has TWO independent
//  positions on one contract — bonded (`account.*`) and auto-compounding
//  (`liquid.*`) — and they move money through different wasm executes against
//  different denoms. A message crossing over would deposit into, or redeem from,
//  the position the user did not choose, so the exact `executeMsg` JSON, the
//  contract address and the funds are byte-pinned here.
//

@testable import VultisigApp
import XCTest

final class RUJIStakingTransactionBuilderTests: XCTestCase {

    /// The `rujira-staking:x/ruji` contract, pinned literally so a constant
    /// change has to be deliberate.
    private static let stakingContract = "thor13g83nn5ef4qzqeafp0508dnvkvm0zqr3sj7eefcn5umu65gqluusrml5cr"
    private static let receiptDenom = "x/staking-x/ruji"
    private static let bondDenom = "x/ruji"

    private static func makeRujiCoin() -> Coin {
        let coin = Coin(
            asset: TokensStore.ruji,
            address: "thor1fixturerujivaultaddress0000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = "10000000000"
        return coin
    }

    /// Parses `executeMsg` and asserts the `{ "<outer>": { "<inner>": {} } }`
    /// shape (whitespace-independent) so the test survives formatting changes.
    private func assertEmptyMessage(_ executeMsg: String, outer: String, inner: String) throws {
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(executeMsg.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Array(json.keys), [outer], "executeMsg must have exactly one top-level key")
        let branch = try XCTUnwrap(json[outer] as? [String: Any])
        XCTAssertEqual(Array(branch.keys), [inner], "\(outer) must contain exactly \(inner)")
        let action = try XCTUnwrap(branch[inner] as? [String: Any])
        XCTAssertTrue(action.isEmpty, "\(inner) must be an empty object")
    }

    // MARK: - Contract pin

    func testConstantMatchesTheDeployedStakingContract() {
        XCTAssertEqual(RUJIStakingConstants.contract, Self.stakingContract)
        XCTAssertEqual(TokensStore.ruji.contractAddress, Self.bondDenom)
        XCTAssertEqual(TokensStore.sruji.contractAddress, Self.receiptDenom)
    }

    // MARK: - Auto-compounding stake (liquid.bond)

    func testLiquidBondEmitsLiquidBondMessage() throws {
        let builder = RUJILiquidBondTransactionBuilder(coin: Self.makeRujiCoin(), amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        try assertEmptyMessage(payload.executeMsg, outer: "liquid", inner: "bond")
        XCTAssertEqual(payload.contractAddress, Self.stakingContract)
        XCTAssertEqual(payload.senderAddress, Self.makeRujiCoin().address)
        XCTAssertEqual(builder.transactionType, .genericContract)
    }

    func testLiquidBondFundsWithTheBondDenom() throws {
        let builder = RUJILiquidBondTransactionBuilder(coin: Self.makeRujiCoin(), amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        XCTAssertEqual(payload.coins.count, 1)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(funds.denom, Self.bondDenom)
        // 10 RUJI at 8 decimals → 1_000_000_000 base units.
        XCTAssertEqual(funds.amount, "1000000000")
    }

    func testLiquidBondTruncatesSubBaseUnitPrecision() throws {
        // 9 dp exceeds RUJI's 8 dp: 1.123456789 × 1e8 = 112345678.9, which must
        // round DOWN to an integer base-unit string.
        let builder = RUJILiquidBondTransactionBuilder(
            coin: Self.makeRujiCoin(),
            amount: "1.123456789",
            sendMaxAmount: false
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(funds.amount, "112345678")
        XCTAssertFalse(funds.amount.contains("."), "funds amount must be an integer base-unit string")
    }

    /// The amount validator only rejects an exact zero, so sub-base-unit dust
    /// reaches the builder. Bonding zero funds is a no-op that still costs a
    /// fee, so no payload is produced — mirroring the unbond side.
    func testLiquidBondProducesNoPayloadBelowOneBaseUnit() {
        let builder = RUJILiquidBondTransactionBuilder(
            coin: Self.makeRujiCoin(),
            amount: "0.000000009",
            sendMaxAmount: false
        )
        XCTAssertNil(builder.wasmContractPayload)
    }

    // MARK: - Auto-compounding unstake (liquid.unbond)

    func testLiquidUnbondEmitsLiquidUnbondMessage() throws {
        let builder = RUJILiquidUnbondTransactionBuilder(
            coin: Self.makeRujiCoin(),
            percentage: 100,
            receiptShares: Decimal(string: "138.55943656")!,
            sendMaxAmount: true
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        try assertEmptyMessage(payload.executeMsg, outer: "liquid", inner: "unbond")
        XCTAssertEqual(payload.contractAddress, Self.stakingContract)
        XCTAssertEqual(builder.transactionType, .genericContract)
    }

    /// At 100% the EXACT held share balance is redeemed — no rounding dust, and
    /// it can never exceed what is held even if the share price moved since the
    /// sheet opened. This is what makes the percentage-driven redemption safe
    /// without a share-price conversion.
    func testLiquidUnbondRedeemsTheExactShareBalanceAtFullPercentage() throws {
        let builder = RUJILiquidUnbondTransactionBuilder(
            coin: Self.makeRujiCoin(),
            percentage: 100,
            receiptShares: Decimal(string: "138.55943656")!,
            sendMaxAmount: true
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        XCTAssertEqual(payload.coins.count, 1)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(funds.denom, Self.receiptDenom)
        XCTAssertEqual(funds.amount, "13855943656")
    }

    func testLiquidUnbondScalesSharesByPercentage() throws {
        let builder = RUJILiquidUnbondTransactionBuilder(
            coin: Self.makeRujiCoin(),
            percentage: 50,
            receiptShares: Decimal(string: "138.55943656")!,
            sendMaxAmount: false
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(funds.amount, "6927971828")
    }

    /// Redeeming zero shares is a no-op the contract would reject, so the
    /// builder produces no payload rather than an empty unbond.
    func testLiquidUnbondProducesNoPayloadBelowOneBaseUnit() {
        let builder = RUJILiquidUnbondTransactionBuilder(
            coin: Self.makeRujiCoin(),
            percentage: 1,
            receiptShares: Decimal(string: "0.00000001")!,
            sendMaxAmount: false
        )
        XCTAssertNil(builder.wasmContractPayload)
    }

    func testLiquidUnbondProducesNoPayloadWithoutAShareBalance() {
        let builder = RUJILiquidUnbondTransactionBuilder(
            coin: Self.makeRujiCoin(),
            percentage: 100,
            receiptShares: 0,
            sendMaxAmount: true
        )
        XCTAssertNil(builder.wasmContractPayload)
    }

    // MARK: - Bonded position stays on the account.* messages

    func testBondedStakeStillEmitsAccountBondFundedWithRuji() throws {
        let builder = RUJIStakeTransactionBuilder(coin: Self.makeRujiCoin(), amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        try assertEmptyMessage(payload.executeMsg, outer: "account", inner: "bond")
        XCTAssertEqual(payload.contractAddress, Self.stakingContract)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(funds.denom, Self.bondDenom)
        XCTAssertEqual(funds.amount, "1000000000")
    }

    /// `CosmosCoin.amount` must be an integer base-unit string; a fractional one
    /// is a malformed execute. The bonded builder used to stringify the raw
    /// `Decimal`, so 9 dp produced `"112345678.9"`.
    func testBondedStakeFundsWithAnIntegerBaseUnitString() throws {
        let builder = RUJIStakeTransactionBuilder(
            coin: Self.makeRujiCoin(),
            amount: "1.123456789",
            sendMaxAmount: false
        )
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(funds.amount, "112345678")
        XCTAssertFalse(funds.amount.contains("."), "funds amount must be an integer base-unit string")
    }

    func testBondedStakeProducesNoPayloadBelowOneBaseUnit() {
        let builder = RUJIStakeTransactionBuilder(
            coin: Self.makeRujiCoin(),
            amount: "0.000000009",
            sendMaxAmount: false
        )
        XCTAssertNil(builder.wasmContractPayload)
    }

    /// The bonded position holds no receipt token, so its withdrawal names the
    /// amount in the message and sends no funds — the mirror image of
    /// `liquid.unbond`.
    func testBondedUnstakeStillEmitsAccountWithdrawWithNoFunds() throws {
        let builder = RUJIUnstakeTransactionBuilder(coin: Self.makeRujiCoin(), amount: "10", sendMaxAmount: false)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        XCTAssertEqual(payload.contractAddress, Self.stakingContract)
        XCTAssertTrue(payload.coins.isEmpty, "account.withdraw carries no funds")

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payload.executeMsg.utf8)) as? [String: Any]
        )
        let account = try XCTUnwrap(json["account"] as? [String: Any])
        let withdraw = try XCTUnwrap(account["withdraw"] as? [String: Any])
        XCTAssertEqual(withdraw["amount"] as? String, "1000000000")
    }
}
