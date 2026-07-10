//
//  BlockChainSpecificDecodingHardeningTests.swift
//  VultisigAppTests
//
//  A keysign payload is untrusted data deserialized from a co-signer.
//  Malformed / empty numeric fields in the peer proto must fall back to a
//  safe default instead of trapping via `BigInt(stringLiteral:)`.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

final class BlockChainSpecificDecodingHardeningTests: XCTestCase {

    // MARK: - Solana

    func testSolanaMalformedComputeLimitAndPriorityFeeFallBackToZero() throws {
        var value = VSSolanaSpecific()
        value.priorityFee = "abc"
        value.computeLimit = "" // present (hasComputeLimit == true) but empty → malformed

        let specific = try BlockChainSpecific(proto: .solanaSpecific(value))
        guard case let .Solana(_, priorityFee, priorityLimit, _, _, _) = specific else {
            return XCTFail("Expected .Solana")
        }
        XCTAssertTrue(value.hasComputeLimit)
        XCTAssertEqual(priorityFee, 0)
        XCTAssertEqual(priorityLimit, 0)
    }

    func testSolanaAbsentComputeLimitYieldsZero() throws {
        var value = VSSolanaSpecific()
        value.priorityFee = "5000"
        // hasComputeLimit left false

        let specific = try BlockChainSpecific(proto: .solanaSpecific(value))
        guard case let .Solana(_, priorityFee, priorityLimit, _, _, _) = specific else {
            return XCTFail("Expected .Solana")
        }
        XCTAssertEqual(priorityFee, 5000)
        XCTAssertEqual(priorityLimit, 0)
    }

    func testSolanaWellFormedValuesMapThroughVerbatimIncludingExplicitZero() throws {
        var value = VSSolanaSpecific()
        value.priorityFee = "0"
        value.computeLimit = "200000"

        let specific = try BlockChainSpecific(proto: .solanaSpecific(value))
        guard case let .Solana(_, priorityFee, priorityLimit, _, _, _) = specific else {
            return XCTFail("Expected .Solana")
        }
        XCTAssertEqual(priorityFee, 0)
        XCTAssertEqual(priorityLimit, 200000)
    }

    // MARK: - Ethereum

    func testEthereumMalformedNumericFieldsFallBackToZero() throws {
        var value = VSEthereumSpecific()
        value.maxFeePerGasWei = ""
        value.priorityFee = "xyz"
        value.gasLimit = ""

        let specific = try BlockChainSpecific(proto: .ethereumSpecific(value))
        guard case let .Ethereum(maxFee, priorityFee, _, gasLimit) = specific else {
            return XCTFail("Expected .Ethereum")
        }
        XCTAssertEqual(maxFee, 0)
        XCTAssertEqual(priorityFee, 0)
        XCTAssertEqual(gasLimit, 0)
    }

    func testEthereumWellFormedValuesMapThroughVerbatim() throws {
        var value = VSEthereumSpecific()
        value.maxFeePerGasWei = "1000000000"
        value.priorityFee = "0"
        value.gasLimit = "21000"

        let specific = try BlockChainSpecific(proto: .ethereumSpecific(value))
        guard case let .Ethereum(maxFee, priorityFee, _, gasLimit) = specific else {
            return XCTFail("Expected .Ethereum")
        }
        XCTAssertEqual(maxFee, BigInt("1000000000"))
        XCTAssertEqual(priorityFee, 0)
        XCTAssertEqual(gasLimit, 21000)
    }

    // MARK: - Polkadot

    func testPolkadotMalformedBlockNumberFallsBackToZero() throws {
        var value = VSPolkadotSpecific()
        value.currentBlockNumber = "not-a-number"

        let specific = try BlockChainSpecific(proto: .polkadotSpecific(value))
        guard case let .Polkadot(_, _, currentBlockNumber, _, _, _, _) = specific else {
            return XCTFail("Expected .Polkadot")
        }
        XCTAssertEqual(currentBlockNumber, 0)
    }

    func testPolkadotWellFormedBlockNumberMapsThroughVerbatim() throws {
        var value = VSPolkadotSpecific()
        value.currentBlockNumber = "18000000"

        let specific = try BlockChainSpecific(proto: .polkadotSpecific(value))
        guard case let .Polkadot(_, _, currentBlockNumber, _, _, _, _) = specific else {
            return XCTFail("Expected .Polkadot")
        }
        XCTAssertEqual(currentBlockNumber, BigInt("18000000"))
    }
}
