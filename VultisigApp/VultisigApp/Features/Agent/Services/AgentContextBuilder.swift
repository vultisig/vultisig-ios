//
//  AgentContextBuilder.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import SwiftData

enum AgentContextBuilder {

    // TODO: Move these instructions to the backend so prompt logic isn't hardcoded in the iOS client.
    // See PR #3910 review (gastonm5): "Is it safe to have these instructions here? Shouldn't we move them to the backend?"
    static let instructions = [
        "You are currently running inside the Vultisig iOS App.",
        "Do NOT use external tools (like get_eth_balance or get_token_balance) for balances, portfolio, or addresses.",
        "To fetch balances or prices, you MUST use the respond_to_user tool with actions: [{type: \"get_balances\"}] or actions: [{type: \"get_market_price\"}].",
        "When a user asks for an address from another vault by name (e.g. 'get Savings vault solana address'), LOOK at the injected `context.all_vaults` JSON array in this prompt. Find the vault using fuzzy/partial name matching on the `name` field, and output the exact address found in its `addresses` object. NEVER say you don't have access to other vaults, because they are provided to you in `all_vaults`.",
        "When a user asks to send funds to a name or contact (e.g. 'send SOL to Alice' or 'send to phantom'), check BOTH the `context.all_vaults` and `context.address_book` JSON arrays using fuzzy/partial name matching. If you find a single match, use that address and proceed with the sign_tx action. If it matches multiple entries or you are unsure if they mean a contact or an internal vault, ask the user to clarify before proceeding.",
        "Prefer using your knowledge and the provided JSON conversation context over calling tools.",
        "Only call a tool when you are missing information that you cannot find in the context JSON.",
        "Use markdown formatting for readability."
    ].joined(separator: " ")

    // MARK: - Context Cache

    /// Cached address-book and vault slices for the light context path.
    /// Both are stable across messages in a single conversation session, so we
    /// hold them for up to `cacheMaxAge` seconds before re-fetching.
    private static var cachedAddressBook: [AgentAddressBookEntry]? = nil
    private static var cachedAllVaults: [AgentVaultInfo]? = nil
    private static var cacheTimestamp: Date? = nil
    private static let cacheMaxAge: TimeInterval = 5 * 60 // 5 minutes

    /// Bug fix (bug 4): using non-nil Optionals as the cache sentinel is wrong when
    /// `cachedAddressBook` legitimately stays nil for users with no address-book entries —
    /// the `cachedAddressBook != nil && cachedAllVaults != nil` guard would never match
    /// and would re-fetch from SwiftData on every message for those users.
    /// A separate boolean flag correctly distinguishes "never populated" from "populated but empty".
    private static var cachePopulated: Bool = false

    private static var isCacheValid: Bool {
        guard cachePopulated, let ts = cacheTimestamp else { return false }
        return Date().timeIntervalSince(ts) < cacheMaxAge
    }

    /// Invalidate the cache. Call this whenever local vault or address-book data changes —
    /// e.g. after add/remove token, add/remove chain, or add/delete address-book entry.
    @MainActor static func invalidateCache() {
        cachedAddressBook = nil
        cachedAllVaults = nil
        cacheTimestamp = nil
        cachePopulated = false   // Bug fix (bug 3): reset sentinel so next call re-fetches
    }

    // MARK: - Full Context (first message)

    /// Build the message context from the current vault state
    @MainActor static func buildContext(vault: Vault, balances: [AgentBalanceInfo]? = nil) -> AgentMessageContext {
        var addresses: [String: String] = [:]
        var coins: [AgentCoinInfo] = []

        for coin in vault.coins {
            // One address per chain from native tokens
            if coin.isNativeToken && !coin.address.isEmpty {
                if addresses[coin.chain.rawValue] == nil {
                    addresses[coin.chain.rawValue] = coin.address
                }
            }

            coins.append(AgentCoinInfo(
                chain: coin.chain.rawValue,
                ticker: coin.ticker,
                contractAddress: coin.contractAddress.isEmpty ? nil : coin.contractAddress,
                isNativeToken: coin.isNativeToken,
                decimals: coin.decimals
            ))
        }

        // Fetch + cache address book and all vaults
        let (addressBook, allVaults) = fetchAndCacheStaticSlices()

        return AgentMessageContext(
            vaultAddress: vault.pubKeyECDSA,
            vaultName: vault.name,
            balances: balances,
            addresses: addresses,
            coins: coins,
            addressBook: addressBook,
            allVaults: allVaults,
            instructions: instructions
        )
    }

    // MARK: - Light Context (subsequent messages)

    /// Build a lightweight context for subsequent messages.
    /// Skips coin enumeration and returns cached address-book / vault slices
    /// rather than re-fetching from SwiftData on every message.
    @MainActor static func buildLightContext(vault: Vault) -> AgentMessageContext {
        let (addressBook, allVaults) = fetchAndCacheStaticSlices()

        // Only include vault-specific coin list (cheap — it's already loaded in memory)
        var addresses: [String: String] = [:]
        for coin in vault.coins where coin.isNativeToken && !coin.address.isEmpty {
            if addresses[coin.chain.rawValue] == nil {
                addresses[coin.chain.rawValue] = coin.address
            }
        }

        return AgentMessageContext(
            vaultAddress: vault.pubKeyECDSA,
            vaultName: vault.name,
            balances: nil,
            addresses: addresses,
            coins: nil,          // Omit full coin list on light requests
            addressBook: addressBook,
            allVaults: allVaults,
            instructions: instructions
        )
    }

    // MARK: - Internal Cache Helper

    @MainActor
    private static func fetchAndCacheStaticSlices() -> (addressBook: [AgentAddressBookEntry]?, allVaults: [AgentVaultInfo]?) {
        // Return cached values if they are still fresh (uses cachePopulated sentinel — not Optional nil-check)
        if isCacheValid {
            return (cachedAddressBook, cachedAllVaults)
        }

        guard let modelContext = Storage.shared.modelContext else {
            return (nil, nil)
        }

        // --- Address Book ---
        var addressBookEntries: [AgentAddressBookEntry]? = nil
        if let items = try? modelContext.fetch(FetchDescriptor<AddressBookItem>()),
           !items.isEmpty {
            addressBookEntries = items.map {
                AgentAddressBookEntry(
                    title: $0.title,
                    address: $0.address,
                    chain: $0.coinMeta.chain.name
                )
            }
        }

        // --- All Vaults ---
        var allVaults: [AgentVaultInfo]? = nil
        if let vaults = try? modelContext.fetch(FetchDescriptor<Vault>()) {
            allVaults = vaults.map { v in
                let nativeCoins = v.coins.filter { $0.isNativeToken }
                var vaultAddresses: [String: String] = [:]
                for coin in nativeCoins {
                    if !coin.address.isEmpty {
                        vaultAddresses[coin.chain.name] = coin.address
                    }
                }
                return AgentVaultInfo(
                    name: v.name,
                    pubKeyECDSA: v.pubKeyECDSA,
                    pubKeyEdDSA: v.pubKeyEdDSA,
                    pubKeyMLDSA44: v.publicKeyMLDSA44,
                    addresses: vaultAddresses
                )
            }
        }

        // Store in cache — set sentinel LAST so isCacheValid stays false if we crash mid-fetch
        cachedAddressBook = addressBookEntries
        cachedAllVaults = allVaults
        cacheTimestamp = Date()
        cachePopulated = true   // Bug fix: sentinel marks cache as valid regardless of nil arrays

        return (addressBookEntries, allVaults)
    }
}
