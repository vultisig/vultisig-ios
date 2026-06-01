//
//  CustomRPCResolutionTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class CustomRPCResolutionTests: XCTestCase {

    private var token: TestContextToken?
    private let store = CustomRPCStore.shared

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
        store.reloadFromStore()
        store.reset(.ethereum)
        store.reset(.gaiaChain)
    }

    override func tearDown() async throws {
        store.reset(.ethereum)
        store.reset(.gaiaChain)
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    // MARK: - EVM

    func test_evmConfig_returnsDefault_whenNoOverride() throws {
        let config = try EvmServiceConfig.getConfig(forChain: .ethereum)
        XCTAssertEqual(config.rpcEndpoint, Endpoint.ethServiceRpcService)
    }

    func test_evmConfig_returnsOverride_whenSet() throws {
        store.set("https://my-eth-node.example/rpc", for: .ethereum)
        let config = try EvmServiceConfig.getConfig(forChain: .ethereum)
        XCTAssertEqual(config.rpcEndpoint, "https://my-eth-node.example/rpc")
    }

    func test_evmService_rpcEndpoint_returnsOverride_whenSet() throws {
        store.set("https://my-eth-node.example/rpc", for: .ethereum)
        let service = try EvmService.getService(forChain: .ethereum)
        XCTAssertEqual(service.rpcEndpoint, "https://my-eth-node.example/rpc")
    }

    // MARK: - Cosmos

    func test_cosmosBaseURL_returnsDefault_whenNoOverride() {
        let config = CosmosServiceConfig(chain: .gaiaChain)
        XCTAssertEqual(config.baseURL?.absoluteString, "https://cosmos-rest.publicnode.com")
    }

    func test_cosmosBaseURL_returnsOverride_whenSet() {
        store.set("https://my-cosmos-node.example", for: .gaiaChain)
        let config = CosmosServiceConfig(chain: .gaiaChain)
        XCTAssertEqual(config.baseURL?.absoluteString, "https://my-cosmos-node.example")
    }
}
