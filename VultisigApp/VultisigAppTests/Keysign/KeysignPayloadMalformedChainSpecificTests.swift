//
//  KeysignPayloadMalformedChainSpecificTests.swift
//  VultisigAppTests
//
//  A keysign payload is untrusted data deserialized from a co-signer at the
//  start of a ceremony. Decoding its chain-specific numeric fields with the
//  trapping `BigInt(stringLiteral:)` initializer hard-crashes the receiving
//  device when a peer sends a malformed/empty string. These tests pin the
//  crash-hardened contract: malformed/empty/absent numeric fields fall back to
//  0 (mirroring an absent field), while every well-formed value — including an
//  explicit "0" — still maps through verbatim so the signed tx is unchanged.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

final class KeysignPayloadMalformedChainSpecificTests: XCTestCase {

    // Base58 of 32 zero bytes — a structurally valid recent blockhash.
    private let recentBlockHash = "11111111111111111111111111111111"

    // MARK: - Solana priority_fee

    func testSolanaMalformedPriorityFeeFallsBackToZero() throws {
        let specific = try decodeSolana(priorityFee: "abc", computeLimit: nil)
        guard case .Solana(_, let priorityFee, _, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityFee, 0, "malformed priority_fee must decode to 0, not crash")
    }

    func testSolanaEmptyPriorityFeeFallsBackToZero() throws {
        let specific = try decodeSolana(priorityFee: "", computeLimit: nil)
        guard case .Solana(_, let priorityFee, _, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityFee, 0, "empty priority_fee must decode to 0, not crash")
    }

    func testSolanaWellFormedPriorityFeeMapsVerbatim() throws {
        let specific = try decodeSolana(priorityFee: "1000000", computeLimit: nil)
        guard case .Solana(_, let priorityFee, _, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityFee, BigInt(1_000_000), "well-formed priority_fee must map through unchanged")
    }

    func testSolanaExplicitZeroPriorityFeeMapsToZero() throws {
        let specific = try decodeSolana(priorityFee: "0", computeLimit: nil)
        guard case .Solana(_, let priorityFee, _, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityFee, 0, "a valid explicit \"0\" must still map to 0")
    }

    // MARK: - Solana compute_limit

    func testSolanaMalformedComputeLimitFallsBackToZero() throws {
        let specific = try decodeSolana(priorityFee: "0", computeLimit: "abc")
        guard case .Solana(_, _, let priorityLimit, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityLimit, 0, "malformed compute_limit must decode to 0, not crash")
    }

    func testSolanaEmptyComputeLimitFallsBackToZero() throws {
        let specific = try decodeSolana(priorityFee: "0", computeLimit: "")
        guard case .Solana(_, _, let priorityLimit, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityLimit, 0, "empty compute_limit must decode to 0, not crash")
    }

    func testSolanaAbsentComputeLimitIsZero() throws {
        let specific = try decodeSolana(priorityFee: "0", computeLimit: nil)
        guard case .Solana(_, _, let priorityLimit, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityLimit, 0, "absent compute_limit must decode to 0 (use-default sentinel)")
    }

    func testSolanaWellFormedComputeLimitMapsVerbatim() throws {
        let specific = try decodeSolana(priorityFee: "0", computeLimit: "100000")
        guard case .Solana(_, _, let priorityLimit, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityLimit, BigInt(100_000), "well-formed compute_limit must map through unchanged")
    }

    func testSolanaExplicitZeroComputeLimitMapsToZero() throws {
        let specific = try decodeSolana(priorityFee: "0", computeLimit: "0")
        guard case .Solana(_, _, let priorityLimit, _, _, _) = specific else {
            return XCTFail("expected Solana case")
        }
        XCTAssertEqual(priorityLimit, 0, "a valid explicit \"0\" compute_limit must still map to 0")
    }

    // MARK: - EVM / Ethereum

    func testEthereumMalformedNumericFieldsFallBackToZero() throws {
        let specific = try decodeEthereum(maxFeePerGasWei: "abc", priorityFee: "", gasLimit: "xyz")
        guard case .Ethereum(let maxFeePerGasWei, let priorityFeeWei, let nonce, let gasLimit) = specific else {
            return XCTFail("expected Ethereum case")
        }
        XCTAssertEqual(maxFeePerGasWei, 0, "malformed max_fee_per_gas_wei must decode to 0, not crash")
        XCTAssertEqual(priorityFeeWei, 0, "empty priority_fee must decode to 0, not crash")
        XCTAssertEqual(gasLimit, 0, "malformed gas_limit must decode to 0, not crash")
        XCTAssertEqual(nonce, 7, "the non-numeric-string fields are untouched")
    }

    func testEthereumWellFormedNumericFieldsMapVerbatim() throws {
        let specific = try decodeEthereum(maxFeePerGasWei: "50000000000", priorityFee: "1500000000", gasLimit: "21000")
        guard case .Ethereum(let maxFeePerGasWei, let priorityFeeWei, _, let gasLimit) = specific else {
            return XCTFail("expected Ethereum case")
        }
        XCTAssertEqual(maxFeePerGasWei, BigInt(50_000_000_000), "well-formed max_fee_per_gas_wei must map through unchanged")
        XCTAssertEqual(priorityFeeWei, BigInt(1_500_000_000), "well-formed priority_fee must map through unchanged")
        XCTAssertEqual(gasLimit, BigInt(21_000), "well-formed gas_limit must map through unchanged")
    }

    // MARK: - Polkadot

    func testPolkadotMalformedCurrentBlockNumberFallsBackToZero() throws {
        let specific = try decodePolkadot(currentBlockNumber: "not-a-number")
        guard case .Polkadot(_, _, let currentBlockNumber, _, _, _, _) = specific else {
            return XCTFail("expected Polkadot case")
        }
        XCTAssertEqual(currentBlockNumber, 0, "malformed current_block_number must decode to 0, not crash")
    }

    func testPolkadotWellFormedCurrentBlockNumberMapsVerbatim() throws {
        let specific = try decodePolkadot(currentBlockNumber: "24680123")
        guard case .Polkadot(_, _, let currentBlockNumber, _, _, _, _) = specific else {
            return XCTFail("expected Polkadot case")
        }
        XCTAssertEqual(currentBlockNumber, BigInt(24_680_123), "well-formed current_block_number must map through unchanged")
    }

    // MARK: - Helpers

    /// Decodes a Solana chain-specific proto through the untrusted-payload path.
    /// A nil `computeLimit` leaves the field unset (absent on the wire).
    private func decodeSolana(priorityFee: String, computeLimit: String?) throws -> BlockChainSpecific {
        var proto = VSSolanaSpecific()
        proto.recentBlockHash = recentBlockHash
        proto.priorityFee = priorityFee
        if let computeLimit {
            proto.computeLimit = computeLimit
        }
        return try BlockChainSpecific(proto: .solanaSpecific(proto))
    }

    private func decodeEthereum(maxFeePerGasWei: String, priorityFee: String, gasLimit: String) throws -> BlockChainSpecific {
        var proto = VSEthereumSpecific()
        proto.maxFeePerGasWei = maxFeePerGasWei
        proto.priorityFee = priorityFee
        proto.nonce = 7
        proto.gasLimit = gasLimit
        return try BlockChainSpecific(proto: .ethereumSpecific(proto))
    }

    private func decodePolkadot(currentBlockNumber: String) throws -> BlockChainSpecific {
        var proto = VSPolkadotSpecific()
        proto.recentBlockHash = recentBlockHash
        proto.nonce = 1
        proto.currentBlockNumber = currentBlockNumber
        proto.specVersion = 1
        proto.transactionVersion = 1
        proto.genesisHash = recentBlockHash
        return try BlockChainSpecific(proto: .polkadotSpecific(proto))
    }
}
