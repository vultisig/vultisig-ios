//
//  HyperliquidContractDiscrepancyTests.swift
//  VultisigAppTests
//
//  Two places where the vultisig-sdk order contract doc
//  (clients/cli/docs/hyperliquid-order-contract.md, origin/main cc88d4976)
//  disagrees with the official Python SDK. Each has a test that passes (the
//  hashes really differ) and one marked `XCTExpectFailure` that states the
//  contract's assumption and fails, so the suite stays green while the
//  mismatch stays visible. Expected values come from hyperliquid-python-sdk
//  (VultisigAppTests/Perps/Vectors/gen_exchange_sdk.py, `discrepancies`).
//

import XCTest
@testable import VultisigApp

final class HyperliquidContractDiscrepancyTests: XCTestCase {
    /// The contract doc's example order: keys a,b,p,r,s,t and p "30000.0".
    private static let contractExample = HLValue.object([
        ("type", .string("order")),
        ("orders", .array([.object([
            ("a", .int(0)), ("b", .bool(true)), ("p", .string("30000.0")),
            ("r", .bool(false)), ("s", .string("0.001")),
            ("t", .object([("limit", .object([("tif", .string("Gtc"))]))]))
        ])])),
        ("grouping", .string("na"))
    ])

    /// Only the key order fixed (a,b,p,s,r,t), "30000.0" kept.
    private static let keyOrderFixed = HLValue.object([
        ("type", .string("order")),
        ("orders", .array([.object([
            ("a", .int(0)), ("b", .bool(true)), ("p", .string("30000.0")),
            ("s", .string("0.001")), ("r", .bool(false)),
            ("t", .object([("limit", .object([("tif", .string("Gtc"))]))]))
        ])])),
        ("grouping", .string("na"))
    ])

    /// What the Python SDK builds for the same order.
    private static var canonical: HLValue {
        HLActions.order([HLOrderWire(asset: 0, isBuy: true, price: HLWireFormat.decimalString(30000), size: "0.001",
                                     reduceOnly: false, type: .limit(.gtc))])
    }

    private func connectionId(_ action: HLValue) throws -> String {
        try HLActionHasher.connectionId(action: action, nonce: 2, vaultAddress: nil).hexString
    }

    // MARK: 1. Key order a,b,p,r,s,t vs a,b,p,s,r,t

    func testKeyOrderChangesTheSignedBytes() throws {
        XCTAssertEqual(try connectionId(Self.contractExample), "6c938d29790e8bddbd876ccffff801db90bd459e814dddc034d743a634b39715")
        XCTAssertEqual(try connectionId(Self.keyOrderFixed), "9f6bee2480472d99b641e8e9e5f6750cc50e3590ecea8366c0a8608435418d28")
        XCTAssertNotEqual(try connectionId(Self.contractExample), try connectionId(Self.keyOrderFixed),
                          "Swapping r and s alone changes the hash, so key order is part of the contract")
    }

    func testContractKeyOrderMatchesSDK() throws {
        XCTExpectFailure("Contract doc orders r before s; the SDK's order_request_to_order_wire emits a,b,p,s,r,t") {
            let contractKeys = Self.contractExample["orders"].flatMap { orders -> [String]? in
                guard case .array(let items) = orders, case .map(let entries)? = items.first else { return nil }
                return entries.map(\.key)
            }
            XCTAssertEqual(contractKeys, ["a", "b", "p", "s", "r", "t"])
        }
    }

    // MARK: 2. "30000.0" vs "30000"

    func testTrailingZeroChangesTheSignedBytes() throws {
        XCTAssertEqual(HLWireFormat.decimalString(30000), "30000", "matches the SDK's float_to_wire(30000.0)")
        XCTAssertEqual(try connectionId(Self.canonical), "2f54f919e286785cc31af0928e81d322aa1e9e9044a2801ede266058e88989c0")
        XCTAssertNotEqual(try connectionId(Self.keyOrderFixed), try connectionId(Self.canonical),
                          "With the key order fixed, the trailing zero alone still changes the hash")
    }

    func testContractPriceStringMatchesSDK() {
        XCTExpectFailure("Contract doc signs p \"30000.0\"; the SDK's float_to_wire normalises to \"30000\"") {
            XCTAssertEqual("30000.0", HLWireFormat.decimalString(30000))
        }
    }
}
