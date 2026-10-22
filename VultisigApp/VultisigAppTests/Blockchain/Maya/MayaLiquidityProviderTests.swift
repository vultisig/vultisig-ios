//
//  MayaLiquidityProviderTests.swift
//  VultisigAppTests
//
//  mayanode records an asset address only on a zero-unit record, so a vault that
//  already holds a CACAO-only position has none, and any add naming one is
//  refunded. These rules decide whether a paired add may be signed at all.
//

import XCTest
@testable import VultisigApp

final class MayaLiquidityProviderTests: XCTestCase {

    private let cacao = "maya1vault"
    private let asset = "0xAbCdEf"

    private func record(
        units: String = "0",
        cacaoAddress: String? = nil,
        assetAddress: String? = nil,
        pendingTxId: String? = nil
    ) -> MayaLiquidityProvider {
        MayaLiquidityProvider(
            asset: "ETH.ETH",
            cacaoAddress: cacaoAddress,
            assetAddress: assetAddress,
            units: units,
            pendingCacao: "0",
            pendingAsset: "0",
            pendingTxId: pendingTxId,
            lastAddHeight: nil
        )
    }

    func testAFreshRecordTakesWhateverAddressesTheAddNames() {
        XCTAssertEqual(record().pairing(cacaoAddress: cacao, assetAddress: asset), .pairable)
    }

    func testAPendingHalfFromTheSameAddressesCompletes() {
        let pending = record(cacaoAddress: cacao, assetAddress: asset.lowercased(), pendingTxId: "ABC")
        XCTAssertEqual(pending.pairing(cacaoAddress: cacao, assetAddress: asset), .pairable)
    }

    func testAPendingHalfFromOtherAddressesIsAMismatch() {
        let pending = record(cacaoAddress: cacao, assetAddress: "0xother", pendingTxId: "ABC")
        XCTAssertEqual(pending.pairing(cacaoAddress: cacao, assetAddress: asset), .addressMismatch)
    }

    func testALivePositionWithNoAssetAddressIsSingleSided() {
        let live = record(units: "500", cacaoAddress: cacao)
        XCTAssertEqual(live.pairing(cacaoAddress: cacao, assetAddress: asset), .singleSidedPosition)
        let blank = record(units: "500", cacaoAddress: cacao, assetAddress: "")
        XCTAssertEqual(blank.pairing(cacaoAddress: cacao, assetAddress: asset), .singleSidedPosition)
    }

    func testALivePositionKeepsItsAssetAddress() {
        let live = record(units: "500", cacaoAddress: cacao, assetAddress: asset.lowercased())
        XCTAssertEqual(live.pairing(cacaoAddress: cacao, assetAddress: asset), .pairable)
        XCTAssertEqual(live.pairing(cacaoAddress: cacao, assetAddress: "0xother"), .addressMismatch)
    }

    func testTheRecordDecodesMayanodesShape() throws {
        let json = """
        {"asset":"ETH.ETH","cacao_address":"maya1vault","asset_address":"0xabc","units":"0",
         "pending_cacao":"0","pending_asset":"100000","pending_tx_id":"TX","last_add_height":123}
        """
        let decoded = try JSONDecoder().decode(MayaLiquidityProvider.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.pendingAsset, "100000")
        XCTAssertEqual(decoded.pendingTxId, "TX")
        XCTAssertEqual(decoded.lastAddHeight, 123)
    }

    func testARecordWithoutAUsableUnitsFieldFailsTheRead() {
        for json in [#"{"asset":"ETH.ETH"}"#, #"{"asset":"ETH.ETH","units":"abc"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MayaLiquidityProvider.self, from: Data(json.utf8)), json)
        }
    }

    func testAMissingRecordReadsAsNil() async throws {
        let service = MayaChainAPIService(httpClient: StubLPHTTPClient(status: 404, body: "{}"))
        let found = try await service.getLiquidityProvider(pool: "ETH.ETH", address: cacao)
        XCTAssertNil(found)
    }

    func testAFailedReadThrowsRatherThanReadingAsMissing() async {
        let service = MayaChainAPIService(httpClient: StubLPHTTPClient(status: 500, body: "{}"))
        do {
            _ = try await service.getLiquidityProvider(pool: "ETH.ETH", address: cacao)
            XCTFail("a server error must not read as an empty record")
        } catch {}
    }

    func testTheRecordIsReadFromMayanodeNotMidgard() async throws {
        let stub = StubLPHTTPClient(status: 200, body: """
        {"asset":"ETH.ETH","units":"0"}
        """)
        let service = MayaChainAPIService(httpClient: stub)
        _ = try await service.getLiquidityProvider(pool: "ETH.ETH", address: cacao)
        XCTAssertEqual(stub.lastTarget?.baseURL.host, "mayanode.mayachain.info")
        XCTAssertEqual(stub.lastTarget?.path, "/mayachain/pool/ETH.ETH/liquidity_provider/\(cacao)")
    }
}

final class StubLPHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    let status: Int
    let body: String
    private(set) var lastTarget: TargetType?

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        lastTarget = target
        guard (200..<300).contains(status) else { throw HTTPError.statusCode(status, Data(body.utf8)) }
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw HTTPError.statusCode(500, Data())
    }
}
