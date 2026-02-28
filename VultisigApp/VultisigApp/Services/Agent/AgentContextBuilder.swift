//
//  AgentContextBuilder.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation

enum AgentContextBuilder {

    static let instructions = [
        "You are currently running inside the Vultisig iOS App.",
        "Do NOT use external tools (like get_eth_balance or get_token_balance) for balances or portfolio.",
        "To fetch balances or prices, you MUST use the respond_to_user tool with actions: [{type: \"get_balances\"}] or actions: [{type: \"get_market_price\"}].",
        "Prefer using your knowledge and conversation context over calling tools.",
        "Only call a tool when you are missing information that you cannot answer from context.",
        "Use markdown formatting for readability."
    ].joined(separator: " ")

    /// Build the message context from the current vault state
    static func buildContext(vault: Vault, balances: [AgentBalanceInfo]? = nil) -> AgentMessageContext {
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

        return AgentMessageContext(
            vaultAddress: vault.pubKeyECDSA,
            vaultName: vault.name,
            balances: balances,
            addresses: addresses,
            coins: coins,
            addressBook: addressBookEntries,
            instructions: instructions
        )
    }

    /// Build a lightweight context (without balances) for subsequent messages
    static func buildLightContext(vault: Vault) -> AgentMessageContext {
        buildContext(vault: vault, balances: nil)
    }
}
