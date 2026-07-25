//
//  RujiDualPositionWiringTests.swift
//  VultisigAppTests
//
//  The three small hooks that turn `TokensStore.sruji` into RUJI's
//  auto-compounding DeFi card. Each is a one-line mapping, and each one being
//  wrong routes real money: without the `.compound` type the card's actions take
//  the bonded path, and without the compound→bond mapping the transaction is
//  built against the receipt denom instead of `x/ruji`.
//

@testable import VultisigApp
import XCTest

@MainActor
final class RujiDualPositionWiringTests: XCTestCase {

    func testSRujiIsSelectableAlongsideRujiOnTHORChain() {
        let coins = DefiPositionsService().stakeCoins(for: .thorChain)
        XCTAssertTrue(coins.contains(TokensStore.ruji), "the bonded position must stay selectable")
        XCTAssertTrue(coins.contains(TokensStore.sruji), "the auto-compounding position must be selectable")
    }

    func testSRujiIsACompoundPosition() {
        XCTAssertEqual(StakePositionType.defaultType(for: TokensStore.sruji), .compound)
        XCTAssertEqual(StakePositionType.defaultType(for: TokensStore.ruji), .stake)
    }

    /// The compounded card's stake/unstake actions run against the BOND coin —
    /// `liquid.bond` is funded with `x/ruji` and `liquid.unbond` is built from
    /// the RUJI coin's decimals — so sRUJI has to map back to RUJI, like sTCY
    /// and ybRUNE do.
    func testCompoundedCardMapsBackToTheRujiBondCoin() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let model = DefiChainScreenModel(vault: TestStore.makeVault(), chain: .thorChain)

        XCTAssertEqual(model.stakeCoin(for: TokensStore.sruji), TokensStore.ruji)
        // Unchanged siblings.
        XCTAssertEqual(model.stakeCoin(for: TokensStore.stcy), TokensStore.tcy)
        XCTAssertEqual(model.stakeCoin(for: TokensStore.ybrune), TokensStore.brune)
        // A non-compound coin maps to itself.
        XCTAssertEqual(model.stakeCoin(for: TokensStore.ruji), TokensStore.ruji)
    }

    /// The two cards are keyed on different denoms, which is what gives them
    /// distinct persistent ids without a SwiftData migration.
    func testTheTwoPositionsGetDistinctPersistentIds() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        let bondedID = StakePosition.makeID(coin: TokensStore.ruji, vault: vault, stakeAccountPubkey: nil)
        let compoundedID = StakePosition.makeID(coin: TokensStore.sruji, vault: vault, stakeAccountPubkey: nil)

        XCTAssertNotEqual(bondedID, compoundedID)
        XCTAssertTrue(bondedID.contains("x/ruji"))
        XCTAssertTrue(compoundedID.contains("x/staking-x/ruji"))
    }

    // MARK: - Which message each card signs
    //
    // Both cards reach the shared stake/unstake view models on the RUJI coin, so
    // `isAutocompound` is the ONLY thing separating two messages that move money
    // into and out of different positions.

    private func makeRujiCoin() -> Coin {
        Coin(
            asset: TokensStore.ruji,
            address: "thor1fixturerujivaultaddress0000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private func executeMsg(_ builder: TransactionBuilder) throws -> [String: Any] {
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(payload.executeMsg.utf8)) as? [String: Any]
        )
    }

    func testCompoundedUnstakeRedeemsTheReceiptWithLiquidUnbond() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = UnstakeTransactionViewModel(
            coin: makeRujiCoin(),
            vault: TestStore.makeVault(),
            isAutocompound: true,
            availableToUnstake: Decimal(string: "140.64866515")!
        )
        viewModel.autocompoundBalance = Decimal(string: "138.55943656")!
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        XCTAssertNotNil(try executeMsg(builder)["liquid"])
        let funds = try XCTUnwrap(try XCTUnwrap(builder.wasmContractPayload).coins.first)
        XCTAssertEqual(funds.denom, "x/staking-x/ruji")
        XCTAssertEqual(funds.amount, "13855943656")
    }

    func testBondedUnstakeWithdrawsWithAccountWithdraw() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = UnstakeTransactionViewModel(
            coin: makeRujiCoin(),
            vault: TestStore.makeVault(),
            isAutocompound: false,
            availableToUnstake: Decimal(string: "16382.3899")!
        )
        viewModel.amountField.value = "10"
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        XCTAssertNotNil(try executeMsg(builder)["account"])
        XCTAssertTrue(try XCTUnwrap(builder.wasmContractPayload).coins.isEmpty)
    }

    /// The compounded sheet's ceiling is the card's RUJI-denominated amount, not
    /// the share balance, so nothing else stops a redemption being built before
    /// the share balance has loaded (or after that read failed).
    func testCompoundedUnstakeRefusesToBuildBeforeTheShareBalanceLoads() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = UnstakeTransactionViewModel(
            coin: makeRujiCoin(),
            vault: TestStore.makeVault(),
            isAutocompound: true,
            availableToUnstake: Decimal(string: "140.64866515")!
        )
        viewModel.validForm = true

        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testCompoundedStakeMintsTheReceiptWithLiquidBond() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = StakeTransactionViewModel(
            coin: makeRujiCoin(),
            vault: TestStore.makeVault(),
            isAutocompound: true
        )
        viewModel.amountField.value = "10"
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        let message = try executeMsg(builder)
        XCTAssertNotNil(message["liquid"])
        XCTAssertNil(message["account"])
        let funds = try XCTUnwrap(try XCTUnwrap(builder.wasmContractPayload).coins.first)
        XCTAssertEqual(funds.denom, "x/ruji")
    }

    func testBondedStakeDepositsWithAccountBond() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let viewModel = StakeTransactionViewModel(
            coin: makeRujiCoin(),
            vault: TestStore.makeVault(),
            isAutocompound: false
        )
        viewModel.amountField.value = "10"
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        let message = try executeMsg(builder)
        XCTAssertNotNil(message["account"])
        XCTAssertNil(message["liquid"])
    }
}
