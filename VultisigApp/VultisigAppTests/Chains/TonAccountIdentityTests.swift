//
//  TonAccountIdentityTests.swift
//  VultisigAppTests
//
//  One TON account has several spellings. These pin that a comparison which
//  claims two forms name the same account is asserting exactly that, and is not
//  quietly comparing two different accounts.
//

import XCTest
@testable import VultisigApp

final class TonAccountIdentityTests: XCTestCase {

    // One account in every spelling it has. Derived from the account SwapKit
    // actually returns in `v3-real-ton-swap.json` (tag 0x51, workchain 0).
    private let bounceable = "EQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlhxmd"
    private let nonBounceable = "UQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlh0RY"
    private let nonBounceableStandardBase64 = "UQC/BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlh0RY"
    private let raw = "0:bf06e2f33aa93d186357874cb55e8b01d81a94ca4d4041c18c1ca3067d1aa587"
    private let otherAccount = "EQCrq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq8Uk"

    func testTreatsBounceableAndNonBounceableAsOneAccount() {
        XCTAssertTrue(TonAccountIdentity.isSameAccount(bounceable, nonBounceable))
    }

    func testTreatsUserFriendlyAndRawAsOneAccount() {
        XCTAssertTrue(TonAccountIdentity.isSameAccount(bounceable, raw))
        XCTAssertTrue(TonAccountIdentity.isSameAccount(nonBounceable, raw))
    }

    func testTreatsBase64UrlAndStandardBase64AsOneAccount() {
        XCTAssertTrue(TonAccountIdentity.isSameAccount(nonBounceable, nonBounceableStandardBase64))
    }

    func testIgnoresSurroundingWhitespace() {
        XCTAssertTrue(TonAccountIdentity.isSameAccount(bounceable, " \(bounceable) "))
    }

    func testSeparatesTwoDifferentAccountsInEverySpelling() {
        XCTAssertFalse(TonAccountIdentity.isSameAccount(bounceable, otherAccount))
        XCTAssertFalse(TonAccountIdentity.isSameAccount(nonBounceable, otherAccount))
        XCTAssertFalse(TonAccountIdentity.isSameAccount(raw, otherAccount))
    }

    /// Two values that name no account do not name the same account. Reporting
    /// "equal" for two identical unparseable strings would let a fail-closed guard
    /// built on this claim agreement about something that is not an address.
    func testRefusesToMatchInputThatIsNotAnAddress() {
        XCTAssertFalse(TonAccountIdentity.isSameAccount("not-an-address", "not-an-address"))
        XCTAssertFalse(TonAccountIdentity.isSameAccount("not-an-address", bounceable))
        XCTAssertFalse(TonAccountIdentity.isSameAccount("", ""))
        XCTAssertFalse(TonAccountIdentity.isSameAccount("", bounceable))
        // A friendly address with a corrupted checksum names no account either.
        XCTAssertFalse(TonAccountIdentity.isSameAccount(
            "EQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlhAAA",
            "EQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlhAAA"
        ))
    }
}
