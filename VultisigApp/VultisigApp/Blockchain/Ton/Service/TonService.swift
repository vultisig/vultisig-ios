import Foundation
import WalletCore
import BigInt
import OSLog

class TonService {

    static let shared = TonService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "ton-service")
    private let httpClient: HTTPClientProtocol = HTTPClient()

    /// Resolves the TON custom RPC override. Injected so the API values are
    /// built from a dependency rather than a global reach-in; resolution happens
    /// per request inside `api(_:)` so a runtime override change is picked up
    /// live. The default host stays the Vultisig proxy, so default users are
    /// unaffected; an override only swaps the host (the `/ton/v2|v3` paths are
    /// preserved, matching TON Center's public API scheme).
    private let resolver: RPCEndpointResolving

    init(resolver: RPCEndpointResolving = CustomRPCStore.shared) {
        self.resolver = resolver
    }

    /// The override-aware TON host. Falls back to the default proxy host when no
    /// override is set.
    private var resolvedHost: URL {
        resolver.resolvedURL(for: .ton, default: TonAPI.defaultHost)
    }

    /// Builds a pure `TonAPI` value with the resolved host baked in. The
    /// `TargetType` itself never consults the resolver.
    private func api(_ endpoint: TonAPI.Endpoint) -> TonAPI {
        TonAPI(endpoint, host: resolvedHost)
    }

    func broadcastTransaction(_ obj: String) async throws -> String {
        let response = try await httpClient.request(
            api(.broadcastTransaction(boc: obj)),
            responseType: ApiResponse<TonBroadcastSuccessResponse>.self
        )

        if response.response.statusCode == 500 {
            // TON wraps "duplicate message" under ApiResponse.error; decode the
            // same envelope and treat duplicates as soft-success (returning "").
            let duplicate = response.data.error?.contains("duplicate message") ?? false
            if duplicate {
                return ""
            }
            throw NSError(domain: "Server Error", code: 500, userInfo: [NSLocalizedDescriptionKey: response.data.error ?? "Unknown server error"])
        }

        guard let hash = response.data.result?.hash else {
            throw NSError(
                domain: "TonService",
                code: response.response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Missing result.hash in TON broadcast response"]
            )
        }
        return hash
    }

    func getTONBalance(address: String) async throws -> String {
        let response = try await httpClient.request(
            api(.addressInformation(address: address)),
            responseType: TonAddressInformation.self
        )
        return response.data.balance ?? .zero
    }

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        if coin.isNativeToken {
            return try await getTONBalance(address: address)
        } else {
            return try await getJettonBalance(coin: coin, address: address)
        }
    }

    func getWalletState(_ address: String) async throws -> String {
        let response = try await httpClient.request(
            api(.addressInformation(address: address)),
            responseType: TonAddressInformation.self
        )
        return response.data.status ?? "uninit"
    }

    func getJettonBalance(coin: CoinMeta, address: String) async throws -> String {
        do {
            let response = try await httpClient.request(
                api(.jettonWallets(ownerAddress: address, jettonMasterAddress: coin.contractAddress)),
                responseType: JettonWalletsResponse.self
            )

            let normalizedCoinAddress = TONAddressConverter.toUserFriendly(address: coin.contractAddress, bounceable: true, testnet: false) ?? coin.contractAddress

            for wallet in response.data.jetton_wallets {
                let normalizedJettonAddress = TONAddressConverter.toUserFriendly(address: wallet.jetton, bounceable: true, testnet: false) ?? wallet.jetton
                if normalizedJettonAddress == normalizedCoinAddress {
                    return wallet.balance
                }
            }
            return String.zero
        } catch HTTPError.statusCode(let code, let data) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<non-utf8>"
            logger.error("getJettonBalance non-200: \(code) body=\(body)")
            return String.zero
        } catch {
            logger.error("Failed to parse jetton balance response: \(error.localizedDescription)")
            return String.zero
        }
    }

    /// Fetches jetton token metadata (name, symbol, decimals) from the Toncenter v3 `/jetton/masters` endpoint.
    /// - Parameter contractAddress: The jetton master contract address to look up.
    /// - Returns: A tuple of the token's display name, ticker symbol, and decimal precision.
    /// - Throws: `URLError` when the server returns an error or no master entry is found.
    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        let mastersResponse: JettonMastersResponse
        do {
            let response = try await httpClient.request(
                api(.jettonMasters(jettonAddress: contractAddress)),
                responseType: JettonMastersResponse.self
            )
            mastersResponse = response.data
        } catch HTTPError.statusCode {
            throw URLError(.badServerResponse)
        }

        guard let master = mastersResponse.jetton_masters.first else {
            throw URLError(.resourceUnavailable)
        }

        var name = ""
        var symbol = ""
        var decimals = 0

        if let metadata = mastersResponse.metadata,
           let masterMetadata = metadata[master.address],
           let tokenInfo = masterMetadata.token_info?.first(where: { $0.valid == true }) {
            name = tokenInfo.name ?? ""
            symbol = tokenInfo.symbol ?? ""
            if let extraDecimals = tokenInfo.extra?.decimals {
                decimals = Int(extraDecimals) ?? 0
            }
        }

        if let content = master.jetton_content {
            if name.isEmpty { name = content.name ?? "" }
            if symbol.isEmpty { symbol = content.symbol ?? "" }
            if decimals == 0, let contentDecimals = content.decimals {
                decimals = Int(contentDecimals) ?? 0
            }
        }

        return (name, symbol, decimals)
    }

    func getSpecificTransactionInfo(_ coin: Coin) async throws -> (UInt64, UInt64) {
        let now = Date()
        let futureDate = now.addingTimeInterval(600)
        let expireAt = UInt64(futureDate.timeIntervalSince1970)

        let response = try await httpClient.request(
            api(.extendedAddressInformation(address: coin.address)),
            responseType: TonExtendedAddressInformation.self
        )

        let seqno = response.data.result?.accountState?.seqno ?? 0
        return (seqno, expireAt)
    }

    /// Resolves the owner's jetton wallet address, retrying a few times to ride
    /// out transient RPC failures. Returns `nil` only when every attempt fails —
    /// callers must treat that as a hard error and never fall back to the master
    /// contract address.
    func resolveJettonWalletAddress(ownerAddress: String, masterAddress: String, maxAttempts: Int = 3) async -> String? {
        for attempt in 1...max(1, maxAttempts) {
            if let resolved = await runGetWalletAddress(owner: ownerAddress, master: masterAddress) {
                return resolved
            }
            if attempt < maxAttempts {
                logger.warning("Jetton wallet resolution failed (attempt \(attempt)/\(maxAttempts)), retrying")
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        logger.error("Failed to resolve jetton wallet address after \(maxAttempts) attempts")
        return nil
    }

    private func runGetWalletAddress(owner: String, master: String) async -> String? {
        guard let boc = TONAddressConverter.toBoc(address: owner) else { return nil }

        do {
            // `RunGetMethodFlexibleResponse` is a strict superset of the older
            // RunGetMethodResponse shape — every `StackItem` decodes as
            // `.object(StackItem)`, and array-shaped stack entries decode as
            // `.array(...)`. One typed decode covers both server variants.
            let response = try await httpClient.request(
                api(.runGetMethod(address: master, method: "get_wallet_address", stack: [["tvm.Slice", boc]])),
                responseType: RunGetMethodFlexibleResponse.self
            )

            guard response.data.ok != false, let stack = response.data.result?.stack else {
                return nil
            }

            for entry in stack {
                if let address = decodeJettonWalletAddress(from: entry) {
                    return address
                }
            }
        } catch {
            logger.error("Error running Ton get_wallet_address: \(error.localizedDescription)")
        }
        return nil
    }

    private func decodeJettonWalletAddress(from entry: FlexibleStackEntry) -> String? {
        switch entry {
        case .object(let item):
            if let boc = item.boc, let addr = TONAddressConverter.fromBoc(boc: boc) {
                return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
            }
            if let value = item.value {
                let blob = value.bytes ?? value.b64 ?? value.boc
                if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                    return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                }
            }
        case .array(let arr):
            if let v = arr.value {
                let blob = v.bytes ?? v.b64 ?? v.boc
                if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                    return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                }
            }
        }
        return nil
    }

}
