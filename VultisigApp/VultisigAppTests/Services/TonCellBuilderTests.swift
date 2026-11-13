//
//  TonCellBuilderTests.swift
//  VultisigAppTests
//
//  Expected BOCs are the `@ton/core` vectors Android's TonCellBuilderTest / TonstakersTest pin,
//  so both platforms emit identical Tonstakers bodies.
//

import BigInt
import XCTest
@testable import VultisigApp

final class TonCellBuilderTests: XCTestCase {
    private let ownerFriendly = "EQBfwesEQte6-OnnVoRroXg2Fhs5kKQtfIITGP22CG98-SSR"
    private let ownerRaw = "0:5fc1eb0442d7baf8e9e756846ba17836161b3990a42d7c821318fdb6086f7cf9"

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func testByteAlignedCellMatchesTonCore() throws {
        let cell = try TonCellBuilder().storeUInt(0x47d54391, bits: 32).storeUInt(0, bits: 64).build()
        XCTAssertEqual(hex(TonBocSerializer.serialize(cell)), "b5ee9c7241010101000e00001847d543910000000000000000e9c18654")
        XCTAssertEqual(
            hex(TonBocSerializer.serialize(cell, withCrc32c: false)),
            "b5ee9c7201010101000e00001847d543910000000000000000"
        )
    }

    func testNonAlignedCellGetsCompletionTag() throws {
        let cell = try TonCellBuilder().storeUInt(0b101, bits: 3).build()
        XCTAssertEqual(hex(TonBocSerializer.serialize(cell)), "b5ee9c72410101010003000001b083bd2ec7")
    }

    func testCoinsUseMinimalByteLength() throws {
        let vectors = [
            ("0", "b5ee9c72410101010003000001088597e2ff"),
            ("255", "b5ee9c724101010100040000031ff87c3fbc10"),
            ("256", "b5ee9c72410101010005000005201008b3d22573"),
            ("18446744073709551616", "b5ee9c7241010101000c00001390100000000000000008b53c4a94")
        ]
        for (value, expected) in vectors {
            let cell = try TonCellBuilder().storeCoins(BigInt(value)!).build()
            XCTAssertEqual(hex(TonBocSerializer.serialize(cell)), expected, value)
        }
    }

    func testMasterchainAddressKeepsSignedWorkchain() throws {
        let cell = try TonCellBuilder()
            .storeAddress(raw: "-1:3333333333333333333333333333333333333333333333333333333333333333")
            .build()
        XCTAssertEqual(
            hex(TonBocSerializer.serialize(cell)),
            "b5ee9c724101010100240000439fe6666666666666666666666666666666666666666666666666666666666666667081557149"
        )
    }

    func testDepositBodyIsCanonicalConstant() throws {
        let body = try XCTUnwrap(Data(base64Encoded: Tonstakers.depositBody()))
        XCTAssertEqual(hex(Array(body)), "b5ee9c7241010101000e00001847d543910000000000000000e9c18654")
    }

    func testBurnBodyMatchesTonstakersSdk() throws {
        let body = try Tonstakers.burnBody(amount: BigInt(4_300_000_000), responseAddress: ownerFriendly)
        XCTAssertEqual(
            body,
            "te6cckEBAgEAOQABZllfB7wAAAAAAAAAAFAQBMywCAC/g9YIha918dPOrQjXQvBsLDZzIUha+QQmMftsEN758wEAASBjtrI+"
        )
    }

    func testBurnBodyReadsBackWithTwoBitFlagsCell() throws {
        let body = try XCTUnwrap(Tonstakers.burnBody(amount: BigInt(4_300_000_000), responseAddress: ownerRaw))
        let slice = try TonBocParser.parse(base64: body).beginParse()
        XCTAssertEqual(try slice.loadUInt(bits: 32), 0x595f07bc)
        XCTAssertEqual(try slice.loadUInt(bits: 64), 0)
        XCTAssertEqual(try slice.loadCoins(), "4300000000")
        _ = try slice.loadAddress()
        let flags = try XCTUnwrap(try slice.loadMaybeRef()).beginParse()
        XCTAssertFalse(try flags.loadBit())
        XCTAssertFalse(try flags.loadBit())
        XCTAssertThrowsError(try flags.loadBit())
    }

    func testBurnBodyCarriesRequestedFlags() throws {
        let body = try XCTUnwrap(
            Tonstakers.burnBody(amount: 1, responseAddress: ownerFriendly, waitTillRoundEnd: true, fillOrKill: true)
        )
        let slice = try TonBocParser.parse(base64: body).beginParse()
        _ = try slice.loadUInt(bits: 32)
        _ = try slice.loadUInt(bits: 64)
        _ = try slice.loadCoins()
        _ = try slice.loadAddress()
        let flags = try XCTUnwrap(try slice.loadMaybeRef()).beginParse()
        XCTAssertTrue(try flags.loadBit())
        XCTAssertTrue(try flags.loadBit())
    }

    func testBurnBodyRefusesNonTonResponseAddress() throws {
        XCTAssertNil(try Tonstakers.burnBody(amount: 1, responseAddress: "not-an-address"))
    }

    func testDepositValueAddsPoolFee() {
        XCTAssertEqual(Tonstakers.depositValue(stakeAmount: BigInt(5_000_000_000)), BigInt(6_000_000_000))
        XCTAssertEqual(Tonstakers.minimumDepositValue(), BigInt(2_000_000_000))
        XCTAssertEqual(Tonstakers.minimumDepositValue(minStake: 0), BigInt(2_000_000_000))
        XCTAssertEqual(Tonstakers.minimumDepositValue(minStake: BigInt(2_500_000_000)), BigInt(3_500_000_000))
    }

    func testRecognisesPoolInEverySpelling() {
        XCTAssertTrue(Tonstakers.isPool(Tonstakers.poolAddress))
        XCTAssertTrue(Tonstakers.isPool("UQCkWxfyhAkim3g2DjKQQg8T5P4g-Q1-K_jErGcDJZ4i-qdU"))
        XCTAssertTrue(Tonstakers.isPool("0:A45B17F28409229B78360E3290420F13E4FE20F90D7E2BF8C4AC6703259E22FA"))
        XCTAssertFalse(Tonstakers.isPool(ownerFriendly))
        XCTAssertFalse(Tonstakers.isPool(""))
    }

    func testFriendlyToRaw() {
        XCTAssertEqual(tonFriendlyToRaw(ownerFriendly), ownerRaw)
        XCTAssertEqual(tonFriendlyToRaw("UQBfwesEQte6-OnnVoRroXg2Fhs5kKQtfIITGP22CG98-XlU"), ownerRaw)
        XCTAssertEqual(tonFriendlyToRaw("EQBfwesEQte6+OnnVoRroXg2Fhs5kKQtfIITGP22CG98+SSR"), ownerRaw)
        XCTAssertEqual(tonFriendlyToRaw(ownerRaw), ownerRaw)
        XCTAssertNil(tonFriendlyToRaw("0:1234"))
        XCTAssertNil(tonFriendlyToRaw(""))
    }

    func testBuilderRejectsOverflow() throws {
        XCTAssertThrowsError(try TonCellBuilder().storeUInt(256, bits: 8))
        XCTAssertThrowsError(try TonCellBuilder().storeCoins(BigInt(-1)))
        XCTAssertThrowsError(try TonCellBuilder().storeCoins(BigInt(1) << 120))
        XCTAssertThrowsError(try TonCellBuilder().storeAddress(raw: "0:1234"))
        let builder = TonCellBuilder()
        for _ in 0..<1023 { try builder.storeBit(false) }
        XCTAssertThrowsError(try builder.storeBit(false))
        let refs = TonCellBuilder()
        let leaf = TonCellBuilder().build()
        for _ in 0..<4 { try refs.storeRef(leaf) }
        XCTAssertThrowsError(try refs.storeRef(leaf))
    }
}
