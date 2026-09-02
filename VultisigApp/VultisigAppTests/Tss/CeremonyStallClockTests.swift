//
//  CeremonyStallClockTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import godkls
import XCTest

@MainActor
final class CeremonyStallClockTests: XCTestCase {

    private final class FakeClock {
        private(set) var instant = ContinuousClock.now

        func advance(_ duration: Duration) {
            instant = instant.advanced(by: duration)
        }
    }

    func testIdleUnderTheLimitIsNotStalled() {
        let fake = FakeClock()
        let clock = CeremonyStallClock { fake.instant }
        fake.advance(.seconds(59))
        XCTAssertFalse(clock.isStalled)
    }

    func testIdleOverTheLimitIsStalled() {
        let fake = FakeClock()
        let clock = CeremonyStallClock { fake.instant }
        fake.advance(.seconds(61))
        XCTAssertTrue(clock.isStalled)
    }

    func testProgressRestartsTheWait() {
        let fake = FakeClock()
        var clock = CeremonyStallClock { fake.instant }
        fake.advance(.seconds(50))
        clock.markProgress()
        fake.advance(.seconds(50))
        XCTAssertFalse(clock.isStalled)
        fake.advance(.seconds(11))
        XCTAssertTrue(clock.isStalled)
    }

    func testResetClearsTheElapsedTime() {
        let fake = FakeClock()
        var clock = CeremonyStallClock { fake.instant }
        fake.advance(.seconds(61))
        XCTAssertTrue(clock.isStalled)
        clock.reset()
        XCTAssertFalse(clock.isStalled)
    }

    func testDefaultLimitIsSixtySeconds() {
        XCTAssertEqual(CeremonyStallClock.defaultLimit, .seconds(60))
        XCTAssertEqual(CeremonyStallClock().limit, CeremonyStallClock.defaultLimit)
    }

    func testSendRetryBudgetFitsInsideTheStallLimit() {
        XCTAssertLessThan(RelaySendRetryPolicy.worstCaseBudget, CeremonyStallClock.defaultLimit)
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
        keysign.stallClock = CeremonyStallClock(limit: .milliseconds(300))

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
        keygen.stallClock = CeremonyStallClock(limit: .milliseconds(300))

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
