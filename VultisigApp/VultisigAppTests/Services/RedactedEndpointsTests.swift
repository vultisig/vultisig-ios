//
//  RedactedEndpointsTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// A broadcast failure is shown on screen, and users screenshot that screen into
/// Discord and GitHub issues when asking for help. A custom RPC endpoint can
/// carry a hosted provider's API key in its path or query, so the message must
/// not — while still saying what actually went wrong, which is the part that
/// makes the failure actionable.
final class RedactedEndpointsTests: XCTestCase {

    // MARK: - What must be removed

    func testAPIKeysInThePathAreRemoved() {
        // QuickNode-style: the token is a path component.
        let message = "Failed to broadcast transaction,error:https://cold-frosty.quiknode.pro/9f3c1a7b2d/ refused"

        let redacted = message.redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("9f3c1a7b2d"))
        XCTAssertTrue(redacted.contains("cold-frosty.quiknode.pro"))
        XCTAssertTrue(redacted.contains("refused"), "the diagnostic must survive")
    }

    func testAPIKeysInTheQueryAreRemoved() {
        let message = "error: https://rpc.example.com/sui?apiKey=SUPERSECRET timed out"

        let redacted = message.redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("SUPERSECRET"))
        XCTAssertFalse(redacted.contains("apiKey"))
        XCTAssertTrue(redacted.contains("rpc.example.com"))
        XCTAssertTrue(redacted.contains("timed out"))
    }

    func testUserInfoCredentialsAreRemoved() {
        let message = "error: https://user:hunter2@rpc.example.com/rpc failed"

        let redacted = message.redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("user:"))
    }

    func testEveryURLInAMessageIsRedacted() {
        let message = "primary https://a.example/k/SECRET1 then https://b.example/k/SECRET2"

        let redacted = message.redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("SECRET1"))
        XCTAssertFalse(redacted.contains("SECRET2"))
        XCTAssertTrue(redacted.contains("a.example"))
        XCTAssertTrue(redacted.contains("b.example"))
    }

    func testThePortIsKeptSoTheEndpointStaysIdentifiable() {
        let redacted = "error: https://rpc.example.com:8443/k/SECRET".redactingEndpointCredentials()

        XCTAssertEqual(redacted, "error: https://rpc.example.com:8443/…")
    }

    // MARK: - What must be kept

    func testAMessageWithNoURLIsUntouched() {
        // The common case by far. Every chain's diagnostic must pass through
        // byte-identical, or this change would have degraded error reporting
        // for every chain in the app.
        let messages = [
            "Failed to broadcast transaction,error:insufficient gas",
            "Failed to broadcast transaction,error:Object version conflict",
            "Failed to broadcast transaction,error:This transaction has already been processed",
            "account sequence mismatch, expected 42, got 41",
            ""
        ]

        for message in messages {
            XCTAssertEqual(message.redactingEndpointCredentials(), message, message)
        }
    }

    func testABareOriginKeepsItsForm() {
        // Nothing credential-bearing to remove, so nothing is added either.
        let redacted = "error: https://graphql.mainnet.sui.io failed".redactingEndpointCredentials()

        XCTAssertEqual(redacted, "error: https://graphql.mainnet.sui.io failed")
    }

    func testSomethingThatIsNotAURLIsLeftAlone() {
        let message = "error: move_abort::0x2::coin::EInsufficientBalance at 1://2"

        XCTAssertEqual(message.redactingEndpointCredentials(), message)
    }

    // MARK: - Fails closed

    func testAQuoteInsideAKeyDoesNotLeaveTheTailBehind() {
        // A boundary that stops at quotes would match only through `ABC` and
        // leave `'DEF` sitting in the message.
        let message = "error: https://rpc.example/rpc?apiKey=ABC'DEF refused"

        let redacted = message.redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("ABC"))
        XCTAssertFalse(redacted.contains("DEF"))
        XCTAssertTrue(redacted.contains("refused"))
    }

    func testAnUnparseableURLShapedCandidateIsRemovedWholesale() {
        // The reason it did not parse is not knowable here, and guessing wrong
        // costs a leaked key — so it goes entirely rather than passing through.
        let message = "error: https://rpc.example:bad/SECRETKEY failed"

        let redacted = message.redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("SECRETKEY"))
        XCTAssertFalse(redacted.contains("rpc.example"))
        XCTAssertTrue(redacted.contains("failed"))
    }

    func testTheFallbackMarkerIsLocalized() {
        // It reaches `keysignError`, so the user reads it — and reads it in
        // their own language.
        let marker = "redactedEndpoint".localized

        XCTAssertNotEqual(
            marker,
            "redactedEndpoint",
            "`.localized` returns the key itself when the entry is missing from the table"
        )
        XCTAssertFalse(marker.isEmpty)

        let redacted = "error: https://rpc.example:bad/SECRET failed".redactingEndpointCredentials()

        XCTAssertEqual(redacted, "error: \(marker) failed")
    }

    func testSentencePunctuationSurvives() {
        let redacted = "tried (https://rpc.example/k/SECRET), then gave up."
            .redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("SECRET"))
        XCTAssertTrue(redacted.hasSuffix("then gave up."))
        XCTAssertTrue(redacted.contains("),"), "message punctuation must not be eaten")
    }

    func testAnIPv6LiteralKeepsItsBracketsAndDoesNotDoubleThem() {
        let redacted = "error: https://[2001:db8::1]:8443/k/SECRET".redactingEndpointCredentials()

        XCTAssertEqual(redacted, "error: https://[2001:db8::1]:8443/…")
    }

    func testABareIPv6URLAtTheEndOfASentenceIsNotTrimmedIntoNonsense() {
        // `]` is sentence punctuation as far as the trimmer knows, so trimming
        // first would leave `https://[::1` — unparseable, and redacted wholesale
        // for no reason. The whole candidate is retried before giving up.
        let redacted = "the node is https://[::1]".redactingEndpointCredentials()

        XCTAssertEqual(redacted, "the node is https://[::1]")
    }

    func testAURLAtEitherEndOfTheMessageIsRedacted() {
        for message in [
            "https://rpc.example/k/SECRET is down",
            "the node is https://rpc.example/k/SECRET",
            "https://rpc.example/k/SECRET"
        ] {
            let redacted = message.redactingEndpointCredentials()
            XCTAssertFalse(redacted.contains("SECRET"), message)
            XCTAssertTrue(redacted.contains("rpc.example"), message)
        }
    }

    func testPercentEncodedAndUnicodeInputDoNotMisbehave() {
        // Bridging NSRange to Range<String.Index> is UTF-16 based; these exist
        // to prove the offsets line up on non-ASCII input.
        let message = "错误: https://rpc.example/k/%2FSECRET%20x failed — 再试一次"

        let redacted = message.redactingEndpointCredentials()

        XCTAssertFalse(redacted.contains("SECRET"))
        XCTAssertTrue(redacted.contains("错误"))
        XCTAssertTrue(redacted.contains("再试一次"))
    }

    func testManyURLsAreAllRedactedAndTheTextBetweenThemSurvives() {
        // Also the shape that a naive in-place loop would corrupt: each
        // replacement changes the length of the string being indexed.
        let message = (1...25).map { "host\($0) https://h\($0).example/k/SECRET\($0) failed;" }
            .joined(separator: " ")

        let redacted = message.redactingEndpointCredentials()

        for index in 1...25 {
            XCTAssertFalse(redacted.contains("SECRET\(index)"), "leaked SECRET\(index)")
            XCTAssertTrue(redacted.contains("host\(index)"), "lost host\(index)")
            XCTAssertTrue(redacted.contains("h\(index).example"), "lost h\(index).example")
        }
    }

    // MARK: - The Sui path specifically

    func testTheLegacyEndpointErrorSurvivesRedactionIntact() {
        // Already redacted at source, so this must be a no-op rather than
        // double-mangling a message the user needs in order to fix a setting.
        let error = SuiRPCError.legacyEndpoint(URL(staticString: "https://node.example:8443/rpc/KEY?x=1"))
        let description = error.errorDescription ?? ""

        XCTAssertEqual(description.redactingEndpointCredentials(), description)
        XCTAssertFalse(description.contains("KEY"))
        XCTAssertTrue(description.contains("node.example"))
    }
}
