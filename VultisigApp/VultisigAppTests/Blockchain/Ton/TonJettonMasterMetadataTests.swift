//
//  TonJettonMasterMetadataTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TonJettonMasterMetadataTests: XCTestCase {

    private func index(from json: String) throws -> [String: TonJettonMasterMetadata] {
        let page = try JSONDecoder().decode(JettonWalletsResponse.self, from: Data(json.utf8))
        return TonJettonMasterMetadata.index(from: page.metadata)
    }

    private func indexFromRecordedPage() throws -> [String: TonJettonMasterMetadata] {
        try index(from: TonJettonFixtures.ownerJettonWalletsPage)
    }

    /// The filter the whole discovery path depends on. Toncenter marks the
    /// owner's jetton *wallet* entries `valid: true` as well, and those carry no
    /// symbol or name — so selecting on `valid` alone reads every master as
    /// nameless and classifies every jetton as unverified. In the recorded page
    /// the DOGS master lists a wallet-typed entry *before* its master-typed one,
    /// which is what makes this assertion bite.
    func testWalletTypedEntriesAreNeverMistakenForMasters() throws {
        let index = try indexFromRecordedPage()
        let dogs = try XCTUnwrap(TonJettonAddress.canonical(TonJettonFixtures.dogsMasterRaw))

        XCTAssertEqual(index[dogs]?.symbol, "DOGS")
        XCTAssertEqual(index[dogs]?.name, "Dogs")
        XCTAssertEqual(index[dogs]?.decimals, 9)
    }

    /// Wallet addresses have entries in the same map and must not appear in an
    /// index of masters.
    func testWalletAddressesAreNotIndexed() throws {
        let index = try indexFromRecordedPage()
        let walletAddress = try XCTUnwrap(
            TonJettonAddress.canonical("0:AA01000000000000000000000000000000000000000000000000000000000001")
        )
        XCTAssertNil(index[walletAddress])
    }

    func testIndexIsKeyedByCanonicalAddress() throws {
        let index = try indexFromRecordedPage()
        let tether = try XCTUnwrap(TonJettonAddress.canonical(TonJettonFixtures.usdtMasterRawLower))

        XCTAssertEqual(index[tether]?.symbol, "USD₮")
        XCTAssertEqual(index[tether]?.decimals, 6)
        XCTAssertEqual(index[tether]?.isFlaggedScam, false)
    }

    /// The imgproxy rendition is preferred over the original `image` URL.
    func testImgproxyRenditionIsPreferredForTheLogo() throws {
        let index = try indexFromRecordedPage()
        let dogs = try XCTUnwrap(TonJettonAddress.canonical(TonJettonFixtures.dogsMasterRaw))
        XCTAssertEqual(index[dogs]?.logo, TonJettonFixtures.dogsLogo)
    }

    /// A typed master entry always wins, even when an untyped one is listed
    /// first — otherwise a wallet entry that simply lost its `type` would
    /// supply the metadata and the master's symbol would go unread.
    func testTypedMasterEntryWinsOverAnUntypedOne() throws {
        let index = try index(from: TonJettonFixtures.pageWithUntypedEntryBeforeMaster)
        let dogs = try XCTUnwrap(TonJettonAddress.canonical(TonJettonFixtures.dogsMasterRaw))

        XCTAssertEqual(index[dogs]?.symbol, "DOGS")
        XCTAssertEqual(index[dogs]?.decimals, 9)
        XCTAssertEqual(index[dogs]?.logo, TonJettonFixtures.dogsLogo)
    }

    /// An untyped entry is still read when it is all there is. If Toncenter ever
    /// stops emitting `type`, the fallback is the difference between degraded
    /// metadata and no metadata at all — and no metadata would classify every
    /// jetton on the chain as unverified and quietly stop discovery.
    func testUntypedEntryIsReadWhenNoMasterEntryExists() throws {
        let index = try index(from: TonJettonFixtures.pageWithUntypedMasterEntry)
        let dogs = try XCTUnwrap(TonJettonAddress.canonical(TonJettonFixtures.dogsMasterRaw))

        XCTAssertEqual(index[dogs]?.symbol, "DOGS")
        XCTAssertEqual(index[dogs]?.decimals, 9)
    }

    /// The degraded case the untyped fallback exists for is also the one where
    /// it is easiest to read the wrong record: with no `type` anywhere, a
    /// balance-only wallet entry is indistinguishable from a master entry by
    /// type alone. Requiring a symbol or a name is what separates them — and
    /// getting it wrong would lose the jetton's real decimals and leave the
    /// default standing in, which is a wrong balance and a wrong amount.
    func testUntypedWalletRecordIsNotReadAsTheMaster() throws {
        let index = try index(from: TonJettonFixtures.pageWithUntypedWalletBeforeUntypedMaster)
        let jusdt = try XCTUnwrap(TonJettonAddress.canonical(TonJettonFixtures.jusdtMasterRaw))

        XCTAssertEqual(index[jusdt]?.symbol, "jUSDT")
        XCTAssertEqual(index[jusdt]?.decimals, 6, "the master's real decimals, not the 9 default")
    }

    func testAbsentMetadataIndexesToNothing() {
        XCTAssertTrue(TonJettonMasterMetadata.index(from: nil).isEmpty)
    }
}
