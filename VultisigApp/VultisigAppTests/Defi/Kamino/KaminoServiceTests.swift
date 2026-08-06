//
//  KaminoServiceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

/// Decoding and request-shaping for the Kamino REST client, against response
/// bodies captured verbatim from `api.kamino.finance`.
///
/// The load-bearing assertion is `test_deposit_sendsTokenUnits_withdraw_sendsShareUnits`:
/// the two endpoints take the same `amount` field with inverted units, and the
/// whole typed-amount design exists to make that impossible to get wrong.
final class KaminoServiceTests: XCTestCase {

    private var http: StubKaminoHTTPClient!
    private var service: KaminoService!

    override func setUp() {
        super.setUp()
        http = StubKaminoHTTPClient()
        service = KaminoService(httpClient: http)
    }

    override func tearDown() {
        http = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Reads

    func test_fetchVaultState_decodesLiveBody() async throws {
        http.queueJSON(Fixtures.steakhouseState, for: .state)

        let response = try await service.fetchVaultState(address: Fixtures.steakhouseAddress)

        XCTAssertEqual(response.address, Fixtures.steakhouseAddress)
        XCTAssertEqual(response.state.name, "Steakhouse USDC")
        XCTAssertEqual(response.state.tokenMintDecimals, 6)
        XCTAssertEqual(response.state.sharesMintDecimals, 6)
        XCTAssertEqual(response.state.minDepositAmount, "100000")
        XCTAssertEqual(response.state.minWithdrawAmount, "1000")
        XCTAssertEqual(response.state.performanceFeeBps, 500)
    }

    /// `minWithdrawAmount` is a TOKEN figure, and the chain refuses a withdraw
    /// worth less than twice it — measured on both vaults at one base unit of
    /// resolution: Steakhouse refuses 1898 share base units and accepts 1899,
    /// Allez refuses 1861 and accepts 1862.
    ///
    /// Reading it as a share count, which is what the field's name suggests,
    /// produced 1000 — below both floors — so the withdraw form advertised a
    /// minimum the chain rejects. This pins the derivation and the margin: the
    /// result must clear the measured floor, and it must not run away from it
    /// either, since it is the smallest amount a user can take out.
    func test_fetchVaultInfo_derivesTheWithdrawMinimumFromTheTokenFigure() async throws {
        http.queueJSON(Fixtures.allezState, for: .state)
        http.queueJSON(Fixtures.allezMetrics, for: .metrics)
        let allez = try await service.fetchVaultInfo(descriptor: KaminoVaultRegistry.allezSOL)

        XCTAssertEqual(allez.minWithdraw.baseUnits, 2_791)
        XCTAssertGreaterThan(allez.minWithdraw.baseUnits, 1_862, "below the measured Allez floor")
        XCTAssertLessThan(allez.minWithdraw.baseUnits, 1_862 * 2, "more margin than the measurement justifies")

        // The published figure read the old way, for contrast: the same "1000"
        // as a share count is little more than half of what executes.
        XCTAssertLessThan(
            BigInt(1_000), allez.minWithdraw.baseUnits,
            "the derivation must not reproduce the published figure as a share count"
        )

        http.queueJSON(Fixtures.steakhouseState, for: .state)
        http.queueJSON(Fixtures.steakhouseMetrics, for: .metrics)
        let steakhouse = try await service.fetchVaultInfo(descriptor: KaminoVaultRegistry.steakhouseUSDC)

        XCTAssertEqual(steakhouse.minWithdraw.baseUnits, 2_847)
        XCTAssertGreaterThan(steakhouse.minWithdraw.baseUnits, 1_899, "below the measured Steakhouse floor")
        XCTAssertLessThan(steakhouse.minWithdraw.baseUnits, 1_899 * 2, "more margin than the measurement justifies")
    }

    /// The rounding direction is a correctness property, not a preference: a
    /// share count worth fractionally less than the minimum is exactly the
    /// failure this whole derivation exists to prevent.
    func test_effectiveWithdrawMinimum_roundsUpRatherThanTruncating() throws {
        // 3 × 1000 token base units at a rate that does not divide evenly.
        let required = KaminoTokenAmount(baseUnits: BigInt(3_000), decimals: 9)
        let rate = try XCTUnwrap(KaminoRate(apiString: "0.0010749299151180878396"))

        let roundedUp = try XCTUnwrap(required.shareAmountRoundedUp(tokensPerShare: rate, shareDecimals: 6))
        let truncated = try XCTUnwrap(required.shareAmount(tokensPerShare: rate, shareDecimals: 6))

        XCTAssertEqual(roundedUp.baseUnits, 2_791)
        XCTAssertEqual(truncated.baseUnits, 2_790, "the exact quotient falls between the two")
        XCTAssertGreaterThan(
            try XCTUnwrap(roundedUp.tokenValue(tokensPerShare: rate, tokenDecimals: 9)).baseUnits,
            BigInt(3_000) - 1,
            "rounded up, the share count is still worth the minimum it was derived from"
        )
    }

    func test_fetchVaultInfo_mergesRegistryWithLiveStateAndMetrics() async throws {
        http.queueJSON(Fixtures.allezState, for: .state)
        http.queueJSON(Fixtures.allezMetrics, for: .metrics)

        let info = try await service.fetchVaultInfo(descriptor: KaminoVaultRegistry.allezSOL)

        XCTAssertEqual(info.name, "Allez SOL")
        XCTAssertEqual(info.descriptor.curator, "Allez Labs")
        // The (token 9, share 6) vault — the case that breaks any code assuming
        // the two decimal scales match.
        XCTAssertEqual(info.tokenDecimals, 9)
        XCTAssertEqual(info.shareDecimals, 6)
        XCTAssertEqual(info.minDeposit.apiString, "0.01")
        // NOT the published "1000" read as shares. That figure is a TOKEN amount
        // and the program's floor is above it — see
        // `test_fetchVaultInfo_derivesTheWithdrawMinimumFromTheTokenFigure`.
        XCTAssertEqual(info.minWithdraw.apiString, "0.002791")
        XCTAssertTrue(info.hasFarm, "all three launch vaults auto-stake shares into a farm")
        XCTAssertEqual(info.apy30d, KaminoDecimal.parse("0.066908831669281033201"))
        XCTAssertEqual(info.tokensPerShare, KaminoRate(apiString: "0.0010749299151180878396"))
        // The liquid buffer a withdraw settles out of, at the token's own scale.
        XCTAssertEqual(info.tokensAvailable?.apiString, "34.19551574")
        XCTAssertEqual(info.tokensAvailable?.decimals, 9)
    }

    func test_fetchPositions_decodesSharesOnly() async throws {
        http.queueJSON(Fixtures.positions, for: .positions)

        let positions = try await service.fetchPositions(owner: Fixtures.owner)

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions.first?.vaultAddress, Fixtures.steakhouseAddress)
        XCTAssertEqual(positions.first?.totalShares, "517536.857982")
    }

    func test_fetchPnl_decodesNegativeAndPositiveLegs() async throws {
        http.queueJSON(Fixtures.pnl, for: .pnl)

        let pnl = try await service.fetchPnl(owner: Fixtures.owner, vault: Fixtures.steakhouseAddress)

        XCTAssertEqual(pnl.totalCostBasis.usd, "528083.63695495184445")
        XCTAssertEqual(pnl.totalPnl.token, "17064.57109480498919")
    }

    // MARK: - Actions

    func test_deposit_sendsTokenUnits_withdraw_sendsShareUnits() async throws {
        http.queueJSON(Fixtures.actionResponse, for: .deposit)
        _ = try await service.buildDepositTransaction(
            owner: Fixtures.owner,
            vault: Fixtures.steakhouseAddress,
            amount: KaminoTokenAmount(baseUnits: 10_000_000, decimals: 6)
        )
        XCTAssertEqual(http.lastRequestBody()?.amount, "10", "deposit amount is in token units")

        http.queueJSON(Fixtures.actionResponse, for: .withdraw)
        _ = try await service.buildWithdrawTransaction(
            owner: Fixtures.owner,
            vault: Fixtures.steakhouseAddress,
            shares: KaminoShareAmount(baseUnits: 5_500_000, decimals: 6)
        )
        XCTAssertEqual(http.lastRequestBody()?.amount, "5.5", "withdraw amount is in SHARE units")
    }

    func test_deposit_returnsRawBase64Transaction() async throws {
        http.queueJSON(Fixtures.actionResponse, for: .deposit)

        let transaction = try await service.buildDepositTransaction(
            owner: Fixtures.owner,
            vault: Fixtures.steakhouseAddress,
            amount: KaminoTokenAmount(baseUnits: 10_000_000, decimals: 6)
        )

        XCTAssertEqual(transaction, "AQAAdGVzdA==")
    }

    // MARK: - Errors

    func test_structuredApiError_surfacesMachineReadableCode() async {
        http.queueError(.statusCode(400, Data(Fixtures.vaultNotFound.utf8)), for: .state)

        do {
            _ = try await service.fetchVaultState(address: "not-a-vault")
            XCTFail("Expected a Kamino API error")
        } catch let error as KaminoServiceError {
            XCTAssertEqual(
                error,
                .api(status: 400, code: "KVAULT_NOT_FOUND", message: "Kamino Earn Vault does not exist")
            )
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_serverErrorWithTheSameBodyShapeStaysRetryable() async {
        // Kamino's error envelope carries its own `statusCode`, so a 503 can
        // arrive in the identical shape as a permanent 400. Losing the HTTP
        // status would make a transient outage indistinguishable from a bad
        // request and suppress any retry.
        http.queueError(.statusCode(503, Data(Fixtures.serviceUnavailable.utf8)), for: .state)

        do {
            _ = try await service.fetchVaultState(address: Fixtures.steakhouseAddress)
            XCTFail("Expected a Kamino API error")
        } catch let error as KaminoServiceError {
            guard case .api(let status, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 503)
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Amount gating

    func test_outOfRangeAmountsNeverReachTheNetwork() async {
        // The API validates nothing, so the client is the only gate. A zero or
        // above-u64 amount must fail before a request is issued.
        await assertInvalidAmount {
            try await self.service.buildDepositTransaction(
                owner: Fixtures.owner,
                vault: Fixtures.steakhouseAddress,
                amount: KaminoTokenAmount(baseUnits: 0, decimals: 6)
            )
        }
        await assertInvalidAmount {
            try await self.service.buildWithdrawTransaction(
                owner: Fixtures.owner,
                vault: Fixtures.steakhouseAddress,
                shares: KaminoShareAmount(baseUnits: BigInt(UInt64.max) + 1, decimals: 6)
            )
        }
        await assertInvalidAmount {
            try await self.service.buildWithdrawTransaction(
                owner: Fixtures.owner,
                vault: Fixtures.steakhouseAddress,
                shares: KaminoShareAmount(baseUnits: -1, decimals: 6)
            )
        }
        XCTAssertNil(http.lastRequestBody(), "no request should have been issued")
    }

    /// `u64::MAX` is the API's own "withdraw everything" sentinel — the value an
    /// over-sized request is silently rewritten to. It is inside the `u64` range
    /// every other amount is bounded by, so it needs its own refusal: no real
    /// share balance is 18.4 quintillion base units, and refusing the value
    /// means a full exit can never be produced by arithmetic.
    func test_theWithdrawEverythingSentinelIsRefusedOutright() async {
        await assertInvalidAmount {
            try await self.service.buildWithdrawTransaction(
                owner: Fixtures.owner,
                vault: Fixtures.steakhouseAddress,
                shares: KaminoShareAmount(baseUnits: BigInt(UInt64.max), decimals: 6)
            )
        }
        XCTAssertNil(http.lastRequestBody(), "no request should have been issued")
    }

    /// A decimal scale is not something the API gets to change: it is a property
    /// of the mint, it scales every amount, and a wrong one mis-sizes the actual
    /// transfer by a power of ten while every other check still passes.
    func test_decimalScaleDisagreeingWithTheRegistryIsRejected() async {
        http.queueJSON(Fixtures.stateWithAbsurdDecimals, for: .state)
        http.queueJSON(Fixtures.allezMetrics, for: .metrics)

        do {
            _ = try await service.fetchVaultInfo(descriptor: KaminoVaultRegistry.allezSOL)
            XCTFail("Expected a vault-metadata mismatch")
        } catch let error as KaminoServiceError {
            XCTAssertEqual(
                error,
                .vaultMetadataMismatch(field: "tokenMintDecimals", expected: "9", actual: "64")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// A descriptor is the app's record of a vault's identity. One that merely
    /// carries a curated address while describing itself differently is not that
    /// record, and hydrating it would put fabricated mints in front of every
    /// later check.
    func test_aDescriptorTheRegistryDoesNotRecogniseIsRejected() async {
        let impostor = KaminoVaultDescriptor(
            address: KaminoVaultRegistry.allezSOL.address,
            tokenMint: KaminoVaultRegistry.allezSOL.tokenMint,
            tokenDecimals: 9,
            sharesMint: KaminoVaultRegistry.steakhouseUSDC.sharesMint,
            sharesDecimals: 6,
            farm: KaminoVaultRegistry.allezSOL.farm,
            fallbackName: "Allez SOL",
            curator: "Allez Labs",
            riskTier: .conservative
        )

        do {
            _ = try await service.fetchVaultInfo(descriptor: impostor)
            XCTFail("Expected an unregistered-vault error")
        } catch let error as KaminoServiceError {
            XCTAssertEqual(error, .vaultNotInRegistry(impostor.address))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNil(http.lastRequestBody(), "no request should have been issued")
    }

    /// The mints and the farm decide where funds go, so they are pinned in the
    /// registry and a response that disagrees is refused rather than merged. A
    /// transaction built by the API cannot be validated against metadata the same
    /// API supplied.
    func test_vaultMetadataDisagreeingWithTheRegistryIsRejected() async {
        http.queueJSON(Fixtures.stateWithSubstitutedFarm, for: .state)
        http.queueJSON(Fixtures.allezMetrics, for: .metrics)

        do {
            _ = try await service.fetchVaultInfo(descriptor: KaminoVaultRegistry.allezSOL)
            XCTFail("Expected a vault-metadata mismatch")
        } catch let error as KaminoServiceError {
            XCTAssertEqual(
                error,
                .vaultMetadataMismatch(
                    field: "vaultFarm",
                    expected: "H6kauPaHmNqpdKtD5U2zw3Eb28ZB7iMeBdHVfLq1i4Kh",
                    actual: "9FVjHqduhDPMVqvu3cXiEBjU6nvxvGdCCLRwd9WpVRZj"
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertInvalidAmount(
        _ operation: () async throws -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected an invalid-amount error", file: file, line: line)
        } catch let error as KaminoServiceError {
            guard case .invalidAmount = error else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func test_unstructuredHTTPError_propagatesUnchanged() async {
        http.queueError(.statusCode(503, Data("gateway".utf8)), for: .state)

        do {
            _ = try await service.fetchVaultState(address: Fixtures.steakhouseAddress)
            XCTFail("Expected the HTTP error to propagate")
        } catch let error as HTTPError {
            guard case .statusCode(let code, _) = error else {
                return XCTFail("Unexpected HTTPError variant: \(error)")
            }
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_malformedMetricNumber_throwsRatherThanDefaultingToZero() async {
        http.queueJSON(Fixtures.allezState, for: .state)
        http.queueJSON(Fixtures.metricsWithGroupedApy, for: .metrics)

        do {
            _ = try await service.fetchVaultInfo(descriptor: KaminoVaultRegistry.allezSOL)
            XCTFail("Expected a malformed-number error")
        } catch let error as KaminoServiceError {
            XCTAssertEqual(error, .malformedNumber(field: "apy30d", value: "1,234.5"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Fixtures

private enum Fixtures {
    static let steakhouseAddress = "HDsayqAsDWy3QvANGqh2yNraqcD8Fnjgh73Mhb3WRS5E"
    static let allezAddress = "A1so1bPD3W1TfeFwboDh8yfAAVaVtcdAYBYCjhg2mJQ"
    static let owner = "CXFmQi2eM4Jzt9HZwm9A5JAzGvNpKwRuxo52ua3Jyceh"

    static let steakhouseState = """
    {"address":"\(steakhouseAddress)","programId":"KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd",
     "state":{"name":"Steakhouse USDC","tokenMint":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
     "tokenMintDecimals":6,"sharesMint":"7D8C5pDFxug58L9zkwK7bCiDg4kD4AygzbcZUmf5usHS",
     "sharesMintDecimals":6,"minDepositAmount":"100000","minWithdrawAmount":"1000",
     "vaultLookupTable":"9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu",
     "vaultFarm":"9FVjHqduhDPMVqvu3cXiEBjU6nvxvGdCCLRwd9WpVRZj",
     "performanceFeeBps":500,"managementFeeBps":0}}
    """

    static let allezState = """
    {"address":"\(allezAddress)","programId":"KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd",
     "state":{"name":"Allez SOL","tokenMint":"So11111111111111111111111111111111111111112",
     "tokenMintDecimals":9,"sharesMint":"FiM4VQdXXnTXL7GgChryf9zHNG9cmvKECwf34L2y3CkN",
     "sharesMintDecimals":6,"minDepositAmount":"10000000","minWithdrawAmount":"1000",
     "vaultLookupTable":"7EzosNioQ6FDNvMKLfg6om5wTVHiJo9vVx7DZNGYBKU3",
     "vaultFarm":"H6kauPaHmNqpdKtD5U2zw3Eb28ZB7iMeBdHVfLq1i4Kh",
     "performanceFeeBps":500,"managementFeeBps":0}}
    """

    /// Captured alongside the state above. The rate is what makes the token/share
    /// distinction visible on a dollar vault: it is near 1, so reading
    /// `minWithdrawAmount` in the wrong unit is off by only ~5% here — and by a
    /// factor of ~930 on the SOL vault.
    static let steakhouseMetrics = """
    {"apy30d":"0.039385625354500915856","tokensPerShare":"1.053852800799466169",
     "sharePrice":"1.053852800799466169","tokenPrice":"0.99987",
     "tokensAvailable":"72296.121119","tokensInvested":"19825431.882"}
    """

    static let allezMetrics = """
    {"apy30d":"0.066908831669281033201","tokensPerShare":"0.0010749299151180878396",
     "sharePrice":"0.079437779653781828774","tokenPrice":"73.900426936257595",
     "tokensAvailable":"34.19551574","tokensInvested":"85886.966434150043482"}
    """

    /// Same shape, but with a grouped APY the strict parser must reject.
    static let metricsWithGroupedApy = """
    {"apy30d":"1,234.5","tokensPerShare":"0.0010749299151180878396",
     "sharePrice":"0.079437779653781828774","tokenPrice":"73.900426936257595",
     "tokensAvailable":"34.19551574","tokensInvested":"85886.966434150043482"}
    """

    static let positions = """
    [{"vaultAddress":"\(steakhouseAddress)","stakedShares":"0",
      "unstakedShares":"517536.857982","totalShares":"517536.857982"}]
    """

    static let pnl = """
    {"totalCostBasis":{"token":"528214.9564752811641","sol":"2205.9506713821705758",
      "usd":"528083.63695495184445"},
     "totalPnl":{"token":"17064.57109480498919","sol":"5199.4589620796208721",
      "usd":"17065.96140930490871"}}
    """

    static let actionResponse = #"{"transaction":"AQAAdGVzdA=="}"#

    static let vaultNotFound = """
    {"statusCode":400,"message":"Kamino Earn Vault does not exist",
     "error":"Bad Request","code":"KVAULT_NOT_FOUND"}
    """

    /// Same envelope shape as the 400 above — the reason the HTTP status has to
    /// survive the mapping.
    static let serviceUnavailable = """
    {"statusCode":503,"message":"Service temporarily unavailable",
     "error":"Service Unavailable","code":null}
    """

    static let stateWithAbsurdDecimals = """
    {"address":"\(allezAddress)","programId":"KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd",
     "state":{"name":"Allez SOL","tokenMint":"So11111111111111111111111111111111111111112",
     "tokenMintDecimals":64,"sharesMint":"FiM4VQdXXnTXL7GgChryf9zHNG9cmvKECwf34L2y3CkN",
     "sharesMintDecimals":6,"minDepositAmount":"10000000","minWithdrawAmount":"1000",
     "vaultLookupTable":"7EzosNioQ6FDNvMKLfg6om5wTVHiJo9vVx7DZNGYBKU3",
     "vaultFarm":"H6kauPaHmNqpdKtD5U2zw3Eb28ZB7iMeBdHVfLq1i4Kh",
     "performanceFeeBps":500,"managementFeeBps":0}}
    """

    /// The Allez vault as the API would describe it if it named another vault's
    /// farm — the shape a response would take to stake the user's shares
    /// somewhere the app never reads.
    static let stateWithSubstitutedFarm = """
    {"address":"\(allezAddress)","programId":"KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd",
     "state":{"name":"Allez SOL","tokenMint":"So11111111111111111111111111111111111111112",
     "tokenMintDecimals":9,"sharesMint":"FiM4VQdXXnTXL7GgChryf9zHNG9cmvKECwf34L2y3CkN",
     "sharesMintDecimals":6,"minDepositAmount":"10000000","minWithdrawAmount":"1000",
     "vaultLookupTable":"7EzosNioQ6FDNvMKLfg6om5wTVHiJo9vVx7DZNGYBKU3",
     "vaultFarm":"9FVjHqduhDPMVqvu3cXiEBjU6nvxvGdCCLRwd9WpVRZj",
     "performanceFeeBps":500,"managementFeeBps":0}}
    """
}

// MARK: - Test double

/// Serves raw JSON so the tests exercise the real decoding path (the typed
/// `request<T>` overload is a protocol-extension default over this one).
///
/// Responses are keyed by endpoint, not by call order. `fetchVaultInfo` issues
/// its state and metrics requests concurrently with `async let`, so a FIFO queue
/// resolves them in nondeterministic order and hands each request the other's
/// body — which decodes as a `keyNotFound` failure rather than anything
/// resembling the real defect. Access is locked because those calls genuinely
/// arrive on different threads.
private final class StubKaminoHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    enum Route: Hashable {
        case state, metrics, positions, pnl, deposit, withdraw
    }

    private enum Queued {
        case json(String)
        case error(HTTPError)
    }

    private let lock = NSLock()
    private var routes: [Route: Queued] = [:]
    private var targets: [KaminoAPI] = []

    func queueJSON(_ json: String, for route: Route) {
        lock.withLock { routes[route] = .json(json) }
    }

    func queueError(_ error: HTTPError, for route: Route) {
        lock.withLock { routes[route] = .error(error) }
    }

    /// The body of the most recent action request, read back off the target.
    func lastRequestBody() -> KaminoActionRequest? {
        lock.withLock {
            guard let target = targets.last else { return nil }
            switch target {
            case .deposit(let request), .withdraw(let request):
                return request
            default:
                return nil
            }
        }
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let kamino = target as? KaminoAPI else {
            XCTFail("StubKaminoHTTPClient received a non-Kamino target")
            throw HTTPError.invalidResponse
        }

        let queued: Queued? = lock.withLock {
            targets.append(kamino)
            return routes[Self.route(for: kamino)]
        }

        guard let queued else {
            XCTFail("No stubbed response for \(kamino.path)")
            throw HTTPError.invalidResponse
        }

        switch queued {
        case .error(let error):
            throw error
        case .json(let json):
            guard let url = URL(string: "https://test.local"),
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: nil
                  )
            else {
                throw HTTPError.invalidResponse
            }
            return HTTPResponse(data: Data(json.utf8), response: response)
        }
    }

    private static func route(for target: KaminoAPI) -> Route {
        switch target {
        case .vaultState: return .state
        case .vaultMetrics: return .metrics
        case .userPositions: return .positions
        case .positionPnl: return .pnl
        case .deposit: return .deposit
        case .withdraw: return .withdraw
        }
    }
}
