//
//  ThorchainBRuneServiceTests.swift
//  VultisigAppTests
//
//  Pins the pure parsing seams for the bRUNE / ybRUNE integration: the NAV ratio
//  computed from the liquid-bond `{"status":{}}` query, and the `x/staking-x/brune`
//  receipt-balance parse. Both drive money-adjacent flows (price display + unstake
//  amount), so their parsing is validated without the LCD round-trip.
//

@testable import VultisigApp
import XCTest

final class ThorchainBRuneServiceTests: XCTestCase {

    // MARK: - navRatio (liquid_bond_size / liquid_bond_shares)

    func testNavRatioSimpleParity() {
        XCTAssertEqual(ThorchainService.navRatio(size: "103", shares: "100"), 1.03)
    }

    func testNavRatioExactDouble() {
        XCTAssertEqual(ThorchainService.navRatio(size: "2000", shares: "1000"), 2.0)
    }

    func testNavRatioLiveContractValues() throws {
        // Live `{"status":{}}` snapshot from the bRUNE liquid-bond contract.
        let ratio = try XCTUnwrap(ThorchainService.navRatio(
            size: "269327874476444",
            shares: "260965816001512"
        ))
        XCTAssertEqual(ratio, 1.03204, accuracy: 1e-5)
    }

    func testNavRatioNilForZeroShares() {
        XCTAssertNil(ThorchainService.navRatio(size: "100", shares: "0"))
    }

    func testNavRatioNilForUnparseableInput() {
        XCTAssertNil(ThorchainService.navRatio(size: "abc", shares: "100"))
        XCTAssertNil(ThorchainService.navRatio(size: "100", shares: "xyz"))
    }

    // MARK: - parseStakingReceiptAmount

    private func balancesJSON(_ entries: [(denom: String, amount: String)]) -> Data {
        let items = entries.map { "{\"denom\":\"\($0.denom)\",\"amount\":\"\($0.amount)\"}" }
        return Data("{\"balances\":[\(items.joined(separator: ","))]}".utf8)
    }

    func testParseReceiptReturnsMatchingDenomAmount() throws {
        let data = balancesJSON([
            ("rune", "500"),
            ("x/staking-x/brune", "344000000")
        ])
        let amount = try ThorchainService.parseStakingReceiptAmount(data: data, denom: "x/staking-x/brune")
        XCTAssertEqual(amount, Decimal(344000000))
    }

    func testParseReceiptStillResolvesTcyDenom() throws {
        let data = balancesJSON([("x/staking-tcy", "12345")])
        let amount = try ThorchainService.parseStakingReceiptAmount(data: data, denom: "x/staking-tcy")
        XCTAssertEqual(amount, Decimal(12345))
    }

    func testParseReceiptReturnsZeroWhenDenomAbsent() throws {
        let data = balancesJSON([("rune", "500"), ("x/staking-tcy", "1")])
        let amount = try ThorchainService.parseStakingReceiptAmount(data: data, denom: "x/staking-x/brune")
        XCTAssertEqual(amount, .zero)
    }

    func testParseReceiptReturnsZeroForEmptyBalances() throws {
        let data = Data("{\"balances\":[]}".utf8)
        let amount = try ThorchainService.parseStakingReceiptAmount(data: data, denom: "x/staking-x/brune")
        XCTAssertEqual(amount, .zero)
    }

    func testParseReceiptThrowsOnMalformedResponse() {
        let data = Data("{\"unexpected\":true}".utf8)
        XCTAssertThrowsError(
            try ThorchainService.parseStakingReceiptAmount(data: data, denom: "x/staking-x/brune")
        )
    }
}
