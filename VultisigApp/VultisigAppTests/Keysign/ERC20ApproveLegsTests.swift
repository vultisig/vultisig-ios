//
//  ERC20ApproveLegsTests.swift
//  VultisigAppTests
//
//  The ERC20 approve legs every signer derives from a shared payload: how many
//  there are, the amount and nonce of each, and the nonce the dependent
//  transaction moves to. Co-signers rebuild this list independently, so a
//  device that derives a different one hashes a different message set and the
//  ceremony stalls instead of failing loudly.
//

import BigInt
import VultisigCommonData
import XCTest
@testable import VultisigApp

final class ERC20ApproveLegsTests: XCTestCase {

    // MARK: - Without the reset: today's messages, byte for byte

    /// Maya EVM route, signed by the `THORChainSwaps` leaf (router deposit).
    /// Hashes are the committed cross-platform corpus values.
    func testApproveSwapWithoutResetKeepsCommittedHashesOnMayaEvmRoute() throws {
        let payload = try fixturePayload(file: "mayaswap", name: "Swap ARB.USDC to CACAO")
        XCTAssertEqual(payload.approvePayload?.amount, BigInt(7_160_000))

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages, [
            "8fc58a393062400da51d6f16d97763008ebf807e8a4e03ae530faf94a7d593c7",
            "5abefbff1d10fc36063e075d2b92e1664129c2c04fc3db7d5bcf1dbcc0737acd"
        ])
    }

    /// Generic EVM route (1inch), signed by the `OneInchSwaps` leaf.
    func testApproveSwapWithoutResetKeepsCommittedHashesOnGenericRoute() throws {
        let payload = try fixturePayload(file: "arb", name: "Swap from ARB.ARB to ARB.ETH via 1inch")
        XCTAssertNotNil(payload.approvePayload)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages, [
            "cbec83beda9f91c7c6ce4283131e6eb4cd52dfa64dfa471efe38023ddc4a5a92",
            "d38e251e526ff07a695d2f91e4a7a1314c33e3b837ddcabf1ab67ae4ecbd12fa"
        ])
    }

    // MARK: - Helpers

    private func fixturePayload(file: String, name: String) throws -> KeysignPayload {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(
            bundle.url(forResource: file, withExtension: "json", subdirectory: "TestData"),
            "Missing TestData/\(file).json in the test bundle"
        )
        let cases = try JSONDecoder().decode([ChainHelperTestCase].self, from: Data(contentsOf: url))
        let testCase = try XCTUnwrap(cases.first { $0.name == name }, "No case named \(name) in \(file).json")
        return try KeysignPayload(proto: testCase.keysignPayload)
    }
}
