//
//  TronStakingAmountTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class TronStakingAmountTests: XCTestCase {

    /// The field holds device-locale text ("100,125" in de_DE). Only a comma-decimal
    /// locale exposes the old `Decimal.description` re-parse; en passes either way.
    func testFreezeSignsTheTypedAmount() throws {
        let viewModel = TronFreezeViewModel(vault: makeVault())
        viewModel.availableBalance = 1_000
        viewModel.onLoad()
        viewModel.amountField.value = typed("100.125")

        let transaction = try XCTUnwrap(viewModel.makeTransaction())

        XCTAssertEqual(transaction.amountInRaw, BigInt(100_125_000))
    }

    func testUnfreezeSignsTheTypedAmount() throws {
        let viewModel = TronUnfreezeViewModel(vault: makeVault(), frozenBandwidthBalance: 1_000)
        viewModel.onLoad()
        viewModel.amountField.value = typed("100.125")

        let transaction = try XCTUnwrap(viewModel.makeTransaction())

        XCTAssertEqual(transaction.amountInRaw, BigInt(100_125_000))
    }

    /// What the amount field shows for `value` in the device locale.
    private func typed(_ value: String) -> String {
        (Decimal(string: value) ?? 0).formatToDecimal(digits: 6)
    }

    private func makeVault() -> Vault {
        let trx = SendFormFixture.makeTRX(rawBalance: "1000000000")
        return SendFormFixture.makeVault(coins: [trx])
    }
}
