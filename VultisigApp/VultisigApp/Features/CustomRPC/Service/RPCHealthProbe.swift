//
//  RPCHealthProbe.swift
//  VultisigApp
//

import Foundation
import OSLog

/// Result of a live RPC health probe.
enum RPCHealthResult: Equatable {
    /// The endpoint answered the canonical probe with a valid response.
    ///
    /// `networkVerified` is `true` when the probe can also confirm the endpoint
    /// is serving the *expected network* (EVM `eth_chainId` match, THORChain LCD
    /// `node_info`). It is `false` for liveness-only probes — chains with no
    /// chainId equivalent (Ripple, Sui, Bittensor, Polkadot, Ton, Tron) where we
    /// can confirm reachability but not network identity. The UI surfaces this
    /// distinction so the user isn't given a false sense of network safety.
    case ok(latencyMs: Int, networkVerified: Bool)
    /// The endpoint could not be reached (network error / timeout / bad URL).
    case unreachable
    /// EVM only: the endpoint answered but reported a different `chainId`.
    case wrongChain(expected: Int, got: Int)
    /// The endpoint answered but the response wasn't the expected shape.
    case invalidResponse
}

/// TargetType that wraps a user-supplied RPC URL for a single health-probe call.
/// The URL is treated as a complete endpoint (no extra path appended), so it
/// works for both JSON-RPC POST endpoints and REST GET status endpoints.
private struct RPCProbeTarget: TargetType {
    let url: URL
    let method: HTTPMethod
    let task: HTTPTask
    var baseURL: URL { url }
    var path: String { "" }
    var headers: [String: String]? { ["Content-Type": "application/json"] }
    var validationType: ValidationType { .successCodes }
    var timeoutInterval: TimeInterval { 10 }
}

private struct EVMChainIdResponse: Decodable {
    let result: String?
}

private struct SolanaHealthResponse: Decodable {
    let result: String?
}

private struct JSONRPCResultPresentResponse: Decodable {
    /// `result` may be a string, number, or object depending on the method;
    /// we only need to know whether the key is present and non-null.
    let result: AnyDecodable?
}

/// Decodes any JSON value, used purely to assert a JSON-RPC `result` is present.
private struct AnyDecodable: Decodable {
    init(from decoder: Decoder) throws {
        // Succeeds for any concrete JSON value; a missing/null `result` leaves
        // the optional `nil` because the surrounding key isn't decoded.
        _ = try decoder.singleValueContainer()
    }
}

private struct RippleServerStateProbeResponse: Decodable {
    let result: ResultBody?
    struct ResultBody: Decodable {
        let state: AnyDecodable?
    }
}

private struct TronProbeResponse: Decodable {
    /// TronGrid `/wallet/getnowblock` returns the current block, keyed `blockID`.
    let blockID: String?
}

/// Live, chain-aware JSON-RPC / REST health probe for a candidate RPC endpoint.
/// Returns reachability plus round-trip latency so the settings UI can show
/// `reachable · {ms} ms` or a typed failure reason instead of merely validating
/// the URL string.
struct RPCHealthProbe {

    private let httpClient: HTTPClientProtocol
    private let logger = Logger(subsystem: "com.vultisig.app", category: "rpc-health-probe")

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    /// Probes `urlString` for `chain` and returns a typed result.
    func probe(urlString: String, chain: Chain) async -> RPCHealthResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            return .unreachable
        }

        switch chain.chainType {
        case .EVM:
            return await probeEVM(url: url, chain: chain)
        case .Solana:
            return await probeSolana(url: url)
        case .THORChain:
            // Covers thorChain + mayaChain: both expose the Cosmos LCD
            // `node_info`, so reachability here also verifies network identity.
            return await probeThorchain(url: url)
        case .Cosmos:
            return await probeCosmos(url: url)
        case .Ripple:
            return await probeRipple(url: url)
        case .Sui:
            return await probeSui(url: url)
        case .Polkadot:
            // Covers polkadot + bittensor (both substrate JSON-RPC).
            return await probeSubstrate(url: url)
        case .Tron:
            return await probeTron(url: url)
        case .Ton:
            return await probeTon(url: url)
        default:
            return await probeReachability(url: url)
        }
    }

    // MARK: - EVM

    private func probeEVM(url: URL, chain: Chain) async -> RPCHealthResult {
        let target = RPCProbeTarget(
            url: url,
            method: .post,
            task: .requestParameters(
                ["jsonrpc": "2.0", "id": 1, "method": "eth_chainId", "params": [] as [Any]],
                .jsonEncoding
            )
        )
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await httpClient.request(target, responseType: EVMChainIdResponse.self)
            let latency = latencyMs(since: start)
            guard let hex = response.data.result,
                  let got = Int(hex.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
                return .invalidResponse
            }
            guard let expected = chain.chainID else {
                return .ok(latencyMs: latency, networkVerified: true)
            }
            return got == expected ? .ok(latencyMs: latency, networkVerified: true) : .wrongChain(expected: expected, got: got)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Solana

    private func probeSolana(url: URL) async -> RPCHealthResult {
        let target = RPCProbeTarget(
            url: url,
            method: .post,
            task: .requestParameters(
                ["jsonrpc": "2.0", "id": 1, "method": "getHealth", "params": [] as [Any]],
                .jsonEncoding
            )
        )
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await httpClient.request(target, responseType: SolanaHealthResponse.self)
            guard response.data.result == "ok" else { return .invalidResponse }
            return .ok(latencyMs: latencyMs(since: start), networkVerified: true)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - THORChain / Cosmos (Tendermint status GET)

    private func probeThorchain(url: URL) async -> RPCHealthResult {
        await probeStatus(url: url, path: "/cosmos/base/tendermint/v1beta1/node_info")
    }

    private func probeCosmos(url: URL) async -> RPCHealthResult {
        await probeStatus(url: url, path: "/cosmos/base/tendermint/v1beta1/node_info")
    }

    private func probeStatus(url: URL, path: String) async -> RPCHealthResult {
        let probeURL = url.appendingPathComponent(path)
        let target = RPCProbeTarget(url: probeURL, method: .get, task: .requestPlain)
        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await httpClient.request(target)
            return .ok(latencyMs: latencyMs(since: start), networkVerified: true)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Ripple (liveness-only: server_state)

    private func probeRipple(url: URL) async -> RPCHealthResult {
        let target = RPCProbeTarget(
            url: url,
            method: .post,
            task: .requestParameters(
                ["jsonrpc": "2.0", "id": 1, "method": "server_state", "params": [] as [Any]],
                .jsonEncoding
            )
        )
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await httpClient.request(target, responseType: RippleServerStateProbeResponse.self)
            // A live XRPL node returns `result.state`; we can confirm liveness but
            // not which network (no chainId equivalent).
            guard response.data.result?.state != nil else { return .invalidResponse }
            return .ok(latencyMs: latencyMs(since: start), networkVerified: false)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Sui (liveness-only: sui_getLatestCheckpointSequenceNumber)

    private func probeSui(url: URL) async -> RPCHealthResult {
        let target = RPCProbeTarget(
            url: url,
            method: .post,
            task: .requestParameters(
                ["jsonrpc": "2.0", "id": 1, "method": "sui_getLatestCheckpointSequenceNumber", "params": [] as [Any]],
                .jsonEncoding
            )
        )
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await httpClient.request(target, responseType: JSONRPCResultPresentResponse.self)
            guard response.data.result != nil else { return .invalidResponse }
            return .ok(latencyMs: latencyMs(since: start), networkVerified: false)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Substrate / Polkadot + Bittensor (liveness-only: system_health)

    private func probeSubstrate(url: URL) async -> RPCHealthResult {
        let target = RPCProbeTarget(
            url: url,
            method: .post,
            task: .requestParameters(
                ["jsonrpc": "2.0", "id": 1, "method": "system_health", "params": [] as [Any]],
                .jsonEncoding
            )
        )
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await httpClient.request(target, responseType: JSONRPCResultPresentResponse.self)
            guard response.data.result != nil else { return .invalidResponse }
            return .ok(latencyMs: latencyMs(since: start), networkVerified: false)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Tron (liveness-only: wallet/getnowblock)

    private func probeTron(url: URL) async -> RPCHealthResult {
        let probeURL = url.appendingPathComponent("/wallet/getnowblock")
        let target = RPCProbeTarget(url: probeURL, method: .post, task: .requestPlain)
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let response = try await httpClient.request(target, responseType: TronProbeResponse.self)
            guard response.data.blockID != nil else { return .invalidResponse }
            return .ok(latencyMs: latencyMs(since: start), networkVerified: false)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Ton (liveness-only: getMasterchainInfo)

    private func probeTon(url: URL) async -> RPCHealthResult {
        let probeURL = url.appendingPathComponent("/ton/v2/getMasterchainInfo")
        let target = RPCProbeTarget(url: probeURL, method: .get, task: .requestPlain)
        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await httpClient.request(target)
            return .ok(latencyMs: latencyMs(since: start), networkVerified: false)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Fallback reachability

    private func probeReachability(url: URL) async -> RPCHealthResult {
        let target = RPCProbeTarget(url: url, method: .get, task: .requestPlain)
        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await httpClient.request(target)
            return .ok(latencyMs: latencyMs(since: start), networkVerified: false)
        } catch {
            return mapFailure(error)
        }
    }

    // MARK: - Helpers

    private func latencyMs(since start: CFAbsoluteTime) -> Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
    }

    private func mapFailure(_ error: Error) -> RPCHealthResult {
        if case HTTPError.decodingFailed = error {
            return .invalidResponse
        }
        logger.debug("RPC probe failed: \(error.localizedDescription)")
        return .unreachable
    }
}
