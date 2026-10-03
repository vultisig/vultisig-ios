import XCTest
@testable import VultisigApp

final class TransactionActivityStateTests: XCTestCase {
    func testPrivatePayloadOmitsDetails() throws {
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                             summary: "secret amount", network: "secret network",
                                             operation: .swap, recipient: "secret recipient", fee: "secret fee",
                                             provider: "secret provider", submittedAt: Date(), sourceAssetID: "usdc", destinationAssetID: "eth",
                                             sourceSummary: "secret amount", destinationTicker: "secret token")
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(state), encoding: .utf8))
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertNil(state.summary)
        XCTAssertNil(state.network)
        XCTAssertNil(state.sourceAssetID)
        XCTAssertNil(state.destinationAssetID)
        XCTAssertFalse(encoded.contains("AssetID"))
        XCTAssertFalse(state.hasDetails)
    }

    func testCombinedPayloadStaysUnderFourKilobytesWithLongUnicode() throws {
        let state = TransactionActivityState(phase: .swapping, observedAt: Date(), revision: Int.max,
                                             summary: String(repeating: "🪙", count: 500),
                                             network: String(repeating: "界", count: 500), showDetails: true,
                                             operation: .swap, recipient: String(repeating: "x", count: 100),
                                             fee: String(repeating: "\"", count: 500), provider: String(repeating: "\"", count: 500),
                                             submittedAt: Date(), sourceAssetID: "usdc", destinationAssetID: "solana",
                                             sourceImageKey: String(repeating: "a", count: 64),
                                             destinationImageKey: String(repeating: "b", count: 64),
                                             sourceSummary: String(repeating: "\"", count: 500),
                                             destinationTicker: String(repeating: "\"", count: 500))
        #if os(iOS)
        let attributes = TransactionActivityAttributes(recordID: UUID())
        let size = try JSONEncoder().encode(attributes).count + JSONEncoder().encode(state).count
        XCTAssertLessThan(size, 4_096)
        #endif
    }

    func testCombiningCharactersAndEscapesStayBounded() throws {
        let text = "a" + String(repeating: "\u{0301}", count: 10_000)
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                             summary: text, network: text, showDetails: true,
                                             recipient: text, fee: text, provider: text)
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(state).count, 3_500)
        XCTAssertLessThanOrEqual(state.summary?.utf8.count ?? 0, 240)
    }

    func testStaleIsSeparateFromOutcome() {
        let date = Date(timeIntervalSince1970: 100)
        let state = TransactionActivityState(phase: .sourceConfirmed, observedAt: date, revision: 1)
        XCTAssertFalse(state.phase.isTerminal)
        XCTAssertEqual(state.staleDate, date.addingTimeInterval(TransactionActivityStaleness.floor))
        XCTAssertNil(TransactionActivityState(phase: .confirmed, observedAt: date, revision: 2).staleDate)
    }

    func testStaleDateUsesTheProvidedStaleWindowAndStaysNilWhenTerminal() {
        let date = Date(timeIntervalSince1970: 100)
        let state = TransactionActivityState(phase: .pending, observedAt: date, revision: 1, staleWindow: 500)
        XCTAssertEqual(state.staleDate, date.addingTimeInterval(500))
        let terminal = TransactionActivityState(phase: .confirmed, observedAt: date, revision: 1, staleWindow: 500)
        XCTAssertNil(terminal.staleDate)
    }

    func testStaleWindowRoundTripsThroughEncodingAndDefaultsForOlderPayloads() throws {
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1, staleWindow: 777)
        let decoded = try JSONDecoder().decode(TransactionActivityState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.staleWindow, 777)
        let original = Data(#"{"schemaVersion":1,"phase":"pending","observedAt":42,"revision":1,"updateDelayed":false}"#.utf8)
        let legacy = try JSONDecoder().decode(TransactionActivityState.self, from: original)
        XCTAssertEqual(legacy.staleWindow, TransactionActivityStaleness.floor)
    }

    func testElapsedTimeAnchorTracksSubmittedAtOnlyWhileNonTerminal() {
        let submittedAt = Date(timeIntervalSince1970: 200)
        let inProgress = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                                   showDetails: true, submittedAt: submittedAt)
        XCTAssertEqual(inProgress.elapsedTimeAnchor, submittedAt)
        let terminal = TransactionActivityState(phase: .confirmed, observedAt: Date(), revision: 1,
                                                 showDetails: true, submittedAt: submittedAt)
        XCTAssertNil(terminal.elapsedTimeAnchor)
        let privateMode = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                                    submittedAt: submittedAt)
        XCTAssertNil(privateMode.submittedAt)
        XCTAssertNil(privateMode.elapsedTimeAnchor)
    }

    func testRichPayloadCannotContainFullRecipient() {
        let address = "0x1234567890123456789012345678901234567890"
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                             showDetails: true, recipient: address)
        XCTAssertEqual(state.recipient, "0x12…7890")
        XCTAssertNotEqual(state.recipient, address)
    }

    func testAssetIDsRejectURLsArbitraryPathsAndTickerAliases() {
        for invalid in ["https://example.com/eth.svg", "../eth", "ETH", "ethereum", "definitely-not-an-asset", String(repeating: "x", count: 10_000)] {
            let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                                 showDetails: true, sourceAssetID: invalid, destinationAssetID: invalid)
            XCTAssertNil(state.sourceAssetID)
            XCTAssertNil(state.destinationAssetID)
        }
        for logo in ["btc", "eth", "usdc", "usdt", "bsc", "solana", "rune", "chain-rune", "logo-outline"] {
            XCTAssertEqual(TransactionActivityState.bundledAssetID(for: logo), logo)
        }
    }

    func testOriginalSchemaOnePayloadDecodesWithoutAssetFields() throws {
        let original = Data(#"{"schemaVersion":1,"phase":"pending","observedAt":42,"revision":1,"updateDelayed":false,"summary":"1 ETH"}"#.utf8)
        let state = try JSONDecoder().decode(TransactionActivityState.self, from: original)
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(state.summary, "1 ETH")
        XCTAssertNil(state.sourceAssetID)
        XCTAssertNil(state.destinationAssetID)
        XCTAssertNil(state.sourceSummary)
        XCTAssertNil(state.destinationTicker)
        XCTAssertNil(state.sourceImageKey)
        XCTAssertNil(state.destinationImageKey)
        XCTAssertEqual(try JSONDecoder().decode(TransactionActivityState.self, from: JSONEncoder().encode(state)), state)
    }

    func testImageKeysValidateAtConstructionAndDecode() throws {
        let valid = String(repeating: "a1", count: 32)
        for key in [valid, String(repeating: "A", count: 64), String(repeating: "g", count: 64),
                    String(repeating: "a", count: 63), "../image", "https://example.com/image.png"] {
            let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                showDetails: true, sourceImageKey: key, destinationImageKey: key)
            XCTAssertEqual(state.sourceImageKey, key == valid ? valid : nil)
            XCTAssertEqual(state.destinationImageKey, key == valid ? valid : nil)
            var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
            payload["sourceImageKey"] = key
            payload["destinationImageKey"] = key
            let decoded = try JSONDecoder().decode(TransactionActivityState.self, from: JSONSerialization.data(withJSONObject: payload))
            XCTAssertEqual(decoded.sourceImageKey, key == valid ? valid : nil)
            XCTAssertEqual(decoded.destinationImageKey, key == valid ? valid : nil)
        }
    }

    func testPrivatePayloadOmitsCachedImageKeys() throws {
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
            sourceAssetID: "rune", destinationAssetID: "chain-rune",
            sourceImageKey: String(repeating: "a", count: 64), destinationImageKey: String(repeating: "b", count: 64))
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(state), encoding: .utf8))
        XCTAssertFalse(encoded.contains("ImageKey"))
        XCTAssertFalse(encoded.contains("AssetID"))
        XCTAssertFalse(state.hasDetails)
    }

    func testRouteLabelsRemainBoundedAndRoundTripWithoutParsingSummary() throws {
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
            summary: "legacy summary", showDetails: true, operation: .swap,
            sourceSummary: String(repeating: "界", count: 100), destinationTicker: String(repeating: "界", count: 100))
        XCTAssertLessThanOrEqual(try XCTUnwrap(state.sourceSummary).utf8.count, 160)
        XCTAssertLessThanOrEqual(try XCTUnwrap(state.destinationTicker).utf8.count, 80)
        XCTAssertEqual(try JSONDecoder().decode(TransactionActivityState.self, from: JSONEncoder().encode(state)), state)
    }

    func testDisplayStatusesRequireVerifiedSettlementAndKeepWirePhasesIntact() {
        let outcomes: [TransactionActivityState.DisplayStatus: [TransactionActivityState.Phase]] = [
            .inProgress: [.submitted, .pending, .sourceConfirmed, .swapping, .sourceConfirmedOnly, .trackingEnded],
            .success: [.confirmed, .completed, .filled],
            .failed: [.failed, .refunded, .partiallyRefunded, .cancelled, .expired]
        ]
        XCTAssertEqual(outcomes.values.flatMap { $0 }.count, TransactionActivityState.Phase.allCases.count)
        for (display, phases) in outcomes {
            for phase in phases { XCTAssertEqual(phase.displayStatus, display) }
        }
        XCTAssertTrue(TransactionActivityState.Phase.sourceConfirmedOnly.isTerminal)
        XCTAssertTrue(TransactionActivityState.Phase.trackingEnded.isTerminal)
        XCTAssertFalse(TransactionActivityState.Phase.swapping.isTerminal)
    }

    func testEveryPhaseHasLocalizedCopy() {
        for phase in TransactionActivityState.Phase.allCases {
            XCTAssertNotEqual(phase.displayStatus.localizationKey.localized, phase.displayStatus.localizationKey)
        }
    }

    func testOpaqueDeepLinkRoundTripsAndRejectsExtraContent() throws {
        let id = UUID()
        XCTAssertEqual(TransactionActivityLink.recordID(from: try XCTUnwrap(TransactionActivityLink.url(recordID: id))), id)
        XCTAssertNil(TransactionActivityLink.recordID(from: URL(string: "https://transaction/" + id.uuidString)!))
        XCTAssertNil(TransactionActivityLink.recordID(from: URL(string: "vultisig://transaction/" + id.uuidString + "?vault=secret")!))
    }
}
