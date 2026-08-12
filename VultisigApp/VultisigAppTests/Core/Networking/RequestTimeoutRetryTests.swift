//
//  RequestTimeoutRetryTests.swift
//  VultisigAppTests
//
//  The Vultisig Solana RPC proxy intermittently accepts a request and then holds
//  it open for a shade over 60 seconds before answering `200` — a constant, not a
//  distribution, which is the signature of a fixed upstream timeout followed by a
//  retry. The `TargetType` default of 60 s sat exactly on that boundary, so the
//  app waited out the whole minute and then usually got its answer.
//
//  Two things follow, and both are pinned here: the timeout has to be well
//  inside that boundary, and a read that trips it has to be retried — once, and
//  only where repeating the request is free of consequence.
//

@testable import VultisigApp
import XCTest

final class RequestTimeoutRetryTests: XCTestCase {

    // MARK: - Timeouts

    /// Twenty seconds for a proxied read, not the 60 the protocol defaults to.
    /// Sixty is the number the stall itself is made of.
    func testAProxiedReadTimesOutWellInsideTheStall() {
        XCTAssertEqual(Self.proxied(.getRecentPrioritizationFees).timeoutInterval, 20)
        XCTAssertEqual(Self.proxied(.getAddressLookupTable(address: "t")).timeoutInterval, 20)
        XCTAssertEqual(
            Self.proxied(.simulateTransaction(
                encodedTransaction: "dHg=",
                replaceRecentBlockhash: true,
                accountAddresses: []
            )).timeoutInterval,
            20
        )
        XCTAssertEqual(KaminoAPI.vaultState(address: "v").timeoutInterval, 20)
        XCTAssertLessThan(SolanaAPI.proxyReadTimeout, SolanaAPI.defaultTimeout)
    }

    /// ⚠️ A broadcast keeps the long timeout. Aborting one does not undo it —
    /// a node that accepted the transaction is indistinguishable from one that
    /// never saw it, and the recovery path is a fresh ceremony over a fresh
    /// blockhash, which is different bytes and the one thing that could execute
    /// twice.
    func testABroadcastKeepsTheLongTimeout() {
        XCTAssertEqual(
            Self.proxied(.sendTransaction(encodedTransaction: "dHg=")).timeoutInterval,
            SolanaAPI.defaultTimeout
        )
    }

    /// The bulk reads keep it too: a slow validator set, stake-program walk or
    /// whole-wallet token scan is the work, not a stall, and cutting them short
    /// would abort a request that was going to succeed.
    func testTheBulkReadsKeepTheLongTimeout() {
        XCTAssertEqual(Self.proxied(.getVoteAccounts).timeoutInterval, SolanaAPI.defaultTimeout)
        XCTAssertEqual(
            Self.proxied(.getStakeAccountsByOwner(staker: "s", pubkeyOnly: false)).timeoutInterval,
            SolanaAPI.defaultTimeout
        )
        XCTAssertEqual(
            Self.proxied(.getTokenAccountsByOwner(walletAddress: "w", filter: .programId("p"))).timeoutInterval,
            SolanaAPI.defaultTimeout
        )
    }

    /// The rule is whether the response is bounded, not which method it is: the
    /// same token-account lookup filtered by MINT returns at most a couple of
    /// accounts, so it stays short.
    func testABoundedTokenAccountLookupStaysOnTheShortTimeout() {
        XCTAssertEqual(
            Self.proxied(.getTokenAccountsByOwner(walletAddress: "w", filter: .mint("m"))).timeoutInterval,
            SolanaAPI.proxyReadTimeout
        )
    }

    /// And a user's own node is not the proxy. The measurement that justifies
    /// the shorter timeout was taken on one specific host; a custom endpoint is
    /// left exactly as it was.
    func testACustomEndpointIsLeftOnTheDefaultTimeout() {
        let custom = SolanaAPI(
            baseURL: URL(staticString: "https://my-own-node.example"),
            usesProxyPath: false,
            rpcMethod: .getRecentPrioritizationFees
        )

        XCTAssertEqual(custom.timeoutInterval, SolanaAPI.defaultTimeout)
    }

    private static func proxied(_ method: SolanaAPI.Method) -> SolanaAPI {
        SolanaAPI(baseURL: SolanaAPI.rpcBaseURL, usesProxyPath: true, rpcMethod: method)
    }

    // MARK: - What may be retried

    /// The reads may. The two build endpoints may not — not because a duplicate
    /// build is dangerous (it signs nothing, and everything it returns is
    /// validated and simulated from scratch), but because a POST carries no
    /// idempotence guarantee this app is entitled to assume about somebody
    /// else's service, and because no stall was ever measured on that host.
    func testOnlyKaminoReadsAreMarkedRetryable() {
        XCTAssertTrue(KaminoAPI.vaultState(address: "v").isIdempotentRead)
        XCTAssertTrue(KaminoAPI.vaultMetrics(address: "v").isIdempotentRead)
        XCTAssertTrue(KaminoAPI.userPositions(owner: "o").isIdempotentRead)
        XCTAssertTrue(KaminoAPI.positionPnl(owner: "o", vault: "v").isIdempotentRead)

        let request = KaminoActionRequest(wallet: "o", kvault: "v", amount: "1")
        XCTAssertFalse(KaminoAPI.deposit(request: request).isIdempotentRead)
        XCTAssertFalse(KaminoAPI.withdraw(request: request).isIdempotentRead)
    }

    // MARK: - The retry itself

    /// Once. Every stall observed cleared on the first resend, and a second
    /// attempt would only stack another timeout onto a user who is already
    /// waiting.
    func testATimedOutReadIsRetriedOnceAndSucceeds() async throws {
        let http = ScriptedHTTPClient(script: [.timeout, .success(Self.feesJSON)])
        let service = SolanaService(resolver: NoOverrideResolver(), httpClient: http)

        let sample = try await service.fetchPrioritizationFeeSample()

        XCTAssertEqual(sample, 30_000)
        XCTAssertEqual(http.attempts, 2)
    }

    func testASecondTimeoutIsNotRetriedAgain() async {
        let http = ScriptedHTTPClient(script: [.timeout, .timeout, .success(Self.feesJSON)])
        let service = SolanaService(resolver: NoOverrideResolver(), httpClient: http)

        do {
            _ = try await service.fetchPrioritizationFeeSample()
            XCTFail("a second timeout must propagate")
        } catch let error as HTTPError {
            guard case .timeout = error else {
                return XCTFail("unexpected error \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }

        XCTAssertEqual(http.attempts, 2)
    }

    /// Only a timeout. A status code does not get better by being repeated, and
    /// repeating it would double the load on a service that is already failing.
    func testANonTimeoutFailureIsNotRetried() async {
        let http = ScriptedHTTPClient(script: [.status(500), .success(Self.feesJSON)])
        let service = SolanaService(resolver: NoOverrideResolver(), httpClient: http)

        do {
            _ = try await service.fetchPrioritizationFeeSample()
            XCTFail("a 500 must propagate")
        } catch {
            // expected
        }

        XCTAssertEqual(http.attempts, 1)
    }

    /// ⚠️ A broadcast is the one call here that is not a read. It already owns a
    /// bespoke resend loop that knows which failures are worth repeating, and a
    /// blind retry underneath it would resend a signed transaction on a timeout
    /// — exactly the case where the first attempt may well have landed.
    func testABroadcastIsNeverRetriedOnTimeout() async {
        let http = ScriptedHTTPClient(script: [.timeout, .success(#"{"jsonrpc":"2.0","id":1,"result":"sig"}"#)])
        let service = SolanaService(resolver: NoOverrideResolver(), httpClient: http)

        do {
            _ = try await service.sendSolanaTransaction(encodedTransaction: "dHg=")
            XCTFail("the timeout must propagate rather than resending signed bytes")
        } catch {
            // expected
        }

        XCTAssertEqual(http.attempts, 1)
    }

    private static let feesJSON = """
    {"jsonrpc":"2.0","id":1,"result":[{"slot":1,"prioritizationFee":30000}]}
    """
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

/// Answers each attempt from a script, so "retried once" and "not retried
/// twice" are the same assertion read from opposite ends.
private final class ScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    enum Step {
        case timeout
        case status(Int)
        case success(String)
    }

    private let lock = NSLock()
    private var script: [Step]
    private var _attempts = 0

    var attempts: Int { lock.withLock { _attempts } }

    init(script: [Step]) {
        self.script = script
    }

    // Protocol requires `async`; the body is synchronous.
    // swiftlint:disable:next async_without_await unused_parameter
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        let step: Step = lock.withLock {
            let index = min(_attempts, script.count - 1)
            _attempts += 1
            return script[index]
        }

        switch step {
        case .timeout:
            throw HTTPError.timeout
        case .status(let code):
            throw HTTPError.statusCode(code, nil)
        case .success(let json):
            guard let url = URL(string: "https://test.local"),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw HTTPError.invalidResponse
            }
            return HTTPResponse(data: Data(json.utf8), response: response)
        }
    }
}
