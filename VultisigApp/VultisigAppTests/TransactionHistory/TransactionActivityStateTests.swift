import XCTest
@testable import VultisigApp

final class TransactionActivityStateTests: XCTestCase {
    func testPrivatePayloadOmitsDetails() throws {
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                             summary: "secret amount", network: "secret network",
                                             operation: .swap, recipient: "secret recipient", fee: "secret fee",
                                             provider: "secret provider", submittedAt: Date())
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(state), encoding: .utf8))
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertNil(state.summary)
        XCTAssertNil(state.network)
    }

    func testCombinedPayloadStaysUnderFourKilobytesWithLongUnicode() throws {
        let state = TransactionActivityState(phase: .swapping, observedAt: Date(), revision: Int.max,
                                             summary: String(repeating: "🪙", count: 500),
                                             network: String(repeating: "界", count: 500), showDetails: true)
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
        XCTAssertEqual(state.staleDate, date.addingTimeInterval(90))
        XCTAssertNil(TransactionActivityState(phase: .confirmed, observedAt: date, revision: 2).staleDate)
    }

    func testRichPayloadCannotContainFullRecipient() {
        let address = "0x1234567890123456789012345678901234567890"
        let state = TransactionActivityState(phase: .pending, observedAt: Date(), revision: 1,
                                             showDetails: true, recipient: address)
        XCTAssertEqual(state.recipient, "0x12…7890")
        XCTAssertNotEqual(state.recipient, address)
    }

    func testEveryPhaseHasLocalizedCopy() {
        for phase in TransactionActivityState.Phase.allCases {
            XCTAssertNotEqual(phase.localizationKey.localized, phase.localizationKey)
        }
    }

    func testOpaqueDeepLinkRoundTripsAndRejectsExtraContent() {
        let id = UUID()
        XCTAssertEqual(TransactionActivityLink.recordID(from: TransactionActivityLink.url(recordID: id)), id)
        XCTAssertNil(TransactionActivityLink.recordID(from: URL(string: "https://transaction/" + id.uuidString)!))
        XCTAssertNil(TransactionActivityLink.recordID(from: URL(string: "vultisig://transaction/" + id.uuidString + "?vault=secret")!))
    }
}
