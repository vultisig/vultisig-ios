//
//  CardanoService.swift
//  VultisigApp
//

import Foundation
import BigInt
import OSLog

class CardanoService {

    static let shared = CardanoService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "cardano-service")
    private let httpClient: HTTPClientProtocol

    private init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func getBalance(address: String) async throws -> String {
        let response = try await httpClient.request(
            CardanoAPI.addressInfo(addresses: [address]),
            responseType: [CardanoAddressInfo].self
        )
        return response.data.first?.balance ?? "0"
    }

    /// Fetch the balance for a Cardano coin: ADA when `contractAddress` is
    /// empty, otherwise the matching native-token quantity in token base units.
    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        guard !coin.contractAddress.isEmpty else {
            return try await getBalance(address: address)
        }

        let parsed = try CardanoAssetId.parse(coin.contractAddress)
        let response = try await httpClient.request(
            CardanoAPI.addressAssets(addresses: [address]),
            responseType: [CardanoAssetEntry].self
        )

        let match = response.data.first { asset in
            asset.policyId.lowercased() == parsed.policyId
                && (asset.assetName ?? "").lowercased() == parsed.assetName
        }
        return match?.quantity ?? "0"
    }

    func getExtendedUTXOs(coin: Coin) async throws -> [CardanoExtendedUtxo] {
        let response = try await httpClient.request(
            CardanoAPI.addressUtxosExtended(addresses: [coin.address]),
            responseType: [CardanoExtendedUtxoEntry].self
        )

        return response.data
            .compactMap(CardanoExtendedUtxo.init)
            // Deterministic ordering so both MPC peers produce identical body bytes
            // when the WalletCore planner picks UTXOs.
            .sorted { lhs, rhs in
                if lhs.hash != rhs.hash { return lhs.hash < rhs.hash }
                return lhs.index < rhs.index
            }
    }

    func estimateTransactionFee() -> Int {
        // Use typical Cardano transaction fee range
        // Simple ADA transfers are usually around 170,000-200,000 lovelace (0.17-0.2 ADA)
        // This is much more reliable than trying to calculate from network parameters
        return 180000 // 0.18 ADA - middle of typical range
    }

    /// Fetch current Cardano slot from Koios API
    /// This is used for dynamic TTL calculation to ensure all TSS devices use the same slot reference
    func getCurrentSlot() async throws -> UInt64 {
        let response = try await httpClient.request(
            CardanoAPI.tip,
            responseType: [CardanoTipEntry].self
        )

        guard let tip = response.data.first else {
            throw NSError(domain: "CardanoServiceError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse slot from response"])
        }

        return tip.absSlot
    }

    /// Calculate TTL as current slot + 720 slots (approximately 12 minutes)
    /// This ensures all TSS devices get the same TTL when fetching chain specific data
    func calculateDynamicTTL() async throws -> UInt64 {
        let currentSlot = try await getCurrentSlot()
        return currentSlot + 720 // Add 720 slots (~12 minutes at 1 slot per second)
    }

    /// Broadcast a signed Cardano transaction via Vultisig's Ogmios JSON-RPC proxy.
    /// - Parameters:
    ///   - signedTransaction: signed CBOR in hex.
    ///   - precomputedTxId: txId derived from the pre-image body during signing.
    ///     Used as the canonical hash and as the fallback on Ogmios "already in
    ///     mempool" (code 3117), where another peer beat us to the punch.
    func broadcastTransaction(signedTransaction: String, precomputedTxId: String) async throws -> String {
        // The endpoint returns 200 on success and 400 with a JSON-RPC error
        // envelope on Ogmios-level errors (e.g. code 3117 "already in mempool").
        // The TargetType accepts both codes; decode the envelope here, but if
        // the 400 body isn't a recognisable JSON-RPC envelope, surface the
        // raw body in an HTTP-style error rather than a generic decoding error.
        let raw = try await httpClient.request(CardanoAPI.submitTransaction(cbor: signedTransaction))
        let body: CardanoSubmitTransactionResponse
        do {
            body = try JSONDecoder().decode(CardanoSubmitTransactionResponse.self, from: raw.data)
        } catch {
            let bodyText = String(data: raw.data, encoding: .utf8) ?? "<non-utf8 body>"
            throw NSError(
                domain: "CardanoServiceError",
                code: raw.response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(raw.response.statusCode): \(bodyText)"]
            )
        }

        if let error = body.error {
            if error.code == 3117 {
                logger.info("Transaction already in mempool (3117). Returning precomputed hash: \(precomputedTxId)")
                return precomputedTxId
            }

            throw NSError(
                domain: "CardanoServiceError",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "RPC Error: \(error.message ?? "code \(error.code)")"]
            )
        }

        guard let txId = body.result?.transaction.id else {
            throw NSError(
                domain: "CardanoServiceError",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Missing result in RPC response"]
            )
        }

        return txId
    }
}
