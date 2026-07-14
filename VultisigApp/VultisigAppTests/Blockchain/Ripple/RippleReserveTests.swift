//
//  RippleReserveTests.swift
//  VultisigAppTests
//
//  Pins the owner-aware XRPL reserve math: the reserve floor is
//  `reserve_base + OwnerCount × reserve_inc`, and the spendable balance is the
//  total minus that floor, clamped at zero. This is the single source of truth
//  the balance calc (and, via `rawBalance`, the MAX-send path) consume.
//
//  - https://xrpl.org/docs/concepts/accounts/reserves
//

@testable import VultisigApp
import XCTest
import BigInt

final class RippleReserveTests: XCTestCase {

    // MARK: - reservedDrops

    func testReservedDropsBaseOnlyWhenOwnerCountZero() {
        // No owned objects → the floor is the base reserve alone (1 XRP).
        let reserved = RippleReserve.reservedDrops(ownerCount: 0, reserveBase: 1_000_000, reserveInc: 200_000)
        XCTAssertEqual(reserved, BigInt(1_000_000))
    }

    func testReservedDropsAddsIncrementPerOwnedObject() {
        // Acceptance case: OwnerCount > 0. Five owned objects (trustlines,
        // offers, tickets, …) → 1 XRP base + 5 × 0.2 XRP = 2 XRP.
        let reserved = RippleReserve.reservedDrops(ownerCount: 5, reserveBase: 1_000_000, reserveInc: 200_000)
        XCTAssertEqual(reserved, BigInt(2_000_000))
    }

    func testReservedDropsUsesSeedsWhenServerStateFieldsMissing() {
        // Missing server_state fields fall back to the mainnet seeds; a
        // missing owner count counts as zero owned objects.
        XCTAssertEqual(
            RippleReserve.reservedDrops(ownerCount: nil, reserveBase: nil, reserveInc: nil),
            RippleReserve.seedReserveBaseDrops
        )
        XCTAssertEqual(
            RippleReserve.reservedDrops(ownerCount: 3, reserveBase: nil, reserveInc: nil),
            RippleReserve.seedReserveBaseDrops + 3 * RippleReserve.seedReserveIncDrops
        )
    }

    func testReservedDropsTracksLiveServerStateValues() {
        // A validator vote can change the reserves; the math must follow the
        // live values, not the seeds.
        let reserved = RippleReserve.reservedDrops(ownerCount: 2, reserveBase: 10_000_000, reserveInc: 2_000_000)
        XCTAssertEqual(reserved, BigInt(14_000_000))
    }

    // MARK: - availableDrops

    func testAvailableDropsClampsToZeroBelowReserve() {
        // Total below the floor → 0 spendable, never negative.
        let available = RippleReserve.availableDrops(
            totalDrops: BigInt(900_000),
            ownerCount: 0,
            reserveBase: 1_000_000,
            reserveInc: 200_000
        )
        XCTAssertEqual(available, BigInt(0))
    }

    func testAvailableDropsSubtractsOwnerAwareReserve() {
        // 10 XRP total, 3 owned objects → 10 − (1 + 3 × 0.2) = 8.4 XRP.
        let available = RippleReserve.availableDrops(
            totalDrops: BigInt(10_000_000),
            ownerCount: 3,
            reserveBase: 1_000_000,
            reserveInc: 200_000
        )
        XCTAssertEqual(available, BigInt(8_400_000))
    }

    func testAvailableDropsEqualsTotalMinusBaseWhenNoOwnedObjects() {
        let available = RippleReserve.availableDrops(
            totalDrops: BigInt(5_000_000),
            ownerCount: nil,
            reserveBase: 1_000_000,
            reserveInc: 200_000
        )
        XCTAssertEqual(available, BigInt(4_000_000))
    }
}
