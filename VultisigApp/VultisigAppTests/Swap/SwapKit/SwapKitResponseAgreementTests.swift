//
//  SwapKitResponseAgreementTests.swift
//  VultisigAppTests
//
//  SwapKit states the deposit destination in three independent fields and the
//  payload builder reads only `targetAddress`. These pin that a response which
//  disagrees with itself is refused rather than resolved by precedence — while
//  the several spellings of one TON account still compare equal, and every
//  recorded real response still passes.
//

import XCTest
@testable import VultisigApp

final class SwapKitResponseAgreementTests: XCTestCase {

    // The account SwapKit returns in `v3-real-ton-swap.json`, in each spelling.
    private let tonBounceable = "EQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlhxmd"
    private let tonNonBounceable = "UQC_BuLzOqk9GGNXh0y1XosB2BqUyk1AQcGMHKMGfRqlh0RY"
    private let tonRaw = "0:bf06e2f33aa93d186357874cb55e8b01d81a94ca4d4041c18c1ca3067d1aa587"
    private let tonOtherAccount = "EQCrq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq8Uk"
    private let xrpAddress = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"

    // MARK: - Destination divergence

    func testRejectsTonTransferAddressNamingADifferentAccountThanTargetAddress() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonBounceable,
            tx: #"[{"address":"\#(tonOtherAccount)","amount":"5000000000"}]"#
        ))
        assertContradiction(response, chain: .ton, mentioning: "tx[0].address")
    }

    func testRejectsInboundAddressDivergingFromTargetAddress() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonBounceable,
            inboundAddress: tonOtherAccount,
            tx: #"[{"address":"\#(tonBounceable)","amount":"5000000000"}]"#
        ))
        assertContradiction(response, chain: .ton, mentioning: "inboundAddress")
    }

    /// Divergence with no `tx[]` involved at all — the deposit-only shape (XRP, ADA).
    func testRejectsInboundAddressDivergingOnADepositOnlyRoute() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh",
            inboundAddress: "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "inboundAddress")
    }

    /// Base58 is case-sensitive: two addresses differing only by case are two
    /// different addresses, and normalising case away would let them pass as one.
    func testRejectsNonTonDivergenceDifferingOnlyByCase() throws {
        let target = "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh"
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: target,
            inboundAddress: target.lowercased()
        ))
        assertContradiction(response, chain: .ripple, mentioning: "inboundAddress")
    }

    // MARK: - TON spellings are not divergence

    func testAcceptsOneTonAccountSpelledBounceableInOneFieldAndNonBounceableInAnother() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonBounceable,
            inboundAddress: tonNonBounceable,
            tx: #"[{"address":"\#(tonNonBounceable)","amount":"5000000000"}]"#
        ))
        XCTAssertNoThrow(try response.validateSelfAgreement(fromChain: .ton))
    }

    func testAcceptsARawTonSpellingAgainstAUserFriendlyOne() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonNonBounceable,
            tx: #"[{"address":"\#(tonRaw)","amount":"5000000000"}]"#
        ))
        XCTAssertNoThrow(try response.validateSelfAgreement(fromChain: .ton))
    }

    // MARK: - Transfer cardinality

    func testRejectsAMultiEntryTonTransferArray() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonBounceable,
            tx: #"""
            [{"address":"\#(tonBounceable)","amount":"5000000000"},
             {"address":"\#(tonBounceable)","amount":"2000000000"}]
            """#
        ))
        assertContradiction(response, chain: .ton, mentioning: "2 transfers")
    }

    func testRejectsAnEmptyTonTransferArray() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonBounceable,
            tx: "[]"
        ))
        assertContradiction(response, chain: .ton, mentioning: "0 transfers")
    }

    // MARK: - Missing primary

    func testRejectsABlankTargetAddressEvenWhenOtherFieldsNameADestination() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: "   ",
            inboundAddress: tonBounceable,
            tx: #"[{"address":"\#(tonBounceable)","amount":"5000000000"}]"#
        ))
        assertContradiction(response, chain: .ton, mentioning: "targetAddress is empty")
    }

    // MARK: - Blank corroborating fields are not agreement

    func testRejectsABlankInboundAddress() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonBounceable,
            inboundAddress: "",
            tx: #"[{"address":"\#(tonBounceable)","amount":"5000000000"}]"#
        ))
        assertContradiction(response, chain: .ton, mentioning: "inboundAddress is empty")
    }

    func testRejectsABlankTonTransferAddress() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: tonBounceable,
            tx: #"[{"address":"","amount":"5000000000"}]"#
        ))
        assertContradiction(response, chain: .ton, mentioning: "tx[0].address is empty")
    }

    /// A TON route whose destination does not parse as a TON account is refused
    /// rather than passed through on string equality.
    func testRejectsATonDestinationThatIsNotAnAccount() throws {
        let response = try decode(makeJSON(
            sellAsset: "TON.TON",
            txType: "TON",
            targetAddress: "not-a-ton-address",
            tx: #"[{"address":"not-a-ton-address","amount":"5000000000"}]"#
        ))
        assertContradiction(response, chain: .ton, mentioning: "tx[0].address")
    }

    // MARK: - Destination tags are half the XRP destination

    /// The address comparison strips the tag suffix on purpose, so without a separate
    /// tag check two fields naming one address with different tags would agree — and
    /// the deposit would land credited to a different account at the exchange.
    func testRejectsConflictingTagSuffixesOnOneAddress() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh?dt=1",
            inboundAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh?dt=2"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "inboundAddress tag suffix")
    }

    func testRejectsATopLevelTagConflictingWithTheTargetAddressSuffix() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh?dt=300",
            topLevelTagJSON: "100"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "destinationTag is 100")
    }

    func testRejectsAMetaTagConflictingWithTheTopLevelTag() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh",
            topLevelTagJSON: "100",
            metaTagJSON: "200"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "meta.destinationTag is 200")
    }

    /// Agreeing tags across all three sources are not a contradiction, and one
    /// destination spelled with the suffix in one field and without it in another
    /// still names one destination.
    func testAcceptsAgreeingTagsStatedInSeveralFields() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh?dt=7",
            inboundAddress: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh",
            topLevelTagJSON: "7"
        ))
        XCTAssertNoThrow(try response.validateSelfAgreement(fromChain: .ripple))
    }

    // MARK: - A tag that cannot be read is not an absent tag

    // Each source is covered on its own: collapsing "unreadable" into "absent" anywhere
    // sends a tag-less deposit to an address where the tag identifies the depositor.

    func testRejectsAnUnreadableTopLevelDestinationTag() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: xrpAddress,
            topLevelTagJSON: "\"abc\""
        ))
        assertContradiction(response, chain: .ripple, mentioning: "destinationTag states a destination tag")
    }

    func testRejectsAnUnreadableMetaDestinationTag() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: xrpAddress,
            metaTagJSON: "\"not-a-tag\""
        ))
        assertContradiction(response, chain: .ripple, mentioning: "meta.destinationTag states a destination tag")
    }

    func testRejectsAnUnreadableTargetAddressTagSuffix() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "\(xrpAddress)?dt=bogus"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "targetAddress tag suffix")
    }

    /// Two `dt` parameters is two answers. Silently taking the first is a guess.
    func testRejectsDuplicateTargetAddressTagParameters() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "\(xrpAddress)?dt=1&dt=2"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "2 dt parameters")
    }

    func testRejectsAnUnreadableInboundAddressTagSuffix() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: xrpAddress,
            inboundAddress: "\(xrpAddress)?dt=bogus"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "inboundAddress tag suffix")
    }

    func testRejectsDuplicateInboundAddressTagParameters() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: xrpAddress,
            inboundAddress: "\(xrpAddress)?dt=1&dt=2"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "2 dt parameters")
    }

    func testRejectsAnUnreadablePipeTagSuffix() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "\(xrpAddress)|bogus"
        ))
        assertContradiction(response, chain: .ripple, mentioning: "targetAddress tag suffix")
    }

    /// A query string carrying no `dt` at all states no tag — that really is absent, and
    /// must not be swept up by the unreadable check.
    func testAcceptsAnAddressWhoseQueryCarriesNoTag() throws {
        let response = try decode(makeJSON(
            sellAsset: "XRP.XRP",
            txType: "XRP",
            targetAddress: "\(xrpAddress)?memo=foo"
        ))
        XCTAssertNoThrow(try response.validateSelfAgreement(fromChain: .ripple))
    }

    // MARK: - No false rejections

    /// An EVM route states the destination once (`inboundAddress` is omitted and
    /// `tx` is an object), so there is nothing to corroborate and nothing to reject.
    func testAcceptsAnEvmResponseWithNoCorroboratingFields() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        XCTAssertNoThrow(try response.validateSelfAgreement(fromChain: .ethereum))
    }

    /// The guard is only worth having if it never fires on a healthy route. Every
    /// recorded real `/v3/swap` response must pass the whole gate unchanged.
    func testAcceptsEveryRecordedRealResponse() throws {
        let fixtures: [(name: String, chain: Chain)] = [
            ("v3-real-ton-swap", .ton),
            ("v3-real-xrp-swap", .ripple),
            ("v3-real-ada-swap", .cardano),
            ("v3-real-ada-cbor-swap", .cardano),
            ("v3-real-ada-cbor-prebuilt-swap", .cardano),
            ("v3-real-btc-all-swap", .bitcoin),
            ("v3-real-btc-FLASHNET-swap", .bitcoin),
            ("v3-real-btc-GARDEN-swap", .bitcoin),
            ("v3-real-bch-swap", .bitcoinCash),
            ("v3-real-dash-swap", .dash),
            ("v3-real-doge-swap", .dogecoin),
            ("v3-real-zec-swap", .zcash),
            ("v3-sol-near-swap-fresh", .solana),
            ("v3-sui-swap-fresh", .sui),
            ("v3-tron-final-swap-fresh", .tron),
            ("v3-erc20-erc20-swap", .ethereum),
            ("v3-flashnet-evm-usdc-btc-swap", .ethereum)
        ]
        for fixture in fixtures {
            let response = try SwapKitFixtureLoader.decode(
                SwapKitSwapResponse.self,
                from: fixture.name
            )
            XCTAssertNoThrow(
                try SwapKitService.validateSigningCapability(
                    response: response,
                    fromChain: fixture.chain
                ),
                "\(fixture.name) is a healthy recorded response and must not be rejected"
            )
        }
    }

    // MARK: - Helpers

    private func assertContradiction(
        _ response: SwapKitSwapResponse,
        chain: Chain,
        mentioning fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try response.validateSelfAgreement(fromChain: chain),
            file: file,
            line: line
        ) { error in
            guard let swapKitError = error as? SwapKitError,
                  case .contradictoryResponse(let detail) = swapKitError else {
                return XCTFail("expected contradictoryResponse, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(
                detail.contains(fragment),
                "detail \(detail) should name \(fragment)",
                file: file,
                line: line
            )
        }
    }

    private func decode(_ json: String) throws -> SwapKitSwapResponse {
        try JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
    }

    private func makeJSON(
        sellAsset: String,
        txType: String,
        targetAddress: String,
        inboundAddress: String? = nil,
        tx: String? = nil,
        topLevelTagJSON: String? = nil,
        metaTagJSON: String? = nil
    ) -> String {
        let inbound = inboundAddress.map { ",\"inboundAddress\":\"\($0)\"" } ?? ""
        let txField = tx.map { ",\"tx\":\($0)" } ?? ""
        let topTag = topLevelTagJSON.map { ",\"destinationTag\":\($0)" } ?? ""
        let metaTagField = metaTagJSON.map { ",\"destinationTag\":\($0)" } ?? ""
        return """
        {
            "swapId":"abc",
            "routeId":"def",
            "providers":["NEAR"],
            "sellAsset":"\(sellAsset)",
            "buyAsset":"ETH.USDC",
            "sellAmount":"5",
            "expectedBuyAmount":"100",
            "expectedBuyAmountMaxSlippage":"99",
            "sourceAddress":"source",
            "destinationAddress":"0x0",
            "targetAddress":"\(targetAddress)",
            "meta":{"txType":"\(txType)"\(metaTagField)},
            "fees":[]
            \(inbound)
            \(txField)
            \(topTag)
        }
        """
    }
}
