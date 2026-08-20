//
//  THORChainWasmStakingAvailabilityTests.swift
//  VultisigAppTests
//

import Foundation
@testable import VultisigApp
import XCTest

final class THORChainWasmStakingAvailabilityTests: XCTestCase {
    private let contractAddress = "thor1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqabcdef"
    private let dataHash = "9F3A872C75AB4413DD37936F720B81A051062B1B96554C9CB46C7CCDB4FD017E"
    private let checksumReference = "T45IOLDVVNCBHXJXSNXXEC4BUBIQMKY3SZKUZHFUNR6M3NH5AF7A"

    func testHaltHeightStartsAfterConfiguredBlock() {
        XCTAssertFalse(ThorchainService.isWasmHaltActive(-1, at: 100))
        XCTAssertFalse(ThorchainService.isWasmHaltActive(0, at: 100))
        XCTAssertFalse(ThorchainService.isWasmHaltActive(100, at: 100))
        XCTAssertFalse(ThorchainService.isWasmHaltActive(101, at: 100))
        XCTAssertTrue(ThorchainService.isWasmHaltActive(100, at: 101))
    }

    func testChecksumKeyUsesThornodeBase32WithoutPadding() {
        XCTAssertEqual(ThorchainService.base32MimirReference(Data("foo".utf8)), "MZXW6")
        XCTAssertEqual(
            ThorchainService.wasmChecksumHaltMimirKey(dataHash: dataHash),
            "HaltWasmCs-\(checksumReference)"
        )
        XCTAssertNil(ThorchainService.wasmChecksumHaltMimirKey(dataHash: "not-hex"))
    }

    func testContractKeyUsesLastSixAddressCharacters() {
        XCTAssertEqual(
            ThorchainService.wasmContractHaltMimirKey(address: contractAddress),
            "HaltWasmContract-abcdef"
        )
        XCTAssertNil(ThorchainService.wasmContractHaltMimirKey(address: "short"))
    }

    func testChecksumHaltDisablesContractAfterConfiguredHeight() async {
        let client = makeClient(currentHeight: 101, global: -1, contract: -1, checksum: 100)
        let service = ThorchainService(resolver: NoTHORChainRPCOverride(), httpClient: client)

        let availability = await service.fetchWasmExecutionAvailabilities(for: [contractAddress])

        XCTAssertEqual(availability[contractAddress], .halted)
    }

    func testChecksumHaltDoesNotStartAtConfiguredHeight() async {
        let client = makeClient(currentHeight: 100, global: -1, contract: -1, checksum: 100)
        let service = ThorchainService(resolver: NoTHORChainRPCOverride(), httpClient: client)

        let availability = await service.fetchWasmExecutionAvailabilities(for: [contractAddress])

        XCTAssertEqual(availability[contractAddress], .available)
    }

    func testContractHaltDisablesContractAfterConfiguredHeight() async {
        let client = makeClient(currentHeight: 101, global: -1, contract: 100, checksum: -1)
        let service = ThorchainService(resolver: NoTHORChainRPCOverride(), httpClient: client)

        let availability = await service.fetchWasmExecutionAvailabilities(for: [contractAddress])

        XCTAssertEqual(availability[contractAddress], .halted)
    }

    func testGlobalHaltDisablesWithoutContractMetadataRequests() async {
        let client = THORChainWasmAvailabilityHTTPClient(
            responses: [
                "/thorchain/lastblock": [lastBlockJSON(height: 101)],
                "/thorchain/mimir/key/HALTWASMGLOBAL": [Data("100".utf8)]
            ]
        )
        let service = ThorchainService(resolver: NoTHORChainRPCOverride(), httpClient: client)

        let availability = await service.fetchWasmExecutionAvailabilities(for: [contractAddress])
        let contractInfoRequests = await client.requestCount(for: "/cosmwasm/wasm/v1/contract/\(contractAddress)")

        XCTAssertEqual(availability[contractAddress], .halted)
        XCTAssertEqual(contractInfoRequests, 0)
    }

    func testMetadataFailureFailsOnlyThatContractClosed() async {
        let client = THORChainWasmAvailabilityHTTPClient(
            responses: [
                "/thorchain/lastblock": [lastBlockJSON(height: 101)],
                "/thorchain/mimir/key/HALTWASMGLOBAL": [Data("-1".utf8)],
                "/thorchain/mimir/key/HALTWASMCONTRACT-ABCDEF": [Data("-1".utf8)]
            ]
        )
        let service = ThorchainService(resolver: NoTHORChainRPCOverride(), httpClient: client)

        let availability = await service.fetchWasmExecutionAvailabilities(for: [contractAddress])

        XCTAssertEqual(availability[contractAddress], .unavailable)
    }

    func testInteractorGatesRujiWithoutDisablingNativeTcy() async {
        let ruji = TokensStore.ruji
        let tcy = TokensStore.tcy
        let provider = StubWasmAvailabilityProvider(
            availabilities: [RUJIStakingConstants.contract: .halted]
        )
        let interactor = THORChainStakeInteractor(wasmAvailabilityProvider: provider)

        let availability = await interactor.fetchActionAvailabilities(for: [ruji, tcy])

        XCTAssertEqual(availability[ruji], .halted)
        XCTAssertEqual(availability[tcy], .available)
    }

    func testInteractorFailsRujiClosedWhenProviderOmitsContract() async {
        let provider = StubWasmAvailabilityProvider(availabilities: [:])
        let interactor = THORChainStakeInteractor(wasmAvailabilityProvider: provider)

        let availability = await interactor.fetchActionAvailabilities(for: [TokensStore.ruji])

        XCTAssertEqual(availability[TokensStore.ruji], .unavailable)
    }

    private func makeClient(
        currentHeight: UInt64,
        global: Int64,
        contract: Int64,
        checksum: Int64
    ) -> THORChainWasmAvailabilityHTTPClient {
        THORChainWasmAvailabilityHTTPClient(
            responses: [
                "/thorchain/lastblock": [lastBlockJSON(height: currentHeight)],
                "/thorchain/mimir/key/HALTWASMGLOBAL": [Data(String(global).utf8)],
                "/thorchain/mimir/key/HALTWASMCONTRACT-ABCDEF": [Data(String(contract).utf8)],
                "/cosmwasm/wasm/v1/contract/\(contractAddress)": [contractInfoJSON(codeID: "43")],
                "/cosmwasm/wasm/v1/code/43": [codeInfoJSON(dataHash: dataHash)],
                "/thorchain/mimir/key/HALTWASMCS-\(checksumReference)": [Data(String(checksum).utf8)]
            ]
        )
    }

    private func lastBlockJSON(height: UInt64) -> Data {
        Data("[{\"thorchain\":\(height)}]".utf8)
    }

    private func contractInfoJSON(codeID: String) -> Data {
        Data("{\"contract_info\":{\"code_id\":\"\(codeID)\"}}".utf8)
    }

    private func codeInfoJSON(dataHash: String) -> Data {
        Data("{\"code_info\":{\"data_hash\":\"\(dataHash)\"}}".utf8)
    }
}

private struct NoTHORChainRPCOverride: RPCEndpointResolving {
    func url(for _: Chain) -> String? { nil }
}

private struct StubWasmAvailabilityProvider: THORChainWasmExecutionAvailabilityProviding {
    let availabilities: [String: THORChainWasmExecutionAvailability]

    // swiftlint:disable async_without_await
    func fetchWasmExecutionAvailabilities(
        for contractAddresses: Set<String>
    ) async -> [String: THORChainWasmExecutionAvailability] {
        availabilities.filter { contractAddresses.contains($0.key) }
    }
    // swiftlint:enable async_without_await
}

private actor THORChainWasmAvailabilityHTTPClient: HTTPClientProtocol {
    private var responses: [String: [Data]]
    private var counts: [String: Int] = [:]

    init(responses: [String: [Data]]) {
        self.responses = responses
    }

    func requestCount(for path: String) -> Int {
        counts[path, default: 0]
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        let path = target.path
        counts[path, default: 0] += 1
        guard var queued = responses[path], !queued.isEmpty else {
            throw HTTPError.statusCode(501, nil)
        }
        let data = queued.removeFirst()
        responses[path] = queued
        let response = HTTPURLResponse(
            url: target.baseURL.appendingPathComponent(path),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: data, response: response)
    }
}
