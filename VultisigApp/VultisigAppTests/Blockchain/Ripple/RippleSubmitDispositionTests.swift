//
//  RippleSubmitDispositionTests.swift
//  VultisigAppTests
//
//  Pins the XRPL submit engine-result gate: only tesSUCCESS (or a defensive
//  missing engine result) counts as an accepted broadcast, the peer-race and
//  queued codes resolve by hash lookup, and every other engine result is the
//  ledger's authoritative rejection that must surface its real code instead
//  of being returned as a txid that may never land.
//
//  - https://xrpl.org/docs/references/protocol/transactions/transaction-results
//

@testable import VultisigApp
import XCTest

final class RippleSubmitDispositionTests: XCTestCase {

    private let txHash = "E08D6E9754025BA2534A78707605E0601F03ACE063687A0CA1BDDACFCD1698C7"

    // MARK: - Accepted

    func testTesSuccessWithHashIsAccepted() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tesSUCCESS",
            engineResultMessage: "The transaction was applied. Only final in a validated ledger.",
            hash: txHash
        )
        XCTAssertEqual(disposition, .accepted(hash: txHash))
    }

    func testMissingEngineResultWithHashIsAccepted() {
        // Defensive default shared with the SDK resolver: a malformed or
        // legacy response without an engine result must not brick broadcast.
        let disposition = RippleSubmitDisposition.classify(
            engineResult: nil,
            engineResultMessage: nil,
            hash: txHash
        )
        XCTAssertEqual(disposition, .accepted(hash: txHash))
    }

    // MARK: - Success responses without a trackable hash

    func testTesSuccessWithoutHashIsRejected() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tesSUCCESS",
            engineResultMessage: nil,
            hash: nil
        )
        XCTAssertEqual(disposition, .rejected(code: "tesSUCCESS", message: nil))
    }

    func testTesSuccessWithEmptyHashIsRejected() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tesSUCCESS",
            engineResultMessage: nil,
            hash: ""
        )
        XCTAssertEqual(disposition, .rejected(code: "tesSUCCESS", message: nil))
    }

    func testMissingEngineResultWithoutHashIsRejectedAsUnknown() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: nil,
            engineResultMessage: nil,
            hash: nil
        )
        XCTAssertEqual(disposition, .rejected(code: "unknown", message: nil))
    }

    // MARK: - Verify-by-hash codes

    func testTefAlreadyIsVerifyByHash() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tefALREADY",
            engineResultMessage: "The exact transaction was already in this ledger.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .verifyByHash(
                code: "tefALREADY",
                hash: txHash,
                message: "The exact transaction was already in this ledger."
            )
        )
    }

    func testTefPastSeqIsVerifyByHash() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tefPAST_SEQ",
            engineResultMessage: "This sequence number has already passed.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .verifyByHash(
                code: "tefPAST_SEQ",
                hash: txHash,
                message: "This sequence number has already passed."
            )
        )
    }

    func testTerQueuedIsVerifyByHash() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "terQUEUED",
            engineResultMessage: "Held until escalated fee drops.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .verifyByHash(
                code: "terQUEUED",
                hash: txHash,
                message: "Held until escalated fee drops."
            )
        )
    }

    func testVerifyByHashNormalizesEmptyEchoedHashToNil() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tefALREADY",
            engineResultMessage: nil,
            hash: ""
        )
        XCTAssertEqual(disposition, .verifyByHash(code: "tefALREADY", hash: nil, message: nil))
    }

    // MARK: - Authoritative rejections

    func testTemRedundantIsRejected() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "temREDUNDANT",
            engineResultMessage: "The transaction is redundant.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .rejected(code: "temREDUNDANT", message: "The transaction is redundant.")
        )
    }

    func testTecClaimFailureIsRejected() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tecUNFUNDED_PAYMENT",
            engineResultMessage: "Insufficient XRP balance to send.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .rejected(code: "tecUNFUNDED_PAYMENT", message: "Insufficient XRP balance to send.")
        )
    }

    func testTerPreSeqIsRejected() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "terPRE_SEQ",
            engineResultMessage: "Missing/inapplicable prior transaction.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .rejected(code: "terPRE_SEQ", message: "Missing/inapplicable prior transaction.")
        )
    }

    func testTelLocalErrorIsRejected() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "telINSUF_FEE_P",
            engineResultMessage: "Fee insufficient.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .rejected(code: "telINSUF_FEE_P", message: "Fee insufficient.")
        )
    }

    func testOtherTefIsRejected() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tefMAX_LEDGER",
            engineResultMessage: "Ledger sequence too high.",
            hash: txHash
        )
        XCTAssertEqual(
            disposition,
            .rejected(code: "tefMAX_LEDGER", message: "Ledger sequence too high.")
        )
    }

    func testRejectionCarriesEngineCodeAndMessage() {
        let disposition = RippleSubmitDisposition.classify(
            engineResult: "tecPATH_DRY",
            engineResultMessage: "Path could not send partial amount.",
            hash: nil
        )
        guard case let .rejected(code, message) = disposition else {
            return XCTFail("Expected .rejected, got \(disposition)")
        }
        XCTAssertEqual(code, "tecPATH_DRY")
        XCTAssertEqual(message, "Path could not send partial amount.")
    }
}

/// Pins the pure interpretation of the `tx` lookup that resolves a
/// `.verifyByHash` disposition: only a validated ledger is final, a known
/// but unvalidated transaction is in flight, and unusable responses carry
/// no evidence about the transaction.
final class RippleTxLookupOutcomeTests: XCTestCase {

    func testValidatedTesSuccessIsValidatedSuccess() throws {
        let response = try decodeTxResponse("""
        {"result": {"hash": "ABC", "validated": true, "ledger_index": 99,
                    "meta": {"TransactionResult": "tesSUCCESS", "TransactionIndex": 0},
                    "status": "success"}}
        """)
        XCTAssertEqual(RippleTxLookupOutcome.interpret(response), .validatedSuccess)
    }

    func testValidatedNonTesIsValidatedFailureWithCode() throws {
        let response = try decodeTxResponse("""
        {"result": {"hash": "ABC", "validated": true, "ledger_index": 99,
                    "meta": {"TransactionResult": "tecUNFUNDED_PAYMENT", "TransactionIndex": 0},
                    "status": "success"}}
        """)
        XCTAssertEqual(
            RippleTxLookupOutcome.interpret(response),
            .validatedFailure(code: "tecUNFUNDED_PAYMENT")
        )
    }

    func testValidatedWithoutMetaIsValidatedSuccess() throws {
        let response = try decodeTxResponse("""
        {"result": {"hash": "ABC", "validated": true, "status": "success"}}
        """)
        XCTAssertEqual(RippleTxLookupOutcome.interpret(response), .validatedSuccess)
    }

    func testKnownUnvalidatedIsPending() throws {
        let response = try decodeTxResponse("""
        {"result": {"hash": "ABC", "validated": false, "status": "success"}}
        """)
        XCTAssertEqual(RippleTxLookupOutcome.interpret(response), .pending)
    }

    func testResultLevelTxnNotFoundIsNotFound() throws {
        let response = try decodeTxResponse("""
        {"result": {"error": "txnNotFound", "error_code": 29,
                    "error_message": "Transaction not found.", "status": "error"}}
        """)
        XCTAssertEqual(RippleTxLookupOutcome.interpret(response), .notFound)
    }

    func testTopLevelTxnNotFoundIsNotFound() throws {
        let response = try decodeTxResponse("""
        {"error": "txnNotFound", "error_code": 29, "error_message": "Transaction not found.", "status": "error"}
        """)
        XCTAssertEqual(RippleTxLookupOutcome.interpret(response), .notFound)
    }

    func testOtherLookupErrorIsNotFound() throws {
        // A lookup failure that says nothing about the transaction (bad
        // params, unsupported method) must not masquerade as evidence.
        let response = try decodeTxResponse("""
        {"result": {"error": "notImpl", "error_code": 38,
                    "error_message": "Not implemented.", "status": "error"}}
        """)
        XCTAssertEqual(RippleTxLookupOutcome.interpret(response), .notFound)
    }

    func testMissingResultIsNotFound() throws {
        let response = try decodeTxResponse("{}")
        XCTAssertEqual(RippleTxLookupOutcome.interpret(response), .notFound)
    }

    private func decodeTxResponse(_ json: String) throws -> RippleTransactionStatusResponse {
        try JSONDecoder().decode(RippleTransactionStatusResponse.self, from: Data(json.utf8))
    }
}
