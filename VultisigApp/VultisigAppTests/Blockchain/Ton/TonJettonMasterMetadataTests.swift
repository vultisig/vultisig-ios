//
//  TonJettonMasterMetadataTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TonJettonMasterMetadataTests: XCTestCase {

    private func indexFromRecordedPage() throws -> [String: TonJettonMasterMetadata] {
        let page = try JSONDecoder().decode(
            JettonWalletsResponse.self,
            from: Data(TonJettonFixtures.ownerJettonWalletsPage.utf8)
        )
        return TonJettonMasterMetadata.index(from: page.metadata)
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

    func testAbsentMetadataIndexesToNothing() {
        XCTAssertTrue(TonJettonMasterMetadata.index(from: nil).isEmpty)
    }
}
