//
//  AgentContextBuilder.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import SwiftData

enum AgentContextBuilder {

    static let instructions = [
        "You are currently running inside the Vultisig iOS App.",
        "Do NOT use external tools (like get_eth_balance or get_token_balance) for balances, portfolio, or addresses.",
        "To fetch balances or prices, you MUST use the respond_to_user tool with actions: [{type: \"get_balances\"}] or actions: [{type: \"get_market_price\"}].",
        "When a user asks for an address from another vault by name (e.g. 'get JP vault solana address'), LOOK at the injected `context.all_vaults` JSON array in this prompt. Find the vault using fuzzy/partial name matching on the `name` field, and output the exact address found in its `addresses` object. NEVER say you don't have access to other vaults, because they are provided to you in `all_vaults`.",
        "When a user asks to send funds to a name or contact (e.g. 'send SOL to JP' or 'send to phantom'), check BOTH the `context.all_vaults` and `context.address_book` JSON arrays using fuzzy/partial name matching. If you find a single match, use that address and proceed with the sign_tx action. If it matches multiple entries or you are unsure if they mean a contact or an internal vault, ask the user to clarify before proceeding.",
        "Prefer using your knowledge and the provided JSON conversation context over calling tools.",
        "Only call a tool when you are missing information that you cannot find in the context JSON.",
        "Use markdown formatting for readability."
    ].joined(separator: " ")

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

        // Wire up address book items from SwiftData
        var addressBookEntries: [AgentAddressBookEntry]? = nil
        if let modelContext = Storage.shared.modelContext,
           let items = try? modelContext.fetch(FetchDescriptor<AddressBookItem>()),
           !items.isEmpty {
            addressBookEntries = items.map {
                AgentAddressBookEntry(
                    title: $0.title,
                    address: $0.address,
                    chain: $0.coinMeta.chain.name
                )
            }
        }

        // Include all vaults with their addresses and public keys
        var allVaults: [AgentVaultInfo]? = nil
        if let modelContext = Storage.shared.modelContext,
           let vaults = try? modelContext.fetch(FetchDescriptor<Vault>()) {
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

        return AgentMessageContext(
            vaultAddress: vault.pubKeyECDSA,
            vaultName: vault.name,
            balances: balances,
            addresses: addresses,
            coins: coins,
            addressBook: addressBookEntries,
            allVaults: allVaults,
            instructions: instructions
        )
    }

    /// Build a lightweight context (without balances) for subsequent messages
    @MainActor static func buildLightContext(vault: Vault) -> AgentMessageContext {
        buildContext(vault: vault, balances: nil)
    }
}
