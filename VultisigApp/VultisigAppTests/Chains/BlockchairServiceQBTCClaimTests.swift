//
//  BlockchairServiceQBTCClaimTests.swift
//  VultisigAppTests
//
//  Covers `BlockchairService.fetchQBTCClaimableUtxos`: the happy path
//  (UTXO adaptation + chain-tip extraction) and the missing-address
//  error path that must NOT collapse a fetch failure into an empty set.
//

@testable import VultisigApp
import XCTest

final class BlockchairServiceQBTCClaimTests: XCTestCase {

    private static let address = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
    private static let txid = String(repeating: "a", count: 64)

    private func makeBtcCoinMeta() -> CoinMeta {
        CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "BitcoinLogo",
            decimals: 8,
            priceProviderId: "Bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
    }

    // MARK: - Happy path

    func testFetchAdaptsUtxosAndReadsTip() async throws {
        let body = """
        {
          "data": {
            "\(Self.address)": {
              "utxo": [
                {
                  "block_id": 952734,
                  "transaction_hash": "\(Self.txid)",
                  "index": 0,
                  "value": 50000
                }
              ]
            }
          },
          "context": { "state": 952877 }
        }
        """
        let service = BlockchairService(httpClient: StubJSONHTTPClient(body: body))

        let result = try await service.fetchQBTCClaimableUtxos(
            bitcoinCoin: makeBtcCoinMeta(),
            address: Self.address
        )

        XCTAssertEqual(result.btcTipHeight, 952_877)
        XCTAssertEqual(result.utxos.count, 1)
        let utxo = try XCTUnwrap(result.utxos.first)
        XCTAssertEqual(utxo.txid, Self.txid)
        XCTAssertEqual(utxo.vout, 0)
        XCTAssertEqual(utxo.amount, 50_000)
        XCTAssertEqual(utxo.blockHeight, 952_734)
    }

    // MARK: - Missing chain tip ⇒ nil height, UTXOs still returned

    /// When Blockchair omits `context` (or `context.state`), the tip is
    /// unknown: `btcTipHeight` must be `nil` while the UTXOs still come
    /// through. The downstream confirmation gate then fails open — see
    /// `QBTCChainService.filterSufficientlyConfirmed`.
    func testFetchReturnsNilTipWhenContextMissing() async throws {
        let body = """
        {
          "data": {
            "\(Self.address)": {
              "utxo": [
                {
                  "block_id": 952734,
                  "transaction_hash": "\(Self.txid)",
                  "index": 0,
                  "value": 50000
                }
              ]
            }
          }
        }
        """
        let service = BlockchairService(httpClient: StubJSONHTTPClient(body: body))

        let result = try await service.fetchQBTCClaimableUtxos(
            bitcoinCoin: makeBtcCoinMeta(),
            address: Self.address
        )

        XCTAssertNil(result.btcTipHeight)
        XCTAssertEqual(result.utxos.count, 1)
        let utxo = try XCTUnwrap(result.utxos.first)
        XCTAssertEqual(utxo.txid, Self.txid)
        XCTAssertEqual(utxo.amount, 50_000)
    }

    // MARK: - Missing address ⇒ throw (don't mask as empty set)

    /// A response whose `data` map lacks the requested address key is a
    /// fetch/normalization failure, not "zero UTXOs". The method must throw
    /// `QBTCClaimableUtxosError.missingAddressData` so the claim flow can
    /// fail-closed instead of telling the user there's nothing to claim.
    func testFetchThrowsWhenAddressKeyMissing() async {
        // Well-formed response, but keyed by a *different* address.
        let body = """
        {
          "data": {
            "bc1qsomeotheraddressxxxxxxxxxxxxxxxxxxxxxxx": { "utxo": [] }
          },
          "context": { "state": 952877 }
        }
        """
        let service = BlockchairService(httpClient: StubJSONHTTPClient(body: body))

        do {
            _ = try await service.fetchQBTCClaimableUtxos(
                bitcoinCoin: makeBtcCoinMeta(),
                address: Self.address
            )
            XCTFail("expected missingAddressData throw, got a result")
        } catch let error as QBTCClaimableUtxosError {
            guard case .missingAddressData(let addr) = error else {
                return XCTFail("expected .missingAddressData, got \(error)")
            }
            XCTAssertEqual(addr, Self.address)
        } catch {
            XCTFail("expected QBTCClaimableUtxosError.missingAddressData, got \(error)")
        }
    }
}

// MARK: - Test double

/// Returns a fixed 200 JSON body for any request. `BlockchairService`
/// decodes it via the `HTTPClientProtocol` default `request(_:responseType:)`.
private final class StubJSONHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let body: String

    init(body: String) {
        self.body = body
    }

    // swiftlint:disable:next async_without_await unused_parameter
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://example.test")!
        // swiftlint:disable:next force_unwrapping
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }
}
