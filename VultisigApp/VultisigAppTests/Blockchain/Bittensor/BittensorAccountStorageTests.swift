//
//  BittensorAccountStorageTests.swift
//  VultisigAppTests
//
//  Coverage for the confirmed-vs-unknown balance distinction CodeRabbit
//  flagged on vultisig-ios#5335: `BittensorService.fetchBalance` collapsed
//  an undecodable address, a malformed RPC response, and a truncated one all
//  into a successful `BigInt.zero` — which the destination-ED guard then
//  read as "confirmed empty", rejecting sends the service simply couldn't
//  evaluate. `BittensorHelper.interpretAccountStorage` is the pure piece of
//  that fix (no network access needed to test the malformed/truncated
//  cases); the undecodable-address case is covered directly against the real
//  `BittensorService` below, since `ss58Decode` fails before any RPC call.
//

import BigInt
import XCTest
@testable import VultisigApp

final class BittensorAccountStorageTests: XCTestCase {

    // MARK: - interpretAccountStorage (pure — no network)

    func testNilResultIsConfirmedZero() {
        // A nil `state_getStorage` response means the storage key doesn't
        // exist — the account has no ledger entry, which IS a confirmed
        // zero balance, not an unknown read.
        XCTAssertEqual(BittensorHelper.interpretAccountStorage(nil), .confirmed(.zero))
    }

    func testEmptyStringResultIsConfirmedZero() {
        XCTAssertEqual(BittensorHelper.interpretAccountStorage(""), .confirmed(.zero))
    }

    func testTruncatedHexIsUnknownNotZero() {
        // Non-empty but shorter than the AccountInfo layout requires
        // (64 hex chars covering nonce/consumers/providers/sufficients/free)
        // is a malformed or truncated read, not a confirmed value.
        XCTAssertEqual(BittensorHelper.interpretAccountStorage("0x1234"), .unknown)
        XCTAssertEqual(BittensorHelper.interpretAccountStorage("1234"), .unknown)
    }

    func testWellFormedHexParsesTheFreeBalanceField() {
        // nonce(4) + consumers(4) + providers(4) + sufficients(4) = 16 hex
        // chars of padding, then free balance (u128 LE) at hex chars 32-63.
        // 1_000_000_000 rao = 0x3B9ACA00, little-endian bytes 00 CA 9A 3B
        // padded to 16 bytes.
        let padding = String(repeating: "0", count: 32)
        let freeLE = "00ca9a3b" + String(repeating: "0", count: 24)
        let hex = "0x" + padding + freeLE

        XCTAssertEqual(BittensorHelper.interpretAccountStorage(hex), .confirmed(BigInt(1_000_000_000)))
    }

    func testWellFormedHexWithoutPrefixParsesTheSame() {
        let padding = String(repeating: "0", count: 32)
        let freeLE = "00ca9a3b" + String(repeating: "0", count: 24)
        let hex = padding + freeLE

        XCTAssertEqual(BittensorHelper.interpretAccountStorage(hex), .confirmed(BigInt(1_000_000_000)))
    }

    // MARK: - Undecodable address (real service, no network reached)

    /// `ss58Decode` fails synchronously before `fetchBalanceRead` ever builds
    /// a storage key or calls the RPC layer, so this exercises the real
    /// `BittensorService` — not a stub — with no network access.
    func testUndecodableAddressIsUnknownNotZero() async throws {
        let unknown = try await BittensorService.shared.getBalanceIfKnown(address: "!!!not-a-valid-ss58-address!!!")
        XCTAssertNil(unknown)
    }

    /// `getBalance` (the wallet-balance-display API, unchanged by this fix)
    /// still collapses the same undecodable address to "0" — confirming the
    /// fix is additive and doesn't alter `BalanceService`'s existing
    /// behavior.
    func testGetBalanceStillReturnsZeroStringForUndecodableAddress() async throws {
        let balance = try await BittensorService.shared.getBalance(address: "!!!not-a-valid-ss58-address!!!")
        XCTAssertEqual(balance, "0")
    }
}
