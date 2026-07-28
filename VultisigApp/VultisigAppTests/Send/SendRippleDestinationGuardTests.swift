//
//  SendRippleDestinationGuardTests.swift
//  VultisigAppTests
//
//  Covers the Verify-stage wiring of the XRP pre-ceremony guards:
//  `SendCryptoVerifyLogic.validateDestinationIfNeeded` runs the RippleService
//  destination check for native XRP sends only — every other chain must pass
//  through without touching the network — and
//  `validateTrustLineReserveIfNeeded` blocks a TrustSet the account cannot
//  afford, at the exact drop.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendRippleDestinationGuardTests: XCTestCase {

    private var token: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func testNonRippleSendSkipsDestinationLookup() async throws {
        // The client trips on ANY request — passing proves no network access.
        let client = TrippingHTTPClient()
        let logic = makeLogic(client: client)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let tx = makeTransaction(coin: eth, amount: "0.1")

        try await logic.validateDestinationIfNeeded(tx: tx)
        XCTAssertEqual(client.requestCount, 0)
    }

    func testRippleSendToFundedDestinationPasses() async throws {
        let client = TrippingHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"account_data":{"Account":"rFunded","Balance":"20000000","OwnerCount":0,"Sequence":7},"status":"success","validated":true}}
        """.utf8))
        let logic = makeLogic(client: client)
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6)
        let tx = makeTransaction(coin: xrp, amount: "0.5")

        try await logic.validateDestinationIfNeeded(tx: tx)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testRippleSendToUnfundedDestinationBelowReserveThrows() async throws {
        let client = TrippingHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"error":"actNotFound","error_code":19,"error_message":"Account not found.","status":"error","validated":false}}
        """.utf8))
        client.serverStateResult = .success(Data("""
        {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":1000000,"reserve_inc":200000}}}}
        """.utf8))
        let logic = makeLogic(client: client)
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6)
        // 0.5 XRP = 500,000 drops < the 1 XRP base reserve.
        let tx = makeTransaction(coin: xrp, amount: "0.5")

        do {
            try await logic.validateDestinationIfNeeded(tx: tx)
            XCTFail("a sub-reserve send to an unfunded XRP destination must be blocked before the ceremony")
        } catch let error as HelperError {
            // Rewrapped for the Verify screen's alert plumbing, which presents
            // only HelperError; the message must carry the localized copy.
            guard case .runtimeError(let message) = error else {
                return XCTFail("unexpected HelperError: \(error)")
            }
            XCTAssertTrue(message.contains("XRP"), "expected the destination-activation copy, got: \(message)")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testRippleDestinationCancellationPropagatesNotRewrapped() async throws {
        // A cancelled lookup must propagate as CancellationError, NOT be
        // rewrapped as HelperError — otherwise the load-time guard would turn a
        // torn-down screen into a spurious balance error.
        let client = TrippingHTTPClient()
        client.accountInfoResult = .failure(CancellationError())
        let logic = makeLogic(client: client)
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6)
        let tx = makeTransaction(coin: xrp, amount: "0.5")

        do {
            try await logic.validateDestinationIfNeeded(tx: tx)
            XCTFail("cancellation must propagate")
        } catch is CancellationError {
            // expected — not rewrapped
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - TrustSet reserve guard

    /// The boundary the guard turns on: spendable XRP covering the owner reserve
    /// plus the fee EXACTLY is affordable. Pinned so the condition can never be
    /// re-spelled off by one drop.
    func testTrustSetWithExactlySpendableReservePlusFeePasses() async throws {
        let client = TrippingHTTPClient()
        client.serverStateResult = .success(Self.serverStateData)
        let logic = makeLogic(client: client)
        let tx = makeTrustSetTransaction(xrpRawBalance: Self.requiredDrops.description, fee: Self.fee)

        try await logic.validateTrustLineReserveIfNeeded(tx: tx)

        XCTAssertEqual(client.requestCount, 1, "the reserve must be read from the node, not seeded")
    }

    /// One drop short is blocked — the TrustSet would otherwise fail on-ledger
    /// with `tecINSUFFICIENT_RESERVE` after the ceremony, fee already burned.
    func testTrustSetOneDropShortOfTheReserveIsBlocked() async throws {
        let client = TrippingHTTPClient()
        client.serverStateResult = .success(Self.serverStateData)
        let logic = makeLogic(client: client)
        let tx = makeTrustSetTransaction(xrpRawBalance: (Self.requiredDrops - 1).description, fee: Self.fee)

        do {
            try await logic.validateTrustLineReserveIfNeeded(tx: tx)
            XCTFail("an unaffordable TrustSet must be blocked before the ceremony")
        } catch let error as HelperError {
            guard case .runtimeError(let message) = error else {
                return XCTFail("unexpected HelperError: \(error)")
            }
            // The copy quotes what the operation really costs, in whole XRP.
            XCTAssertTrue(
                message.contains(RippleReserve.xrpAmount(drops: Self.requiredDrops)),
                "expected the required total in the copy, got: \(message)"
            )
            XCTAssertEqual(client.requestCount, 1, "the reserve must be read from the node, not seeded")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    /// A trust line is an object owned by an XRP account: with no XRP coin there
    /// is nothing to attach it to and nothing to pay the fee. Fails closed,
    /// before any network call.
    func testTrustSetWithoutAnXrpCoinIsBlocked() async throws {
        let client = TrippingHTTPClient()
        let logic = makeLogic(client: client)
        let tx = makeTrustSetTransaction(
            xrpRawBalance: Self.requiredDrops.description,
            fee: Self.fee,
            includeXrpCoin: false
        )

        do {
            try await logic.validateTrustLineReserveIfNeeded(tx: tx)
            XCTFail("a TrustSet with no XRP account must be blocked")
        } catch is HelperError {
            XCTAssertEqual(client.requestCount, 0, "the guard must fail closed without a lookup")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    /// Every non-TrustSet transaction passes through untouched — the client trips
    /// on any request, so a zero count proves the guard never reaches the network.
    func testNonTrustSetTransactionSkipsTheReserveGuard() async throws {
        let client = TrippingHTTPClient()
        let logic = makeLogic(client: client)
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6)
        let tx = makeTransaction(coin: xrp, amount: "0.5")

        try await logic.validateTrustLineReserveIfNeeded(tx: tx)
        XCTAssertEqual(client.requestCount, 0)
    }

    /// A cancelled reserve read must propagate, NOT fall through to a seeded
    /// verdict. `hasBalanceError` / `errorMessage` are shared `@Published` state,
    /// so a stale cancelled pass that answers anyway can overwrite a newer one.
    ///
    /// The balance here is affordable under the SEED but not under the stubbed
    /// increment, so swallowing the cancel would return success — the silent
    /// half of the bug, invisible to a test that only checks for a thrown error.
    func testTrustSetReserveCancellationPropagatesRatherThanSeedingSuccess() async throws {
        let client = TrippingHTTPClient()
        client.serverStateResult = .failure(CancellationError())
        let logic = makeLogic(client: client)
        // 300,000 drops: over the seeded 200,020 requirement, under the stubbed
        // 500,020 one.
        let tx = makeTrustSetTransaction(xrpRawBalance: "300000", fee: Self.fee)

        do {
            try await logic.validateTrustLineReserveIfNeeded(tx: tx)
            XCTFail("a cancelled reserve read must not seed its way to success")
        } catch is CancellationError {
            // expected — the caller's cancellation branch aborts the load pass
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    /// The other half: a cancelled read must not become a `HelperError` either.
    /// The balance is below even the seeded requirement, so swallowing the cancel
    /// would raise the insufficient-XRP alert and leave Sign blocked on a pass
    /// that was already superseded.
    func testTrustSetReserveCancellationIsNotRewrappedAsABalanceError() async throws {
        let client = TrippingHTTPClient()
        client.serverStateResult = .failure(CancellationError())
        let logic = makeLogic(client: client)
        let tx = makeTrustSetTransaction(xrpRawBalance: "100000", fee: Self.fee)

        do {
            try await logic.validateTrustLineReserveIfNeeded(tx: tx)
            XCTFail("cancellation must propagate")
        } catch is CancellationError {
            // expected — not rewrapped into a spurious balance error
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    /// Both cancellation tests are only meaningful if the seeded fallback would
    /// really have produced a different verdict than propagating.
    func testTheSeededOwnerReserveWouldChangeBothCancellationVerdicts() {
        let seeded = RippleReserve.reservedDrops(ownerCount: 1, reserveBase: 0, reserveInc: nil) + Self.fee
        XCTAssertLessThan(seeded, BigInt(300_000), "the seeded requirement must be affordable at 300,000 drops")
        XCTAssertGreaterThan(seeded, BigInt(100_000), "the seeded requirement must be unaffordable at 100,000 drops")
        XCTAssertGreaterThan(Self.requiredDrops, BigInt(300_000), "the live requirement must be unaffordable at 300,000 drops")
    }

    /// The two boundary tests above only prove the reserve was read LIVE if the
    /// stubbed increment differs from the seed the guard falls back to.
    func testTheStubbedOwnerReserveIsNotTheSeed() {
        XCTAssertNotEqual(
            Self.ownerReserveDrops,
            RippleReserve.seedReserveIncDrops,
            "pick a stubbed reserve_inc the seed cannot coincidentally match"
        )
    }

    // MARK: - Fixtures

    /// Owner reserve the node reports. Deliberately NOT
    /// `RippleReserve.seedReserveIncDrops`, so a test only passes if the guard
    /// really read `server_state` — falling back to the seed changes the answer.
    private static let ownerReserveDrops = BigInt(500_000)
    private static let fee = BigInt(20)
    /// What the TrustSet costs: one owner increment plus the fee. `reserve_base`
    /// is excluded — the account already exists and already meets it.
    private static var requiredDrops: BigInt { ownerReserveDrops + fee }

    /// `reserve_inc` set to the value above; `reserve_base` left at the mainnet
    /// 1 XRP the guard never reads.
    private static let serverStateData = Data("""
    {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":1000000,"reserve_inc":500000}}}}
    """.utf8)

    /// A TrustSet on an XRPL issued currency, in a vault that holds the XRP coin
    /// paying for it unless `includeXrpCoin` says otherwise.
    private func makeTrustSetTransaction(
        xrpRawBalance: String,
        fee: BigInt,
        includeXrpCoin: Bool = true
    ) -> SendTransaction {
        let tokenAsset = CoinMeta(
            chain: .ripple,
            ticker: "USD",
            logo: "",
            decimals: 15,
            priceProviderId: "trustset-guard-\(UUID().uuidString)",
            contractAddress: "USD.rvYAfWj5gh67oV6fW32ZzP3Aw4Eubs59B",
            isNativeToken: false
        )
        let token = Coin(asset: tokenAsset, address: "rTrustSetAccountUnderTest", hexPublicKey: "")
        token.rawBalance = "0"

        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6)
        xrp.rawBalance = xrpRawBalance

        let vault = TestStore.makeVault()
        vault.coins = includeXrpCoin ? [xrp, token] : [token]

        return SendTransaction(
            coin: token,
            vault: vault,
            fromAddress: token.address,
            toAddress: token.address,
            toAddressLabel: nil,
            amount: "1000000000000000",
            amountInFiat: "",
            memo: "",
            gas: BigInt.zero,
            fee: fee,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .rippleTrustSet,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: xrp
        )
    }

    private func makeLogic(client: HTTPClientProtocol) -> SendCryptoVerifyLogic {
        SendCryptoVerifyLogic(
            interactor: MockSendInteractor(),
            rippleService: RippleService(resolver: NoOverrideResolver(), httpClient: client)
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        var asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true)
        asset.priceProviderId = "dest-guard-\(ticker)-\(UUID().uuidString)"
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = "100000000"
        return coin
    }

    private func makeTransaction(coin: Coin, amount: String) -> SendTransaction {
        let vault = TestStore.makeVault()
        return SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: "rDestinationAddressUnderTest",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "",
            gas: BigInt.zero,
            fee: BigInt(20),
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

// `async` is required by `HTTPClientProtocol`; the stub answers synchronously.
// swiftlint:disable async_without_await

/// Scripted client that counts requests and fails on anything unscripted, so a
/// test can prove a code path never touches the network.
private final class TrippingHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    var accountInfoResult: Result<Data, Error> = .failure(URLError(.badServerResponse))
    var serverStateResult: Result<Data, Error> = .failure(URLError(.badServerResponse))

    private let queue = DispatchQueue(label: "TrippingHTTPClient.queue")
    private var _requestCount = 0

    var requestCount: Int {
        queue.sync { _requestCount }
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        queue.sync { _requestCount += 1 }
        guard let api = target as? RippleAPI else {
            throw URLError(.unsupportedURL)
        }
        switch api.endpoint {
        case .accountInfo:
            return try respond(accountInfoResult)
        case .serverState:
            return try respond(serverStateResult)
        case .submit, .tx, .accountLines:
            throw URLError(.unsupportedURL)
        }
    }

    private func respond(_ result: Result<Data, Error>) throws -> HTTPResponse<Data> {
        let data = try result.get()
        guard let url = URL(string: "https://xrplcluster.com"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badURL)
        }
        return HTTPResponse(data: data, response: response)
    }
}

// swiftlint:enable async_without_await
