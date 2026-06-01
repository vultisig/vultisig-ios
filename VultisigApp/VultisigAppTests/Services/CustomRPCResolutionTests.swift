//
//  CustomRPCResolutionTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

/// A fake `RPCEndpointResolving` that returns a fixed override per chain. Lets
/// the resolution layer be exercised without touching `CustomRPCStore.shared`
/// or SwiftData.
private struct FakeRPCResolver: RPCEndpointResolving {
    var overrides: [Chain: String] = [:]
    func url(for chain: Chain) -> String? { overrides[chain] }
}

final class CustomRPCResolutionTests: XCTestCase {

    private let noOverride = FakeRPCResolver()

    // MARK: - EVM (single resolution point: EvmServiceConfig.getConfig)

    func test_evmConfig_returnsDefault_whenNoOverride() throws {
        let config = try EvmServiceConfig.getConfig(forChain: .ethereum, resolver: noOverride)
        XCTAssertEqual(config.rpcEndpoint, Endpoint.ethServiceRpcService)
    }

    func test_evmConfig_returnsOverride_whenSet() throws {
        let resolver = FakeRPCResolver(overrides: [.ethereum: "https://my-eth-node.example/rpc"])
        let config = try EvmServiceConfig.getConfig(forChain: .ethereum, resolver: resolver)
        XCTAssertEqual(config.rpcEndpoint, "https://my-eth-node.example/rpc")
    }

    func test_evmConfig_overrideForOneChain_doesNotLeakToAnother() throws {
        let resolver = FakeRPCResolver(overrides: [.ethereum: "https://my-eth-node.example/rpc"])
        let config = try EvmServiceConfig.getConfig(forChain: .base, resolver: resolver)
        XCTAssertEqual(config.rpcEndpoint, Endpoint.baseServiceRpcService)
    }

    // MARK: - Cosmos (TargetType stays pure; config resolves)

    func test_cosmosBaseURL_returnsDefault_whenNoOverride() {
        let config = CosmosServiceConfig(chain: .gaiaChain, resolver: noOverride)
        XCTAssertEqual(config.baseURL?.absoluteString, "https://cosmos-rest.publicnode.com")
        XCTAssertNil(config.overrideURL)
    }

    func test_cosmosBaseURL_returnsOverride_whenSet() {
        let resolver = FakeRPCResolver(overrides: [.gaiaChain: "https://my-cosmos-node.example"])
        let config = CosmosServiceConfig(chain: .gaiaChain, resolver: resolver)
        XCTAssertEqual(config.baseURL?.absoluteString, "https://my-cosmos-node.example")
    }

    func test_cosmosAPI_builtWithBaseURL_yieldsExpectedRequestURL() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://my-cosmos-node.example"))
        let api = CosmosAPI(baseURL: baseURL, endpoint: .balance(address: "cosmos1abc"))
        XCTAssertEqual(api.baseURL.absoluteString, "https://my-cosmos-node.example")
        XCTAssertEqual(api.path, "/cosmos/bank/v1beta1/balances/cosmos1abc")
    }

    // MARK: - Solana (baseURL + path resolved together, can't disagree)

    func test_solanaAPI_default_usesProxyHostAndPath() {
        let api = SolanaAPI(baseURL: SolanaAPI.rpcBaseURL, usesProxyPath: true, rpcMethod: .getBalance(address: "addr"))
        XCTAssertEqual(api.baseURL, SolanaAPI.rpcBaseURL)
        XCTAssertEqual(api.path, SolanaAPI.proxyPath)
    }

    func test_solanaAPI_override_dropsProxyPath() throws {
        let override = try XCTUnwrap(URL(string: "https://my-solana-node.example/rpc"))
        let api = SolanaAPI(baseURL: override, usesProxyPath: false, rpcMethod: .getBalance(address: "addr"))
        XCTAssertEqual(api.baseURL.absoluteString, "https://my-solana-node.example/rpc")
        XCTAssertEqual(api.path, "")
    }

    // MARK: - THORChain (LCD/RPC hosts injected; Midgard/GraphQL stay default)

    func test_thorchainMainnet_default_lcdAndRpcHosts() {
        let lcd = ThorchainMainnetAPI(.balances(address: "thor1abc"))
        XCTAssertEqual(lcd.baseURL, ThorchainMainnetAPI.defaultLCDHost)
        XCTAssertEqual(lcd.path, "/cosmos/bank/v1beta1/balances/thor1abc")

        let rpc = ThorchainMainnetAPI(.networkStatus)
        XCTAssertEqual(rpc.baseURL, ThorchainMainnetAPI.defaultRPCHost)
        XCTAssertEqual(rpc.path, "/status")
    }

    func test_thorchainMainnet_override_appliesToLcdAndRpcOnly() throws {
        let host = try XCTUnwrap(URL(string: "https://my-thor-node.example"))

        let lcd = ThorchainMainnetAPI(.balances(address: "thor1abc"), lcdHost: host, rpcHost: host)
        XCTAssertEqual(lcd.baseURL, host)

        let rpc = ThorchainMainnetAPI(.networkStatus, lcdHost: host, rpcHost: host)
        XCTAssertEqual(rpc.baseURL, host)

        // Midgard (TNS) and the Vultisig GraphQL proxy have no single-chain
        // identity and keep their defaults regardless of the injected host.
        let tns = ThorchainMainnetAPI(.resolveTNS(name: "vitalik", chain: .thorChain), lcdHost: host, rpcHost: host)
        XCTAssertEqual(tns.baseURL.absoluteString, "https://gateway.liquify.com/chain/thorchain_midgard")

        let graphql = ThorchainMainnetAPI(.rujiGraphQL(query: "{}"), lcdHost: host, rpcHost: host)
        XCTAssertEqual(graphql.baseURL.absoluteString, "https://api.vultisig.com")
    }

    func test_thorchainBroadcast_default_usesLcdHost() {
        let api = ThorchainBroadcastAPI(body: Data())
        XCTAssertEqual(api.baseURL, ThorchainMainnetAPI.defaultLCDHost)
        XCTAssertEqual(api.path, "/cosmos/tx/v1beta1/txs")
    }

    func test_thorchainBroadcast_override_usesInjectedLcdHost() throws {
        let host = try XCTUnwrap(URL(string: "https://my-thor-node.example"))
        let api = ThorchainBroadcastAPI(body: Data(), lcdHost: host)
        XCTAssertEqual(api.baseURL, host)
    }

    // MARK: - Default == previous-default (behavior identical with no override)

    func test_defaults_matchHardcodedHosts() throws {
        // EVM
        XCTAssertEqual(
            try EvmServiceConfig.getConfig(forChain: .base, resolver: noOverride).rpcEndpoint,
            Endpoint.baseServiceRpcService
        )
        // Cosmos
        XCTAssertEqual(
            CosmosServiceConfig(chain: .osmosis, resolver: noOverride).baseURL?.absoluteString,
            "https://osmosis-rest.publicnode.com"
        )
        // Solana
        XCTAssertEqual(SolanaAPI.rpcBaseURL.absoluteString, "https://api.vultisig.com")
        XCTAssertEqual(SolanaAPI.proxyPath, "/solana/")
        // THORChain
        XCTAssertEqual(
            ThorchainMainnetAPI.defaultLCDHost.absoluteString,
            "https://gateway.liquify.com/chain/thorchain_api"
        )
        XCTAssertEqual(
            ThorchainMainnetAPI.defaultRPCHost.absoluteString,
            "https://gateway.liquify.com/chain/thorchain_rpc"
        )
    }
}
