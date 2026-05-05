//
//  TonJettonMetadataResolver.swift
//  VultisigApp
//

import Foundation
import OSLog
import WalletCore

/// Resolves a TON jetton wallet address (the per-owner contract whose `to` field
/// appears as the outer destination of a TonConnect jetton transfer) into
/// display metadata for the underlying jetton master: ticker, decimals, logo.
///
/// Mirrors `useTonMessageDecode.ts` from the Vultisig Windows codebase. Look-up
/// order, in priority:
///
/// 1. Built-in tokens registry (`TokensStore.findTokenMeta`) — preferred so the
///    icon comes from the bundled asset catalog.
/// 2. Active vault's enabled coins — covers custom jettons the user already
///    added, even when not in the registry.
/// 3. Toncenter v3: jetton wallet → master mapping (`/ton/v3/jetton/wallets`),
///    then master content (`/ton/v3/jetton/masters`) for ticker/decimals/image.
///
/// Network calls are best-effort; failures degrade to `nil` so the keysign UI
/// can fall back to the raw integer amount + jetton-wallet contract address.
enum TonJettonMetadataResolver {

    private static let logger = Logger(subsystem: "com.vultisig.app", category: "ton-jetton-metadata-resolver")
    private static let httpClient: HTTPClientProtocol = HTTPClient()

    /// Resolved jetton metadata. `address` is the user-friendly master address
    /// (`EQ.../UQ...`) so the caller can key per-jetton state on it.
    struct Resolved: Equatable {
        let masterAddress: String
        let ticker: String
        let decimals: Int
        let logo: String
    }

    /// Resolve the jetton master for the given jetton-wallet contract address.
    ///
    /// `jettonWalletAddress` is the outer `message.to` of a TonConnect jetton
    /// transfer (the *sender's* jetton wallet, NOT the recipient). The function
    /// is best-effort and returns `nil` on any failure path.
    static func resolve(
        jettonWalletAddress: String,
        vault: Vault
    ) async -> Resolved? {
        guard let normalizedWallet = TONAddressConverter.toUserFriendly(
            address: jettonWalletAddress,
            bounceable: true,
            testnet: false
        ) else { return nil }

        // 1. Vault custom token shortcut: when the user has already enabled the
        //    jetton, `coin.address` is the vault's jetton wallet contract — a
        //    direct match means we can skip the Toncenter round-trip entirely.
        if let vaultMatch = findVaultJetton(walletAddress: normalizedWallet, vault: vault) {
            return vaultMatch
        }

        // 2. Otherwise, look up the master on chain so unknown/dApp-only
        //    jettons still render with their real ticker.
        guard let masterAddress = await fetchMasterAddress(walletAddress: normalizedWallet) else {
            return nil
        }

        // 3. Built-in registry first — it's the source of truth for icons.
        if let registry = TokensStore.findTokenMeta(chain: .ton, contractAddress: masterAddress) {
            return Resolved(
                masterAddress: masterAddress,
                ticker: registry.ticker,
                decimals: registry.decimals,
                logo: registry.logo
            )
        }

        // 4. Vault custom token: a user may have added the jetton master under
        //    a different wallet than the dApp is targeting (rare but possible
        //    cross-wallet flows). Match on the master.
        if let vaultMatch = findVaultJettonByMaster(masterAddress: masterAddress, vault: vault) {
            return vaultMatch
        }

        // 5. Last resort: fetch master content from Toncenter for ticker /
        //    decimals / image.
        return await fetchMasterMetadata(masterAddress: masterAddress)
    }

    // MARK: - Helpers

    private static func findVaultJetton(walletAddress: String, vault: Vault) -> Resolved? {
        guard let coin = vault.coins.first(where: { coin in
            coin.chain == .ton
                && !coin.isNativeToken
                && TONAddressConverter.toUserFriendly(
                    address: coin.address,
                    bounceable: true,
                    testnet: false
                ) == walletAddress
        }) else { return nil }
        return Resolved(
            masterAddress: TONAddressConverter.toUserFriendly(
                address: coin.contractAddress,
                bounceable: true,
                testnet: false
            ) ?? coin.contractAddress,
            ticker: coin.ticker,
            decimals: coin.decimals,
            logo: coin.logo
        )
    }

    private static func findVaultJettonByMaster(masterAddress: String, vault: Vault) -> Resolved? {
        guard let coin = vault.coins.first(where: { coin in
            coin.chain == .ton
                && !coin.isNativeToken
                && TONAddressConverter.toUserFriendly(
                    address: coin.contractAddress,
                    bounceable: true,
                    testnet: false
                ) == masterAddress
        }) else { return nil }
        return Resolved(
            masterAddress: masterAddress,
            ticker: coin.ticker,
            decimals: coin.decimals,
            logo: coin.logo
        )
    }

    private static func fetchMasterAddress(walletAddress: String) async -> String? {
        do {
            let response = try await httpClient.request(
                TonAPI.jettonWalletsByAddress(walletAddress: walletAddress),
                responseType: JettonWalletsResponse.self
            )
            guard let wallet = response.data.jetton_wallets.first else { return nil }
            return TONAddressConverter.toUserFriendly(
                address: wallet.jetton,
                bounceable: true,
                testnet: false
            ) ?? wallet.jetton
        } catch {
            logger.error("fetchMasterAddress failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func fetchMasterMetadata(masterAddress: String) async -> Resolved? {
        do {
            let response = try await httpClient.request(
                TonAPI.jettonMasters(jettonAddress: masterAddress),
                responseType: JettonMastersResponse.self
            )
            let body = response.data
            guard let master = body.jetton_masters.first else { return nil }

            var ticker: String?
            var decimals: Int?
            var image: String?

            if let metadata = body.metadata,
               let masterMetadata = metadata[master.address],
               let info = masterMetadata.token_info?.first(where: { $0.valid == true }) {
                ticker = nonEmpty(info.symbol)
                if let raw = info.extra?.decimals { decimals = Int(raw) }
                image = nonEmpty(info.image)
            }
            if let content = master.jetton_content {
                ticker = ticker ?? nonEmpty(content.symbol)
                if decimals == nil, let raw = content.decimals { decimals = Int(raw) }
                image = image ?? nonEmpty(content.image)
            }

            guard let ticker else { return nil }
            return Resolved(
                masterAddress: masterAddress,
                ticker: ticker,
                decimals: decimals ?? 9,
                logo: image ?? ""
            )
        } catch {
            logger.error("fetchMasterMetadata failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
