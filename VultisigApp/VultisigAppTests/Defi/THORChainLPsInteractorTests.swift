//
//  THORChainLPsInteractorTests.swift
//  VultisigAppTests
//
//  Note: branching tests for `convertToLPPositions` (asset-format parsing,
//  RUNE/asset coin lookup) need either a protocol extraction over
//  `THORChainAPIService.getLPPositions` or fixture injection. For now we
//  assert the early-return guard and document the gap in
//  [[projects/vultisig/defi-tab-fixes/architecture-review]].
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class THORChainLPsInteractorTests: XCTestCase {

    func testFetchLPPositionsReturnsEmptyWithoutRuneCoin() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()
        // No RUNE coin → early-return guard returns [] without an API call.
        let result = await THORChainLPsInteractor().fetchLPPositions(vault: vault)
        XCTAssertTrue(result.isEmpty)
    }

    func testPoolStatsRequestDoesNotAskMidgardForAvailableOnly() {
        guard case .requestParameters(let parameters, _) = THORChainLPsAPI.getPoolStats(period: nil).task else {
            return XCTFail("pool stats should be URL-parameterized")
        }

        XCTAssertEqual(parameters["period"] as? String, "30d")
        XCTAssertNil(parameters["status"], "status filtering is client-side so staged pools are visible")
    }

    func testGetLPPositionsIncludesStagedPoolsAndSkipsSuspendedPools() async throws {
        let client = ThorchainLPsHTTPClient(poolsJSON: Self.poolStatsJSON)
        let service = THORChainAPIService(httpClient: client)

        let positions = try await service.getLPPositions(
            address: FunctionActionFixture.thorAddress,
            userLPs: [AddLPFixture.ethPool, AddLPFixture.usdcPool].compactMap {
                THORChainAssetFactory.createCoin(from: $0)
            },
            period: "30d"
        )

        let liquidityProviderRequestCount = await client.liquidityProviderRequestCount()

        XCTAssertEqual(positions.map(\.asset), [AddLPFixture.ethPool, AddLPFixture.usdcPool])
        XCTAssertTrue(positions.allSatisfy { $0.poolStats.supportsPairedLPAdd })
        XCTAssertEqual(liquidityProviderRequestCount, 2)
    }

    private static let poolStatsJSON = """
    [
      {
        "asset": "\(AddLPFixture.ethPool)",
        "assetDepth": "1000",
        "runeDepth": "1000",
        "liquidityUnits": "1000",
        "annualPercentageRate": "0.01",
        "poolAPY": "0.01",
        "assetPrice": "1",
        "assetPriceUSD": "1",
        "status": "available",
        "units": "1000"
      },
      {
        "asset": "\(AddLPFixture.usdcPool)",
        "assetDepth": "1000",
        "runeDepth": "1000",
        "liquidityUnits": "1000",
        "annualPercentageRate": "0.02",
        "poolAPY": "0.02",
        "assetPrice": "1",
        "assetPriceUSD": "1",
        "status": "staged",
        "units": "1000"
      },
      {
        "asset": "ETH.DAI-0X6B175474E89094C44DA98B954EEDEAC495271D0F",
        "assetDepth": "1000",
        "runeDepth": "1000",
        "liquidityUnits": "1000",
        "annualPercentageRate": "0.03",
        "poolAPY": "0.03",
        "assetPrice": "1",
        "assetPriceUSD": "1",
        "status": "suspended",
        "units": "1000"
      }
    ]
    """
}

private actor ThorchainLPsHTTPClient: HTTPClientProtocol {
    private let poolsJSON: String
    private(set) var liquidityProviderPaths: [String] = []

    init(poolsJSON: String) {
        self.poolsJSON = poolsJSON
    }

    func liquidityProviderRequestCount() -> Int {
        liquidityProviderPaths.count
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        let body: String
        if target.path == "/v2/pools" {
            body = poolsJSON
        } else {
            liquidityProviderPaths.append(target.path)
            body = """
            {
              "asset": "BTC.BTC",
              "rune_address": "\(FunctionActionFixture.thorAddress)",
              "asset_address": "asset-address",
              "last_add_height": 1,
              "units": "1000",
              "pending_rune": "0",
              "pending_asset": "0",
              "pending_tx_id": null,
              "rune_deposit_value": "100",
              "asset_deposit_value": "200",
              "rune_redeem_value": "100",
              "asset_redeem_value": "200",
              "luvi_deposit_value": "1",
              "luvi_redeem_value": "1",
              "luvi_growth_pct": "0"
            }
            """
        }

        let url = URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }
}
