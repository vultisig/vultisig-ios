//
//  SuiAPI.swift
//  VultisigApp
//

import Foundation

/// Pure `TargetType` for the Sui RPC endpoint consumed by `SuiService` and the
/// Sui transaction-status poller. The host is baked in at construction by the
/// caller (see `SuiEndpointResolver`); this value never consults global state.
/// Sui exposes a single RPC endpoint that every method posts to directly, so the
/// host is the complete URL and the path is always empty.
struct SuiAPI: TargetType {
    enum Endpoint {
        case coinMetadata(coinType: String)
        case allBalances(address: String)
        case allCoins(address: String, cursor: String?)
        case referenceGasPrice
        /// Broadcast. `txBytes` and `signature` are the base64 strings produced
        /// by the signing path and are forwarded verbatim — the transport never
        /// re-encodes signed material.
        case executeTransactionBlock(txBytes: String, signature: String)
        case dryRunTransactionBlock(txBytes: String)
    }

    /// Primary Sui RPC host.
    static let defaultHost = URL(staticString: "https://sui-rpc.publicnode.com")

    /// Hosts attempted in order when the user has not configured a custom RPC.
    ///
    /// Both entries are already trusted with Vultisig traffic: the primary is the
    /// host Sui has always used here, and the fallback is Vultisig's own proxy,
    /// which the app already routes every EVM chain and Polkadot through — so the
    /// fallback introduces no new operator and no new privacy surface.
    static let defaultHosts: [URL] = [
        defaultHost,
        URL(staticString: "https://api.vultisig.com/sui/")
    ]

    let baseURL: URL
    let endpoint: Endpoint

    init(baseURL: URL = SuiAPI.defaultHost, endpoint: Endpoint) {
        self.baseURL = baseURL
        self.endpoint = endpoint
    }

    var path: String { "" }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        .requestParameters(Self.body(for: endpoint), .jsonEncoding)
    }

    private static func body(for endpoint: Endpoint) -> [String: Any] {
        switch endpoint {
        case .coinMetadata(let coinType):
            return envelope(method: "suix_getCoinMetadata", params: [coinType])
        case .allBalances(let address):
            return envelope(method: "suix_getAllBalances", params: [address])
        case .allCoins(let address, let cursor):
            return envelope(method: "suix_getAllCoins", params: [address, cursor ?? NSNull()])
        case .referenceGasPrice:
            return envelope(method: "suix_getReferenceGasPrice", params: [])
        case .executeTransactionBlock(let txBytes, let signature):
            return envelope(method: "sui_executeTransactionBlock", params: [txBytes, [signature]])
        case .dryRunTransactionBlock(let txBytes):
            return envelope(method: "sui_dryRunTransactionBlock", params: [txBytes])
        }
    }

    private static func envelope(method: String, params: [Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params
        ]
    }
}
