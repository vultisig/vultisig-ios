//
//  CeremonyWatchdogTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import godkls
import XCTest

@MainActor
final class CeremonyWatchdogTests: XCTestCase {

    private final class FakeClock {
        private(set) var instant = ContinuousClock.now

        func advance(_ duration: Duration) {
            instant = instant.advanced(by: duration)
        }
    }

    func testPeerWaitUnderTheLimitDoesNotExpire() throws {
        let fake = FakeClock()
        let watchdog = CeremonyWatchdog(now: { fake.instant })
        fake.advance(.seconds(59))
        XCTAssertNoThrow(try watchdog.checkExpired())
    }

    func testPeerWaitExpiresAfterTheLimit() {
        let fake = FakeClock()
        let watchdog = CeremonyWatchdog(now: { fake.instant })
        fake.advance(.seconds(61))
        XCTAssertThrowsError(try watchdog.checkExpired()) { error in
            XCTAssertEqual(error as? CeremonyTimeoutError, .peerUnresponsive)
        }
    }

    func testBeginningANewPeerWaitRestartsOnlyTheIdleWindow() throws {
        let fake = FakeClock()
        var watchdog = CeremonyWatchdog(now: { fake.instant })
        fake.advance(.seconds(50))
        watchdog.beginWaitingForPeer()
        fake.advance(.seconds(50))
        XCTAssertNoThrow(try watchdog.checkExpired())
        fake.advance(.seconds(11))
        XCTAssertThrowsError(try watchdog.checkExpired()) { error in
            XCTAssertEqual(error as? CeremonyTimeoutError, .peerUnresponsive)
        }
    }

    func testNewAttemptsNeverMoveTheHardDeadline() {
        let fake = FakeClock()
        var watchdog = CeremonyWatchdog(
            peerWaitLimit: .seconds(60),
            hardLimit: .seconds(240),
            now: { fake.instant }
        )

        for _ in 0..<4 {
            fake.advance(.seconds(59))
            watchdog.beginAttempt()
        }
        fake.advance(.seconds(5))

        XCTAssertThrowsError(try watchdog.checkExpired()) { error in
            XCTAssertEqual(error as? CeremonyTimeoutError, .overallDeadlineExceeded)
        }
    }

    func testPollBudgetUsesTheEarlierPeerDeadline() throws {
        let fake = FakeClock()
        let watchdog = CeremonyWatchdog(now: { fake.instant })
        fake.advance(.seconds(50))

        let budget = try watchdog.pollRequestBudget()

        XCTAssertEqual(budget.timeoutInterval, 10, accuracy: 0.001)
        XCTAssertEqual(budget.timeoutError, .peerUnresponsive)
    }

    func testPollBudgetUsesTheEarlierHardDeadline() throws {
        let fake = FakeClock()
        let watchdog = CeremonyWatchdog(
            peerWaitLimit: .seconds(60),
            hardLimit: .seconds(20),
            now: { fake.instant }
        )

        let budget = try watchdog.pollRequestBudget()

        XCTAssertEqual(budget.timeoutInterval, 20, accuracy: 0.001)
        XCTAssertEqual(budget.timeoutError, .overallDeadlineExceeded)
    }

    func testLocalRequestTimeoutIsClippedOnlyByTheHardDeadline() throws {
        let fake = FakeClock()
        var watchdog = CeremonyWatchdog(
            peerWaitLimit: .seconds(2),
            hardLimit: .seconds(20),
            now: { fake.instant }
        )
        fake.advance(.seconds(10))
        watchdog.beginWaitingForPeer()

        XCTAssertEqual(
            try watchdog.hardRequestTimeout(maximum: 60),
            10,
            accuracy: 0.001
        )
    }

    func testDefaultLimitsPreserveTheRetryEnvelope() {
        XCTAssertEqual(CeremonyWatchdog.defaultPeerWaitLimit, .seconds(60))
        XCTAssertEqual(CeremonyWatchdog.defaultHardLimit, .seconds(240))
        XCTAssertLessThan(
            RelaySendRetryPolicy.worstCaseBudget,
            CeremonyWatchdog.defaultPeerWaitLimit
        )
    }

    // MARK: - The poll loops consult the clock

    func testDKLSKeysignPollLoopThrowsWhenTheClockStalls() async {
        let vault = Vault(name: "DKLS", libType: .DKLS)
        vault.localPartyID = "partyA"
        let keysign = DKLSKeysign(
            keysignCommittee: ["partyA", "partyB"],
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            messsageToSign: ["deadbeef"],
            vault: vault,
            encryptionKeyHex: "00",
            chainPath: "m/44'/60'/0'/0/0",
            isInitiateDevice: false,
            publicKeyECDSA: "ECDSAKey",
            httpClient: EmptyPollingHTTPClient()
        )
        keysign.ceremonyWatchdog = CeremonyWatchdog(
            peerWaitLimit: .milliseconds(300),
            hardLimit: .seconds(1)
        )

        do {
            _ = try await keysign.pullInboundMessages(handle: godkls.Handle(), messageID: "msg")
            XCTFail("expected the stall timeout")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timeout"), "\(error)")
        }
    }

    func testDKLSKeygenPollLoopThrowsWhenTheClockStalls() async {
        let vault = Vault(name: "DKLS", libType: .DKLS)
        vault.localPartyID = "partyA"
        let keygen = DKLSKeygen(
            vault: vault,
            tssType: .Keygen,
            keygenCommittee: ["partyA", "partyB"],
            vaultOldCommittee: [],
            mediatorURL: "https://relay.invalid",
            sessionID: "session",
            encryptionKeyHex: "00",
            isInitiateDevice: true,
            localUI: nil,
            httpClient: EmptyPollingHTTPClient()
        )
        keygen.ceremonyWatchdog = CeremonyWatchdog(
            peerWaitLimit: .milliseconds(300),
            hardLimit: .seconds(1)
        )

        do {
            _ = try await keygen.pullInboundMessages(handle: godkls.Handle())
            XCTFail("expected the stall timeout")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timeout"), "\(error)")
        }
    }
}

/// Answers every poll with no messages so the loop idles until its clock trips.
private final class EmptyPollingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        let url = URL(string: "https://relay.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(), response: response)
    }
}
