@testable import VultisigApp
import Mediator
import XCTest

final class TssRelayAPITests: XCTestCase {

    private let base = URL(string: "https://relay.example.com")!

    private func api(_ endpoint: TssRelayAPI.Endpoint) -> TssRelayAPI {
        TssRelayAPI(baseURL: base, endpoint: endpoint)
    }

    private func makeMessage() -> Message {
        Message(session_id: "s", from: "a", to: ["b"], body: "body", hash: "hash", sequenceNo: 0)
    }

    // MARK: - uploadSetupMessage

    func testUploadSetupMessage_additionalHeaderSet_usesAdditionalHeader() {
        let sut = api(.uploadSetupMessage(sessionID: "s", body: Data(), messageID: "ignored", additionalHeader: "extra"))
        XCTAssertEqual(sut.headers?["message_id"], "extra")
    }

    func testUploadSetupMessage_onlyMessageIDSet_noMessageIDHeader() {
        // messageID is intentionally ignored for uploadSetupMessage; only additionalHeader counts.
        let sut = api(.uploadSetupMessage(sessionID: "s", body: Data(), messageID: "msg-123", additionalHeader: nil))
        XCTAssertNil(sut.headers?["message_id"])
    }

    func testUploadSetupMessage_bothNil_noMessageIDHeader() {
        let sut = api(.uploadSetupMessage(sessionID: "s", body: Data(), messageID: nil, additionalHeader: nil))
        XCTAssertNil(sut.headers?["message_id"])
    }

    func testUploadSetupMessage_bothSet_additionalHeaderWins() {
        let sut = api(.uploadSetupMessage(sessionID: "s", body: Data(), messageID: "msg-123", additionalHeader: "extra"))
        XCTAssertEqual(sut.headers?["message_id"], "extra")
    }

    // MARK: - downloadSetupMessage

    func testDownloadSetupMessage_additionalHeaderSet_usesAdditionalHeader() {
        let sut = api(.downloadSetupMessage(sessionID: "s", messageID: "ignored", additionalHeader: "extra"))
        XCTAssertEqual(sut.headers?["message_id"], "extra")
    }

    func testDownloadSetupMessage_onlyMessageIDSet_noMessageIDHeader() {
        // messageID is intentionally ignored for downloadSetupMessage; only additionalHeader counts.
        let sut = api(.downloadSetupMessage(sessionID: "s", messageID: "msg-123", additionalHeader: nil))
        XCTAssertNil(sut.headers?["message_id"])
    }

    func testDownloadSetupMessage_bothNil_noMessageIDHeader() {
        let sut = api(.downloadSetupMessage(sessionID: "s", messageID: nil, additionalHeader: nil))
        XCTAssertNil(sut.headers?["message_id"])
    }

    func testDownloadSetupMessage_bothSet_additionalHeaderWins() {
        let sut = api(.downloadSetupMessage(sessionID: "s", messageID: "msg-123", additionalHeader: "extra"))
        XCTAssertEqual(sut.headers?["message_id"], "extra")
    }

    // MARK: - sendMessage (regression guard — uses messageID directly, unchanged)

    func testSendMessage_messageIDSet_usesMessageID() {
        let sut = api(.sendMessage(sessionID: "s", message: makeMessage(), messageID: "msg-123", addLegacyKeygenHeader: false))
        XCTAssertEqual(sut.headers?["message_id"], "msg-123")
    }

    func testSendMessage_messageIDNil_noMessageIDHeader() {
        let sut = api(.sendMessage(sessionID: "s", message: makeMessage(), messageID: nil, addLegacyKeygenHeader: false))
        XCTAssertNil(sut.headers?["message_id"])
    }

    func testSendMessage_legacyKeygenHeaderTrue_setsKeygenHeader() {
        let sut = api(.sendMessage(sessionID: "s", message: makeMessage(), messageID: nil, addLegacyKeygenHeader: true))
        XCTAssertEqual(sut.headers?["keygen"], "vultisig")
    }

    func testSendMessage_legacyKeygenHeaderFalse_noKeygenHeader() {
        let sut = api(.sendMessage(sessionID: "s", message: makeMessage(), messageID: nil, addLegacyKeygenHeader: false))
        XCTAssertNil(sut.headers?["keygen"])
    }

    // MARK: - pollInboundMessages (regression guard)

    func testPollInboundMessages_messageIDSet_usesMessageID() {
        let sut = api(.pollInboundMessages(sessionID: "s", localPartyID: "p", messageID: "msg-xyz"))
        XCTAssertEqual(sut.headers?["message_id"], "msg-xyz")
    }

    func testPollInboundMessages_messageIDNil_noMessageIDHeader() {
        let sut = api(.pollInboundMessages(sessionID: "s", localPartyID: "p", messageID: nil))
        XCTAssertNil(sut.headers?["message_id"])
    }

    // MARK: - checkKeygenStarted

    func testCheckKeygenStarted_noSpecialHeaders() {
        let sut = api(.checkKeygenStarted(sessionID: "s"))
        XCTAssertNil(sut.headers?["message_id"])
        XCTAssertNil(sut.headers?["keygen"])
    }

    // MARK: - Content-Type always present

    func testHeaders_allEndpoints_containContentTypeJSON() {
        let endpoints: [TssRelayAPI.Endpoint] = [
            .uploadSetupMessage(sessionID: "s", body: Data(), messageID: nil, additionalHeader: nil),
            .downloadSetupMessage(sessionID: "s", messageID: nil, additionalHeader: nil),
            .sendMessage(sessionID: "s", message: makeMessage(), messageID: nil, addLegacyKeygenHeader: false),
            .pollInboundMessages(sessionID: "s", localPartyID: "p", messageID: nil),
            .deleteMessage(sessionID: "s", localPartyID: "p", hash: "h", messageID: nil),
            .checkKeygenStarted(sessionID: "s")
        ]
        for endpoint in endpoints {
            XCTAssertEqual(api(endpoint).headers?["Content-Type"], "application/json", "Missing Content-Type for \(endpoint)")
        }
    }
}
