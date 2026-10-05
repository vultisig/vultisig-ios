//
//  MayaPendingLPDepositTests.swift
//  VultisigAppTests
//
//  A paired add mints no LP units until both sides arrive, so a half-finished
//  one reads as an empty position while MayaChain holds the deposit and counts
//  down to refunding it.
//

import XCTest
@testable import VultisigApp

final class MayaPendingLPDepositTests: XCTestCase {

    private let cacao = "maya1vault"
    private let asset = "0xvaultasset"

    private func record(
        units: String = "0",
        pendingCacao: String = "0",
        pendingAsset: String = "0",
        pendingTxId: String? = "TX",
        lastAddHeight: Int64? = 1000
    ) -> MayaLiquidityProvider {
        MayaLiquidityProvider(
            asset: "ETH.ETH",
            cacaoAddress: cacao,
            assetAddress: asset,
            units: units,
            pendingCacao: pendingCacao,
            pendingAsset: pendingAsset,
            pendingTxId: pendingTxId,
            lastAddHeight: lastAddHeight
        )
    }

    // MARK: - From a record

    func testARecordWithNothingPendingIsNotADeposit() {
        XCTAssertNil(MayaPendingLPDeposit(pool: "ETH.ETH", record: record()))
    }

    func testAPendingAssetIsAwaitingTheCacaoSide() throws {
        let deposit = try XCTUnwrap(MayaPendingLPDeposit(pool: "ETH.ETH", record: record(pendingAsset: "100000")))

        XCTAssertFalse(deposit.isCacaoPending)
        XCTAssertEqual(deposit.pendingAsset, 100_000)
        XCTAssertEqual(deposit.pairedAddress, cacao, "the missing CACAO side comes from the CACAO address")
        XCTAssertEqual(deposit.pendingTxId, "TX")
    }

    func testAPendingCacaoIsAwaitingTheAssetSide() throws {
        let deposit = try XCTUnwrap(MayaPendingLPDeposit(pool: "ETH.ETH", record: record(pendingCacao: "5000000000")))

        XCTAssertTrue(deposit.isCacaoPending)
        XCTAssertEqual(deposit.pairedAddress, asset, "the missing asset side comes from the asset address")
    }

    /// A top-up's pending half sits on a live position's record.
    func testALivePositionCanStillHoldAPendingHalf() {
        XCTAssertNotNil(MayaPendingLPDeposit(pool: "ETH.ETH", record: record(units: "900", pendingAsset: "1")))
    }

    // MARK: - Refund countdown

    func testTheCountdownRunsFromTheLastAddToTheAgeLimit() {
        XCTAssertEqual(
            MayaPendingLPDeposit.blocksUntilRefund(lastAddHeight: 1000, ageLimit: 100_800, currentHeight: 50_000),
            51_800
        )
    }

    func testTheCountdownNeverGoesNegative() {
        XCTAssertEqual(
            MayaPendingLPDeposit.blocksUntilRefund(lastAddHeight: 1000, ageLimit: 100, currentHeight: 5000),
            0
        )
    }

    func testTheCountdownIsUnknownWithoutAllThreeInputs() {
        XCTAssertNil(MayaPendingLPDeposit.blocksUntilRefund(lastAddHeight: nil, ageLimit: 100, currentHeight: 5))
        XCTAssertNil(MayaPendingLPDeposit.blocksUntilRefund(lastAddHeight: 1, ageLimit: nil, currentHeight: 5))
        XCTAssertNil(MayaPendingLPDeposit.blocksUntilRefund(lastAddHeight: 1, ageLimit: 100, currentHeight: nil))
    }

    // MARK: - Scan

    private func poolsJSON(pending: [String: (cacao: String, asset: String)]) -> String {
        let rows = ["BTC.BTC", "ETH.ETH", "ZEC.ZEC"].map { pool -> String in
            let p = pending[pool] ?? ("0", "0")
            return """
            {"asset":"\(pool)","status":"Available","balance_cacao":"1","balance_asset":"1","pool_units":"1",
             "LP_units":"1","synth_units":"0","synth_supply":"0",
             "pending_inbound_cacao":"\(p.cacao)","pending_inbound_asset":"\(p.asset)"}
            """
        }
        return "[\(rows.joined(separator: ","))]"
    }

    func testTheScanReadsOnlyPoolsHoldingPendingLiquidityAndAddsTheCountdown() async throws {
        let stub = RoutingLPHTTPClient(routes: [
            "/mayachain/pools": poolsJSON(pending: ["ETH.ETH": ("0", "100000")]),
            "/mayachain/pool/ETH.ETH/liquidity_provider/\(cacao)": """
            {"asset":"ETH.ETH","cacao_address":"\(cacao)","asset_address":"\(asset)","units":"0",
             "pending_cacao":"0","pending_asset":"100000","pending_tx_id":"TX","last_add_height":1000}
            """,
            "/mayachain/mimir": #"{"PENDINGLIQUIDITYAGELIMIT": 2000}"#,
            "/mayachain/lastblock": #"[{"mayachain": 1500}]"#
        ])
        let service = MayaChainAPIService(httpClient: stub)

        let deposits = try await service.getPendingLPDeposits(cacaoAddress: cacao).deposits

        XCTAssertEqual(deposits.map(\.pool), ["ETH.ETH"])
        XCTAssertEqual(deposits.first?.blocksUntilRefund, 1500)
        XCTAssertFalse(stub.paths.contains { $0.contains("BTC.BTC") || $0.contains("ZEC.ZEC") })
    }

    func testTheDefaultAgeLimitAppliesWhenMimirNamesNone() async throws {
        let stub = RoutingLPHTTPClient(routes: [
            "/mayachain/pools": poolsJSON(pending: ["ETH.ETH": ("0", "1")]),
            "/mayachain/pool/ETH.ETH/liquidity_provider/\(cacao)": """
            {"asset":"ETH.ETH","cacao_address":"\(cacao)","asset_address":"\(asset)","units":"0",
             "pending_cacao":"0","pending_asset":"1","pending_tx_id":"TX","last_add_height":1000}
            """,
            "/mayachain/mimir": "{}",
            "/mayachain/lastblock": #"[{"mayachain": 1100}]"#
        ])
        let scan = try await MayaChainAPIService(httpClient: stub).getPendingLPDeposits(cacaoAddress: cacao)
        let deposits = scan.deposits

        XCTAssertEqual(deposits.first?.blocksUntilRefund, 100_700)
    }

    func testAnUnreadableHeightLeavesTheCountdownUnknown() async throws {
        let stub = RoutingLPHTTPClient(routes: [
            "/mayachain/pools": poolsJSON(pending: ["ETH.ETH": ("0", "1")]),
            "/mayachain/pool/ETH.ETH/liquidity_provider/\(cacao)": """
            {"asset":"ETH.ETH","cacao_address":"\(cacao)","asset_address":"\(asset)","units":"0",
             "pending_cacao":"0","pending_asset":"1","pending_tx_id":"TX","last_add_height":1000}
            """,
            "/mayachain/mimir": "{}"
        ])
        let scan = try await MayaChainAPIService(httpClient: stub).getPendingLPDeposits(cacaoAddress: cacao)
        let deposits = scan.deposits

        XCTAssertEqual(deposits.count, 1)
        XCTAssertNil(deposits.first?.blocksUntilRefund)
    }

    func testAFailedPoolScanThrowsRatherThanReadingAsNoDeposits() async {
        let stub = RoutingLPHTTPClient(routes: [:])
        do {
            _ = try await MayaChainAPIService(httpClient: stub).getPendingLPDeposits(cacaoAddress: cacao)
            XCTFail("an outage must not read as an empty list")
        } catch {}
    }

    func testAFailedRecordReadDropsOnlyThatPool() async throws {
        let stub = RoutingLPHTTPClient(routes: [
            "/mayachain/pools": poolsJSON(pending: ["ETH.ETH": ("0", "1"), "BTC.BTC": ("5", "0")]),
            "/mayachain/pool/BTC.BTC/liquidity_provider/\(cacao)": """
            {"asset":"BTC.BTC","cacao_address":"\(cacao)","asset_address":"bc1q","units":"0",
             "pending_cacao":"5","pending_asset":"0","pending_tx_id":"TX2","last_add_height":10}
            """,
            "/mayachain/mimir": "{}",
            "/mayachain/lastblock": #"[{"mayachain": 20}]"#
        ])
        let scan = try await MayaChainAPIService(httpClient: stub).getPendingLPDeposits(cacaoAddress: cacao)
        let deposits = scan.deposits

        XCTAssertEqual(deposits.map(\.pool), ["BTC.BTC"])
        XCTAssertFalse(scan.isComplete, "a pool that could not be read may hide a deposit")
    }

    func testAScanThatReadEveryPoolIsComplete() async throws {
        let stub = RoutingLPHTTPClient(routes: [
            "/mayachain/pools": poolsJSON(pending: [:])
        ])
        let scan = try await MayaChainAPIService(httpClient: stub).getPendingLPDeposits(cacaoAddress: cacao)
        XCTAssertEqual(scan, MayaPendingLPScan(deposits: [], isComplete: true))
    }
}

/// Answers each path with a fixed body and anything else with a 500.
final class RoutingLPHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let routes: [String: String]
    private let lock = NSLock()
    private var requested: [String] = []

    init(routes: [String: String]) {
        self.routes = routes
    }

    var paths: [String] {
        lock.lock(); defer { lock.unlock() }
        return requested
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        lock.lock(); requested.append(target.path); lock.unlock()
        guard let body = routes[target.path] else { throw HTTPError.statusCode(500, Data()) }
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw HTTPError.statusCode(500, Data())
    }
}
