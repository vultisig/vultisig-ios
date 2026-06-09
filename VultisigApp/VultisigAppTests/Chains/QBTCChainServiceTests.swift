//
//  QBTCChainServiceTests.swift
//  VultisigAppTests
//
//  Pure-helper tests for QBTCChainService (no network).
//  Mirrors vultisig-sdk/.../getClaimWithProofDisabled.ts.
//
//  Post-qbtc#158 the iOS-side cosmos auth/account/broadcast paths are
//  gone (the proof service signs + broadcasts directly), so this file
//  only covers what remains: the kill-switch param parse + the
//  `QBTCParamResponse` DTO shape.
//

@testable import VultisigApp
import XCTest

final class QBTCChainServiceTests: XCTestCase {
    // MARK: - parseDisabledFlag

    func testDisabledFlagZeroIsEnabled() throws {
        XCTAssertFalse(try QBTCChainService.parseDisabledFlag("0"))
    }

    func testDisabledFlagOneIsDisabled() throws {
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("1"))
    }

    func testDisabledFlagAnyPositiveIsDisabled() throws {
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("5"))
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("9999"))
    }

    func testDisabledFlagRejectsNonNumeric() {
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag("yes"))
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag(""))
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag("1.5"))
    }

    // MARK: - parseConfirmationBlocks

    func testParseConfirmationBlocksReadsLiveValue() throws {
        // Live chain param at time of writing.
        XCTAssertEqual(try QBTCChainService.parseConfirmationBlocks("144"), 144)
    }

    func testParseConfirmationBlocksAcceptsZero() throws {
        XCTAssertEqual(try QBTCChainService.parseConfirmationBlocks("0"), 0)
    }

    func testParseConfirmationBlocksRejectsNonNumeric() {
        XCTAssertThrowsError(try QBTCChainService.parseConfirmationBlocks("abc"))
        XCTAssertThrowsError(try QBTCChainService.parseConfirmationBlocks(""))
        XCTAssertThrowsError(try QBTCChainService.parseConfirmationBlocks("1.5"))
        XCTAssertThrowsError(try QBTCChainService.parseConfirmationBlocks("-1"))
    }

    // MARK: - confirmations

    func testConfirmationsCountsMiningBlockAsFirst() {
        // Mined exactly at the tip ⇒ 1 confirmation.
        XCTAssertEqual(QBTCChainService.confirmations(blockHeight: 100, tipHeight: 100), 1)
        // 144 blocks deep: tip 952877, mined at 952734 ⇒ 144 confs.
        XCTAssertEqual(QBTCChainService.confirmations(blockHeight: 952_734, tipHeight: 952_877), 144)
    }

    func testConfirmationsTreatsNilHeightAsZero() {
        XCTAssertEqual(QBTCChainService.confirmations(blockHeight: nil, tipHeight: 952_877), 0)
    }

    func testConfirmationsClampsWhenTipLagsHeight() {
        // Stale tip / reorg: height ahead of tip must not underflow.
        XCTAssertEqual(QBTCChainService.confirmations(blockHeight: 200, tipHeight: 100), 0)
    }

    // MARK: - filterSufficientlyConfirmed

    private static let confTxid1 = String(repeating: "a", count: 64)
    private static let confTxid2 = String(repeating: "b", count: 64)
    private static let confTxid3 = String(repeating: "c", count: 64)

    func testFilterSufficientlyConfirmedKeepsConfirmedHidesUnderConfirmed() {
        let service = QBTCChainService(httpClient: NoopHTTPClient())
        let tip: UInt32 = 1_000_000
        let utxos = [
            // 144 confs exactly — kept (boundary).
            ClaimableUtxo(txid: Self.confTxid1, vout: 0, amount: 1, blockHeight: tip - 143),
            // 143 confs — hidden (one short).
            ClaimableUtxo(txid: Self.confTxid2, vout: 1, amount: 2, blockHeight: tip - 142),
            // nil height (mempool) — always hidden.
            ClaimableUtxo(txid: Self.confTxid3, vout: 2, amount: 3, blockHeight: nil)
        ]

        let kept = service.filterSufficientlyConfirmed(utxos, btcTipHeight: tip, minConfirmations: 144)

        XCTAssertEqual(kept.map(\.txid), [Self.confTxid1])
    }

    func testFilterSufficientlyConfirmedFailsOpenWhenTipUnknown() {
        // Tip unavailable ⇒ can't prove anything under-confirmed ⇒ keep all,
        // including the nil-height entry. Mirrors filterClaimable fail-open.
        let service = QBTCChainService(httpClient: NoopHTTPClient())
        let utxos = [
            ClaimableUtxo(txid: Self.confTxid1, vout: 0, amount: 1, blockHeight: 10),
            ClaimableUtxo(txid: Self.confTxid2, vout: 1, amount: 2, blockHeight: nil)
        ]

        let kept = service.filterSufficientlyConfirmed(utxos, btcTipHeight: nil, minConfirmations: 144)

        XCTAssertEqual(kept.count, 2)
    }

    // MARK: - DTO decoding

    func testParamResponseDecodes() throws {
        let json = #"{"param":{"key":"ClaimWithProofDisabled","value":"0"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QBTCParamResponse.self, from: json)
        XCTAssertEqual(decoded.param.key, "ClaimWithProofDisabled")
        XCTAssertEqual(decoded.param.value, "0")
    }

    func testMinUtxoConfirmationBlocksParamResponseDecodes() throws {
        // Real shape returned by /qbtc/v1/params/MinUtxoConfirmationBlocks.
        let json = #"{"param":{"key":"MinUtxoConfirmationBlocks","value":"144"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QBTCParamResponse.self, from: json)
        XCTAssertEqual(decoded.param.key, "MinUtxoConfirmationBlocks")
        XCTAssertEqual(decoded.param.value, "144")
    }

    // MARK: - minUtxoConfirmationBlocks (reads the param off the wire)

    func testMinUtxoConfirmationBlocksReadsThresholdFromParam() async throws {
        let mock = StubParamHTTPClient(
            path: "/qbtc/v1/params/MinUtxoConfirmationBlocks",
            body: #"{"param":{"key":"MinUtxoConfirmationBlocks","value":"144"}}"#
        )
        let service = QBTCChainService(httpClient: mock)

        let threshold = try await service.minUtxoConfirmationBlocks()

        XCTAssertEqual(threshold, 144)
    }

    func testMinUtxoConfirmationBlocksThrowsOnNonNumericParam() async {
        let mock = StubParamHTTPClient(
            path: "/qbtc/v1/params/MinUtxoConfirmationBlocks",
            body: #"{"param":{"key":"MinUtxoConfirmationBlocks","value":"oops"}}"#
        )
        let service = QBTCChainService(httpClient: mock)

        do {
            _ = try await service.minUtxoConfirmationBlocks()
            XCTFail("expected parse to throw on non-numeric param value")
        } catch let error as QBTCChainServiceError {
            // Pin the contract: callers (confirmationGated) only fail-open on
            // *this* error, so a generic throw assertion would mask a regression
            // that surfaced an unrelated failure here.
            guard case .invalidParamValue(let raw) = error else {
                return XCTFail("expected .invalidParamValue, got \(error)")
            }
            XCTAssertEqual(raw, "oops")
        } catch {
            XCTFail("expected QBTCChainServiceError.invalidParamValue, got \(error)")
        }
    }
}

// MARK: - Test doubles

/// Pure-logic stub: `filterSufficientlyConfirmed` never touches the network,
/// so any request is a programming error.
private final class NoopHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    // swiftlint:disable:next async_without_await unused_parameter
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        throw NoopError.unexpected
    }

    enum NoopError: Error { case unexpected }
}

/// Returns a fixed 200 body for one expected param path.
private final class StubParamHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let path: String
    private let body: String

    init(path: String, body: String) {
        self.path = path
        self.body = body
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard target.path == path else {
            throw StubError.unexpectedRoute(target.path)
        }
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://example.test\(path)")!
        // swiftlint:disable:next force_unwrapping
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    enum StubError: Error { case unexpectedRoute(String) }
}
