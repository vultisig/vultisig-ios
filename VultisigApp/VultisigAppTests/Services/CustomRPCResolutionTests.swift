//
//  CustomRPCResolutionTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
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

    // MARK: - resolvedURL(for:default:) extension (override + parse helper)

    func test_resolvedURL_validOverride_returnsParsedURL() throws {
        let defaultURL = try XCTUnwrap(URL(string: "https://default.example"))
        let resolver = FakeRPCResolver(overrides: [.ethereum: "https://my-node.example/rpc"])
        XCTAssertEqual(
            resolver.resolvedURL(for: .ethereum, default: defaultURL).absoluteString,
            "https://my-node.example/rpc"
        )
    }

    func test_resolvedURL_noOverride_returnsDefault() throws {
        let defaultURL = try XCTUnwrap(URL(string: "https://default.example"))
        XCTAssertEqual(noOverride.resolvedURL(for: .ethereum, default: defaultURL), defaultURL)
    }

    func test_resolvedURL_malformedOverride_returnsDefault() throws {
        let defaultURL = try XCTUnwrap(URL(string: "https://default.example"))
        // A non-empty but unparseable override string must fall back to the
        // default rather than producing a broken URL.
        let resolver = FakeRPCResolver(overrides: [.ethereum: "ht tp://not a url"])
        XCTAssertEqual(resolver.resolvedURL(for: .ethereum, default: defaultURL), defaultURL)
    }

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

    func test_thorchainMainnet_feeAndInbound_default_matchLegacyNineRealmsURLs() {
        // fetchFeePrice() / fetchThorchainInboundAddress() route through
        // mainnet(.networkInfo) / mainnet(.inboundAddresses) so the override
        // applies. With no override the resolved URL must stay byte-identical
        // to the legacy NineRealms endpoints they previously hit.
        let networkInfo = ThorchainMainnetAPI(.networkInfo)
        XCTAssertEqual(networkInfo.baseURL, ThorchainMainnetAPI.defaultLCDHost)
        XCTAssertEqual(
            networkInfo.baseURL.appendingPathComponent(networkInfo.path).absoluteString,
            "https://gateway.liquify.com/chain/thorchain_api/thorchain/network"
        )

        let inbound = ThorchainMainnetAPI(.inboundAddresses)
        XCTAssertEqual(inbound.baseURL, ThorchainMainnetAPI.defaultLCDHost)
        XCTAssertEqual(
            inbound.baseURL.appendingPathComponent(inbound.path).absoluteString,
            "https://gateway.liquify.com/chain/thorchain_api/thorchain/inbound_addresses"
        )
    }

    func test_thorchainMainnet_feeAndInbound_override_appliesInjectedHost() throws {
        let host = try XCTUnwrap(URL(string: "https://my-thor-node.example"))
        let networkInfo = ThorchainMainnetAPI(.networkInfo, lcdHost: host, rpcHost: host)
        XCTAssertEqual(networkInfo.baseURL, host)
        let inbound = ThorchainMainnetAPI(.inboundAddresses, lcdHost: host, rpcHost: host)
        XCTAssertEqual(inbound.baseURL, host)
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

    // MARK: - MayaChain (Mayanode host injected; Midgard stays default)

    func test_mayaChainAPI_default_usesMayanodeHost() {
        let api = MayaChainAPI(.balances(address: "maya1abc"))
        XCTAssertEqual(api.baseURL, MayaChainAPI.defaultHost)
        XCTAssertEqual(api.baseURL.absoluteString, "https://mayanode.mayachain.info")
        XCTAssertEqual(api.path, "/cosmos/bank/v1beta1/balances/maya1abc")
    }

    func test_mayaChainAPI_override_usesInjectedHost() throws {
        let host = try XCTUnwrap(URL(string: "https://my-maya-node.example"))
        let api = MayaChainAPI(.broadcast(body: Data()), host: host)
        XCTAssertEqual(api.baseURL, host)
        XCTAssertEqual(api.path, "/cosmos/tx/v1beta1/txs")
    }

    // MARK: - Ripple (XRPL host injected; path-agnostic JSON-RPC)

    func test_rippleAPI_default_usesXrplHost() {
        let api = RippleAPI(.serverState)
        XCTAssertEqual(api.baseURL, RippleAPI.defaultHost)
        XCTAssertEqual(api.baseURL.absoluteString, "https://xrplcluster.com")
        XCTAssertEqual(api.path, "/")
    }

    func test_rippleAPI_override_usesInjectedHost() throws {
        let host = try XCTUnwrap(URL(string: "https://my-xrpl-node.example"))
        let api = RippleAPI(.submit(txBlob: "deadbeef"), host: host)
        XCTAssertEqual(api.baseURL, host)
        XCTAssertEqual(api.path, "/")
    }

    // MARK: - Tron (proxy default; override swaps host, keeps /wallet/* paths)

    func test_tronAPI_default_usesProxyHostAndWalletPaths() {
        let api = TronAPI(.getNowBlock)
        XCTAssertEqual(api.baseURL, TronAPI.defaultHost)
        XCTAssertEqual(api.baseURL.absoluteString, "https://api.vultisig.com/tron-rest")
        XCTAssertEqual(api.path, "/wallet/getnowblock")
    }

    func test_tronAPI_override_swapsHostKeepsPath() throws {
        let host = try XCTUnwrap(URL(string: "https://my-trongrid.example"))
        let api = TronAPI(.broadcastTransaction(jsonString: "{}"), host: host)
        XCTAssertEqual(api.baseURL, host)
        XCTAssertEqual(api.path, "/wallet/broadcasttransaction")
    }

    func test_tronEvmRpc_ignoresTronOverride_keepsProxy() throws {
        // The `.tron` override is a TronGrid REST endpoint, NOT an EVM JSON-RPC
        // node, so the EVM-side tron-rpc host must stay on the proxy default.
        let resolver = FakeRPCResolver(overrides: [.tron: "https://my-trongrid.example"])
        let config = try EvmServiceConfig.getConfig(forChain: .tron, resolver: resolver)
        XCTAssertEqual(config.rpcEndpoint, Endpoint.tronEvmServiceRpc)
    }

    // MARK: - Ton (proxy default; override swaps host, keeps /ton/v2|v3 paths)

    func test_tonAPI_default_usesProxyHostAndVersionedPaths() {
        let v3 = TonAPI(.addressInformation(address: "EQabc"))
        XCTAssertEqual(v3.baseURL, TonAPI.defaultHost)
        XCTAssertEqual(v3.baseURL.absoluteString, "https://api.vultisig.com")
        XCTAssertEqual(v3.path, "/ton/v3/addressInformation")

        let v2 = TonAPI(.broadcastTransaction(boc: "boc"))
        XCTAssertEqual(v2.path, "/ton/v2/sendBocReturnHash")
    }

    func test_tonAPI_override_swapsHostKeepsVersionedPaths() throws {
        let host = try XCTUnwrap(URL(string: "https://my-toncenter.example"))
        let v3 = TonAPI(.jettonMasters(jettonAddress: "EQmaster"), host: host)
        XCTAssertEqual(v3.baseURL, host)
        XCTAssertEqual(v3.path, "/ton/v3/jetton/masters")

        let v2 = TonAPI(.runGetMethod(address: "EQa", method: "m", stack: []), host: host)
        XCTAssertEqual(v2.baseURL, host)
        XCTAssertEqual(v2.path, "/ton/v2/runGetMethod")
    }

    // MARK: - No cross-chain leak

    func test_override_doesNotLeakAcrossChains() throws {
        let resolver = FakeRPCResolver(overrides: [.ethereum: "https://eth-only.example"])
        // EVM sibling unaffected
        XCTAssertEqual(
            try EvmServiceConfig.getConfig(forChain: .base, resolver: resolver).rpcEndpoint,
            Endpoint.baseServiceRpcService
        )
        // Non-EVM chains resolve their own keys, so an EVM override is invisible.
        XCTAssertNil(resolver.url(for: .tron))
        XCTAssertNil(resolver.url(for: .ton))
        XCTAssertNil(resolver.url(for: .ripple))
        XCTAssertNil(resolver.url(for: .sui))
        XCTAssertNil(resolver.url(for: .mayaChain))
        XCTAssertNil(resolver.url(for: .polkadot))
        XCTAssertNil(resolver.url(for: .bittensor))
    }

    // MARK: - Default == previous-default (behavior identical with no override)

    func test_defaults_matchHardcodedHosts() throws {
        // EVM
        XCTAssertEqual(
            try EvmServiceConfig.getConfig(forChain: .base, resolver: noOverride).rpcEndpoint,
            Endpoint.baseServiceRpcService
        )
        // EVM variants newly exposed in the picker
        XCTAssertEqual(
            try EvmServiceConfig.getConfig(forChain: .ethereumSepolia, resolver: noOverride).rpcEndpoint,
            Endpoint.ethSepoliaServiceRpcService
        )
        XCTAssertEqual(
            try EvmServiceConfig.getConfig(forChain: .polygon, resolver: noOverride).rpcEndpoint,
            Endpoint.polygonServiceRpcService
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
        // MayaChain
        XCTAssertEqual(MayaChainAPI.defaultHost.absoluteString, "https://mayanode.mayachain.info")
        // Ripple
        XCTAssertEqual(RippleAPI.defaultHost.absoluteString, "https://xrplcluster.com")
        // Sui
        XCTAssertEqual(SuiService.defaultRPCURL.absoluteString, "https://sui-rpc.publicnode.com")
        XCTAssertEqual(Endpoint.suiServiceRpc, "https://sui-rpc.publicnode.com")
        // Bittensor (proxy/onfinality default baked at init)
        XCTAssertEqual(BittensorService.rpcEndpoint, "https://bittensor-finney.api.onfinality.io/public")
        XCTAssertEqual(Endpoint.bittensorServiceRpc, "https://bittensor-finney.api.onfinality.io/public")
        // Tron REST proxy default + EVM-rpc proxy default
        XCTAssertEqual(TronAPI.defaultHost.absoluteString, "https://api.vultisig.com/tron-rest")
        XCTAssertEqual(Endpoint.tronEvmServiceRpc, "https://api.vultisig.com/tron-rpc")
        // Ton proxy default
        XCTAssertEqual(TonAPI.defaultHost.absoluteString, "https://api.vultisig.com")
        // Polkadot proxy default baked at init
        XCTAssertEqual(PolkadotService.rpcEndpoint, "https://api.vultisig.com/dot/")
        XCTAssertEqual(Endpoint.polkadotServiceRpc, "https://api.vultisig.com/dot/")
    }
}

/// EVM funnel tests that exercise the real `CustomRPCStore` so Polygon aliasing
/// (`.polygon` / `.polygonV2` sharing one override slot) is observable — the
/// pure `FakeRPCResolver` keys verbatim and cannot reproduce the normalizer.
@MainActor
final class CustomRPCPolygonFunnelTests: XCTestCase {

    private var token: TestContextToken?
    private let store = CustomRPCStore.shared

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
        store.reloadFromStore()
        store.reset(.polygon)
    }

    override func tearDown() async throws {
        store.reset(.polygon)
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func test_evmConfig_polygonOverride_appliesToPolygonV2() throws {
        store.set("https://my-polygon-node.example/rpc", for: .polygon)
        let config = try EvmServiceConfig.getConfig(forChain: .polygonV2, resolver: store)
        XCTAssertEqual(config.rpcEndpoint, "https://my-polygon-node.example/rpc")
    }

    func test_evmConfig_polygonV2Override_appliesToPolygon() throws {
        store.set("https://my-polygon-node.example/rpc", for: .polygonV2)
        let config = try EvmServiceConfig.getConfig(forChain: .polygon, resolver: store)
        XCTAssertEqual(config.rpcEndpoint, "https://my-polygon-node.example/rpc")
    }

    func test_evmConfig_polygon_noOverride_returnsDefaultForBothCases() throws {
        XCTAssertEqual(
            try EvmServiceConfig.getConfig(forChain: .polygon, resolver: store).rpcEndpoint,
            Endpoint.polygonServiceRpcService
        )
        XCTAssertEqual(
            try EvmServiceConfig.getConfig(forChain: .polygonV2, resolver: store).rpcEndpoint,
            Endpoint.polygonServiceRpcService
        )
    }
}
