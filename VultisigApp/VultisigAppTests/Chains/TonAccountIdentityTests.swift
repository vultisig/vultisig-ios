//
//  TonAccountIdentityTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TonAccountIdentityTests: XCTestCase {

    // One account in every spelling it has, so a test claiming two forms match is
    // asserting that rather than comparing two different accounts.
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

    /// Two values that name no account do not name the same account.
    func testRefusesToMatchInputThatIsNotAnAddress() {
        XCTAssertFalse(TonAccountIdentity.isSameAccount("not-an-address", "not-an-address"))
        XCTAssertFalse(TonAccountIdentity.isSameAccount("not-an-address", bounceable))
        XCTAssertFalse(TonAccountIdentity.isSameAccount("", ""))
        XCTAssertFalse(TonAccountIdentity.isSameAccount("", bounceable))
        XCTAssertFalse(TonAccountIdentity.isSameAccount(
            "EQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlhAAA",
            "EQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlhAAA"
        ))
    }
}
