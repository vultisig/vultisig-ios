//
//  AgentToolExecutor.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import SwiftData

@MainActor
final class AgentToolExecutor {

    static func execute(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
        switch action.type {

        // MARK: Chain & Token Management (iOS-side)
        case "add_token", "add_coin":
            return await executeAddToken(action: action, vault: vault)
        case "add_chain":
            return await executeAddChain(action: action, vault: vault)
        case "remove_coin":
            return await executeRemoveToken(action: action, vault: vault)
        case "remove_chain":
            return await executeRemoveChain(action: action, vault: vault)
        case "search_token":
            return await executeSearchToken(action: action, vault: vault)

        // MARK: Vault Info (iOS-side)
        case "list_vaults":
            return await executeListVaults(action: action)
        case "get_addresses":
            return await executeGetAddresses(action: action, vault: vault)
        case "get_balances":
            return await executeGetBalances(action: action, vault: vault)
        case "get_portfolio":
            return await executeGetPortfolio(action: action, vault: vault)
        case "get_market_price":
            return await executeGetMarketPrice(action: action, vault: vault)

        // MARK: Address Book (iOS-side)
        case "get_address_book":
            return await executeGetAddressBook(action: action)
        case "add_address_book", "address_book_add":
            return await executeAddAddressBook(action: action)
        case "delete_address_book", "address_book_remove":
            return await executeDeleteAddressBook(action: action)

        // MARK: Signing (requires iOS Keysign flow - not auto-executeable)
        case "sign_tx", "sign_transaction_bundle":
            return buildErrorResult(action: action, error: "sign_requires_keysign_flow")

        // MARK: Server-side only (handled by agent-backend/MCP, should not reach here)
        case "build_swap_tx", "build_send_tx", "build_custom_tx",
             "plugin_install", "create_policy", "delete_policy",
             "read_evm_contract", "scan_tx", "thorchain_query",
             "build_btc_send", "build_evm_tx", "build_utxo_tx",
             "get_eth_balance", "get_token_balance", "get_utxo_balance",
             "get_utxo_transactions", "list_utxos", "convert_amount",
             "abi_encode", "abi_decode", "evm_call", "evm_tx_info", "btc_fee_rate":
            return buildErrorResult(action: action, error: "handled_server_side")

        default:
            return buildErrorResult(action: action, error: "unknown_action_type")
        }
    }

    // MARK: - List Vaults

    private static func executeListVaults(action: AgentBackendAction) -> AgentActionResult {
        guard let context = Storage.shared.modelContext else {
            return buildErrorResult(action: action, error: "storage_unavailable")
        }
        do {
            var vaults = try context.fetch(FetchDescriptor<Vault>())

            // Support optional search/filter by partial vault name (case-insensitive)
            if let paramsDict = action.params,
               let searchValue = paramsDict["search"]?.value as? String,
               !searchValue.isEmpty {
                vaults = vaults.filter { $0.name.localizedCaseInsensitiveContains(searchValue) }
            }

            let result = vaults.map { v in
                let nativeCoins = v.coins.filter { $0.isNativeToken }
                var addresses: [String: String] = [:]
                for coin in nativeCoins {
                    addresses[coin.chain.name] = coin.address
                }
                var entry: [String: Any] = [
                    "name": v.name,
                    "pubkey_ecdsa": v.pubKeyECDSA,
                    "pubkey_eddsa": v.pubKeyEdDSA,
                    "chains": nativeCoins.map { $0.chain.name },
                    "addresses": addresses,
                    "is_fast_vault": v.isFastVault,
                    "created_at": ISO8601DateFormatter().string(from: v.createdAt)
                ]
                if let mldsa = v.publicKeyMLDSA44, !mldsa.isEmpty {
                    entry["pubkey_mldsa44"] = mldsa
                }
                return entry
            }
            return buildSuccessResult(action: action, data: ["vaults": result, "count": vaults.count])
        } catch {
            return buildErrorResult(action: action, error: error.localizedDescription)
        }
    }

    // MARK: - Get Addresses

    private static func executeGetAddresses(action: AgentBackendAction, vault: Vault) -> AgentActionResult {
        let chainParam: String?
        let vaultNameParam: String?

        if let paramsDict = action.params,
           let paramsData = try? JSONEncoder().encode(paramsDict),
           let decoded = try? JSONDecoder().decode([String: String].self, from: paramsData) {
            chainParam = decoded["chain"]
            vaultNameParam = decoded["vault_name"]
        } else {
            chainParam = nil
            vaultNameParam = nil
        }

        // Resolve target vault: if vault_name is provided, look it up with wildcard matching
        var targetVault = vault
        if let searchName = vaultNameParam, !searchName.isEmpty {
            guard let context = Storage.shared.modelContext else {
                return buildErrorResult(action: action, error: "storage_unavailable")
            }
            do {
                let allVaults = try context.fetch(FetchDescriptor<Vault>())
                if let matched = allVaults.first(where: { $0.name.localizedCaseInsensitiveContains(searchName) }) {
                    targetVault = matched
                } else {
                    return buildErrorResult(action: action, error: "vault_not_found: no vault matching '\(searchName)'")
                }
            } catch {
                return buildErrorResult(action: action, error: error.localizedDescription)
            }
        }

        var coins = targetVault.coins.filter { $0.isNativeToken }
        if let filter = chainParam, !filter.isEmpty {
            coins = coins.filter { $0.chain.rawValue.lowercased() == filter.lowercased() || $0.chain.name.lowercased() == filter.lowercased() }
        }

        let addresses = coins.map { coin -> [String: String] in
            return [
                "chain": coin.chain.name,
                "ticker": coin.ticker,
                "address": coin.address
            ]
        }

        var resultData: [String: Any] = [
            "addresses": addresses,
            "vault_name": targetVault.name,
            "pubkey_ecdsa": targetVault.pubKeyECDSA,
            "pubkey_eddsa": targetVault.pubKeyEdDSA
        ]
        if let mldsa = targetVault.publicKeyMLDSA44, !mldsa.isEmpty {
            resultData["pubkey_mldsa44"] = mldsa
        }
        return buildSuccessResult(action: action, data: resultData)
    }

    // MARK: - Search Token

    private static func executeSearchToken(action: AgentBackendAction, vault: Vault) -> AgentActionResult {
        guard let paramsDict = action.params else {
            return buildErrorResult(action: action, error: "missing_query_param")
        }

        let query: String
        if let q = paramsDict["query"]?.value as? String {
            query = q
        } else {
            return buildErrorResult(action: action, error: "missing_query_param")
        }

        let chainFilter = paramsDict["chain"]?.value as? String
        let queryLower = query.lowercased()

        // Search across the full local TokensStore
        var matches = TokensStore.TokenSelectionAssets.filter { asset in
            asset.ticker.lowercased().contains(queryLower) ||
            asset.chain.name.lowercased().contains(queryLower) ||
            asset.contractAddress.lowercased().contains(queryLower)
        }

        if let chainFilter = chainFilter, !chainFilter.isEmpty {
            matches = matches.filter { $0.chain.rawValue.lowercased() == chainFilter.lowercased() || $0.chain.name.lowercased() == chainFilter.lowercased() }
        }

        let results = matches.prefix(20).map { asset -> [String: Any] in
            let alreadyInVault = vault.coin(for: asset) != nil
            return [
                "chain": asset.chain.name,
                "ticker": asset.ticker,
                "contract_address": asset.contractAddress,
                "decimals": asset.decimals,
                "is_native": asset.isNativeToken,
                "logo": asset.logo,
                "already_in_vault": alreadyInVault
            ]
        }

        return buildSuccessResult(action: action, data: ["results": Array(results), "count": results.count])
    }

    // MARK: - Add Token

    private static func executeAddToken(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var tokensToProcess: [AgentTokenParam] = []
        if let multiParams = try? JSONDecoder().decode(AgentAddTokenParams.self, from: paramsData) {
            tokensToProcess = multiParams.tokens
        } else if let singleParam = try? JSONDecoder().decode(AgentTokenParam.self, from: paramsData) {
            tokensToProcess = [singleParam]
        } else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        // Process tokens concurrently
        let tokenResults: [AgentAddTokenResult] = await withTaskGroup(of: AgentAddTokenResult.self) { group in
            for tokenParam in tokensToProcess {
                group.addTask {
                    guard let chainObj = Chain.allCases.first(where: { $0.rawValue.lowercased() == tokenParam.chain.lowercased() }) else {
                        return AgentAddTokenResult(chain: tokenParam.chain, ticker: tokenParam.ticker, address: nil, contractAddress: tokenParam.contractAddress, success: false, error: "unknown_chain")
                    }

                    let isNative = tokenParam.isNative ?? (tokenParam.contractAddress == nil || tokenParam.contractAddress!.isEmpty)
                    // Use TokensStore to resolve native token decimals — MUST filter by isNativeToken
                    // to avoid picking a non-native coin (e.g. JUP decimals:6 instead of SOL decimals:9 on Solana)
                    let defaultDecimals = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chainObj && $0.isNativeToken })?.decimals ?? 18
                    let decimals = tokenParam.decimals ?? (isNative ? defaultDecimals : 18)

                    let coinMeta = CoinMeta(
                        chain: chainObj,
                        ticker: tokenParam.ticker,
                        logo: tokenParam.logo ?? chainObj.logo,
                        decimals: decimals,
                        priceProviderId: tokenParam.priceProviderId ?? "",
                        contractAddress: tokenParam.contractAddress ?? "",
                        isNativeToken: isNative
                    )

                    let hasChain = vault.coins.contains(where: { $0.chain == chainObj && $0.isNativeToken })

                    do {
                        if let newCoin = try await CoinService.addIfNeeded(asset: coinMeta, to: vault, priceProviderId: coinMeta.priceProviderId) {
                            if isNative {
                                await CoinService.addDiscoveredTokens(nativeToken: newCoin, to: vault)
                            }
                            await MainActor.run {
                                if !vault.defiChains.contains(chainObj) && vault.availableDefiChains.contains(chainObj) {
                                    vault.defiChains.append(chainObj)
                                }
                            }
                            return AgentAddTokenResult(
                                chain: chainObj.rawValue,
                                ticker: newCoin.ticker,
                                address: newCoin.address,
                                contractAddress: newCoin.contractAddress,
                                success: true,
                                error: nil,
                                chainAdded: !hasChain
                            )
                        } else {
                            return AgentAddTokenResult(chain: chainObj.rawValue, ticker: tokenParam.ticker, contractAddress: tokenParam.contractAddress, success: false, error: "failed_to_add")
                        }
                    } catch {
                        return AgentAddTokenResult(chain: chainObj.rawValue, ticker: tokenParam.ticker, contractAddress: tokenParam.contractAddress, success: false, error: error.localizedDescription)
                    }
                }
            }
            var collected: [AgentAddTokenResult] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let anySuccess = tokenResults.contains(where: { $0.success })
        if anySuccess {
            try? Storage.shared.save()
        }

        return AgentActionResult(action: action.type, actionId: action.id, success: tokenResults.contains(where: { $0.success }), data: encodeToAnyCodableDict(["results": tokenResults]))
    }

    // MARK: - Add Chain

    private static func executeAddChain(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var chainsToProcess: [AgentChainParam] = []
        if let multiParams = try? JSONDecoder().decode(AgentAddChainParams.self, from: paramsData) {
            chainsToProcess = multiParams.chains
        } else if let singleParam = try? JSONDecoder().decode(AgentChainParam.self, from: paramsData) {
            chainsToProcess = [singleParam]
        } else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var results: [AgentAddChainResult] = []
        var anySuccess = false

        for chainParam in chainsToProcess {
            guard let chainObj = Chain.allCases.first(where: { $0.rawValue.lowercased() == chainParam.chain.lowercased() }) else {
                results.append(AgentAddChainResult(chain: chainParam.chain, success: false, error: "unknown_chain"))
                continue
            }

            if vault.coins.contains(where: { $0.chain == chainObj && $0.isNativeToken }) {
                results.append(AgentAddChainResult(chain: chainObj.rawValue, success: false, error: "already_exists"))
                continue
            }

            // Filter by isNativeToken to get correct chain decimals (e.g. SOL=9, not JUP=6)
            let defaultDecimals = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chainObj && $0.isNativeToken })?.decimals ?? 18
            // Native fee coin asset
            let feeAsset = CoinMeta(
                chain: chainObj,
                ticker: chainObj.ticker,
                logo: chainObj.logo,
                decimals: defaultDecimals,
                priceProviderId: "",
                contractAddress: "",
                isNativeToken: true
            )

            do {
                if let newCoin = try await CoinService.addIfNeeded(asset: feeAsset, to: vault, priceProviderId: nil) {
                    await CoinService.addDiscoveredTokens(nativeToken: newCoin, to: vault)
                    results.append(AgentAddChainResult(
                        chain: chainObj.rawValue,
                        ticker: newCoin.ticker,
                        address: newCoin.address,
                        success: true,
                        error: nil
                    ))
                    anySuccess = true

                    if !vault.defiChains.contains(chainObj) && vault.availableDefiChains.contains(chainObj) {
                        vault.defiChains.append(chainObj)
                    }
                } else {
                    results.append(AgentAddChainResult(chain: chainObj.rawValue, success: false, error: "failed_to_add"))
                }
            } catch {
                results.append(AgentAddChainResult(chain: chainObj.rawValue, success: false, error: error.localizedDescription))
            }
        }

        if anySuccess {
            try? Storage.shared.save()
        }

        return AgentActionResult(action: action.type, actionId: action.id, success: results.contains(where: { $0.success }), data: encodeToAnyCodableDict(["results": results]))
    }

    // MARK: - Remove Token

    private static func executeRemoveToken(action: AgentBackendAction, vault: Vault) -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var tokensToProcess: [AgentTokenParam] = []
        if let multiParams = try? JSONDecoder().decode(AgentRemoveTokenParams.self, from: paramsData) {
            tokensToProcess = multiParams.tokens
        } else if let singleParam = try? JSONDecoder().decode(AgentTokenParam.self, from: paramsData) {
            tokensToProcess = [singleParam]
        } else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var results: [AgentRemoveTokenResult] = []
        var anySuccess = false

        for tokenParam in tokensToProcess {
            guard let chainObj = Chain.allCases.first(where: { $0.rawValue.lowercased() == tokenParam.chain.lowercased() }) else {
                results.append(AgentRemoveTokenResult(chain: tokenParam.chain, ticker: tokenParam.ticker, success: false, error: "unknown_chain"))
                continue
            }

            // Find the coins to remove
            let coinsToRemove = vault.coins.filter {
                $0.chain == chainObj &&
                $0.ticker.caseInsensitiveCompare(tokenParam.ticker) == .orderedSame &&
                ((tokenParam.contractAddress == nil || tokenParam.contractAddress!.isEmpty) || $0.contractAddress.caseInsensitiveCompare(tokenParam.contractAddress!) == .orderedSame)
            }

            if coinsToRemove.isEmpty {
                results.append(AgentRemoveTokenResult(chain: chainObj.rawValue, ticker: tokenParam.ticker, success: true, error: nil))
                continue
            }

            do {
                try CoinService.removeCoins(coins: coinsToRemove, vault: vault)
                results.append(AgentRemoveTokenResult(chain: chainObj.rawValue, ticker: tokenParam.ticker, success: true, error: nil))
                anySuccess = true
            } catch {
                results.append(AgentRemoveTokenResult(chain: chainObj.rawValue, ticker: tokenParam.ticker, success: false, error: error.localizedDescription))
            }
        }

        if anySuccess {
            try? Storage.shared.save()
        }

        return AgentActionResult(action: action.type, actionId: action.id, success: results.contains(where: { $0.success }), data: encodeToAnyCodableDict(["results": results]))
    }

    // MARK: - Remove Chain

    private static func executeRemoveChain(action: AgentBackendAction, vault: Vault) -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var chainsToProcess: [AgentChainParam] = []
        if let multiParams = try? JSONDecoder().decode(AgentRemoveChainParams.self, from: paramsData) {
            chainsToProcess = multiParams.chains
        } else if let singleParam = try? JSONDecoder().decode(AgentChainParam.self, from: paramsData) {
            chainsToProcess = [singleParam]
        } else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var results: [AgentRemoveChainResult] = []
        var anySuccess = false

        for chainParam in chainsToProcess {
            guard let chainObj = Chain.allCases.first(where: { $0.rawValue.lowercased() == chainParam.chain.lowercased() }) else {
                results.append(AgentRemoveChainResult(chain: chainParam.chain, success: false, error: "unknown_chain"))
                continue
            }

            let vaultCoinsForChain = vault.coins.filter { $0.chain == chainObj }

            if vaultCoinsForChain.isEmpty {
                results.append(AgentRemoveChainResult(chain: chainObj.rawValue, success: true, error: nil))
                continue
            }

            do {
                CoinService.clearHiddenTokensForChain(chainObj, vault: vault)
                try CoinService.removeCoins(coins: vaultCoinsForChain, vault: vault)
                vault.defiChains.removeAll(where: { $0 == chainObj })

                results.append(AgentRemoveChainResult(chain: chainObj.rawValue, success: true, error: nil))
                anySuccess = true
            } catch {
                results.append(AgentRemoveChainResult(chain: chainObj.rawValue, success: false, error: error.localizedDescription))
            }
        }

        if anySuccess {
            try? Storage.shared.save()
        }

        return AgentActionResult(action: action.type, actionId: action.id, success: results.contains(where: { $0.success }), data: encodeToAnyCodableDict(["results": results]))
    }

    // MARK: - Get Address Book

    private static func executeGetAddressBook(action: AgentBackendAction) -> AgentActionResult {
        guard let context = Storage.shared.modelContext else {
            return buildErrorResult(action: action, error: "storage_unavailable")
        }

        let params: AgentGetAddressBookParams?
        if let paramsDict = action.params, let paramsData = try? JSONEncoder().encode(paramsDict) {
            params = try? JSONDecoder().decode(AgentGetAddressBookParams.self, from: paramsData)
        } else {
            params = nil
        }

        do {
            let descriptor = FetchDescriptor<AddressBookItem>()
            var allItems = try context.fetch(descriptor)

            if let chainParam = params?.chain, !chainParam.isEmpty {
                let param = chainParam.lowercased()
                allItems = allItems.filter {
                    $0.coinMeta.chain.rawValue.lowercased() == param ||
                    $0.coinMeta.chain.name.lowercased() == param
                }
            }
            if let query = params?.query, !query.isEmpty {
                let lowerQuery = query.lowercased()
                allItems = allItems.filter { $0.title.lowercased().contains(lowerQuery) || $0.address.lowercased().contains(lowerQuery) }
            }

            let results = allItems.map { item in
                AgentAddressBookEntryResult(
                    id: item.id.uuidString,
                    title: item.title,
                    address: item.address,
                    chain: item.coinMeta.chain.rawValue,
                    chainKind: String(describing: item.coinMeta.chain.chainType)
                )
            }

            let response = AgentGetAddressBookResult(entries: results, totalCount: results.count)
            return AgentActionResult(action: action.type, actionId: action.id, success: true, data: encodeToAnyCodableDict(response))

        } catch {
            return buildErrorResult(action: action, error: error.localizedDescription)
        }
    }

    // MARK: - Add Address Book

    private static func executeAddAddressBook(action: AgentBackendAction) -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        // Support both {entries: [...]} and flat {name, address, chain}
        var entriesToProcess: [AgentAddAddressBookEntryParam] = []
        if let multiParams = try? JSONDecoder().decode(AgentAddAddressBookParams.self, from: paramsData) {
            entriesToProcess = multiParams.entries
        } else if let singleParam = try? JSONDecoder().decode(AgentAddAddressBookEntryParam.self, from: paramsData) {
            entriesToProcess = [singleParam]
        } else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var results: [AgentAddAddressBookResult] = []
        var anySuccess = false

        for entryParam in entriesToProcess {
            let chainName = entryParam.chain
            guard let chainObj = Chain.allCases.first(where: {
                $0.rawValue.lowercased() == chainName.lowercased() ||
                $0.name.lowercased() == chainName.lowercased()
            }) else {
                results.append(AgentAddAddressBookResult(id: "", title: entryParam.resolvedTitle, address: entryParam.address, chain: chainName, success: false, error: "unknown_chain"))
                continue
            }

            // Filter by isNativeToken to get correct chain decimals (e.g. SOL=9, not JUP=6)
            let defaultDecimals = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chainObj && $0.isNativeToken })?.decimals ?? 18
            let meta = CoinMeta(chain: chainObj, ticker: chainObj.ticker, logo: chainObj.logo, decimals: defaultDecimals, priceProviderId: "", contractAddress: "", isNativeToken: true)
            let item = AddressBookItem(title: entryParam.resolvedTitle, address: entryParam.address, coinMeta: meta, order: 0)

            Storage.shared.insert(item)
            results.append(AgentAddAddressBookResult(
                id: item.id.uuidString,
                title: entryParam.resolvedTitle,
                address: entryParam.address,
                chain: chainObj.rawValue,
                success: true,
                error: nil
            ))
            anySuccess = true
        }

        if anySuccess {
            try? Storage.shared.save()
        }

        return AgentActionResult(action: action.type, actionId: action.id, success: results.contains(where: { $0.success }), data: encodeToAnyCodableDict(["results": results]))
    }

    // MARK: - Delete Address Book

    private static func executeDeleteAddressBook(action: AgentBackendAction) -> AgentActionResult {
        guard let context = Storage.shared.modelContext else {
            return buildErrorResult(action: action, error: "storage_unavailable")
        }

        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        // Support both {entries: [...]} and flat {name, address, chain}
        var entriesToProcess: [AgentDeleteAddressBookEntryParam] = []
        if let multiParams = try? JSONDecoder().decode(AgentDeleteAddressBookParams.self, from: paramsData) {
            entriesToProcess = multiParams.entries
        } else if let singleParam = try? JSONDecoder().decode(AgentDeleteAddressBookEntryParam.self, from: paramsData) {
            entriesToProcess = [singleParam]
        } else {
            return buildErrorResult(action: action, error: "invalid_params")
        }

        var results: [AgentDeleteAddressBookResult] = []
        var anySuccess = false

        do {
            let allItems = try context.fetch(FetchDescriptor<AddressBookItem>())

            for param in entriesToProcess {
                var match: AddressBookItem?

                if let idParam = param.id, let uuid = UUID(uuidString: idParam) {
                    match = allItems.first(where: { $0.id == uuid })
                } else if let title = param.resolvedTitle, let chain = param.chain {
                    match = allItems.first(where: {
                        $0.title.lowercased() == title.lowercased() &&
                        ($0.coinMeta.chain.rawValue.lowercased() == chain.lowercased() ||
                         $0.coinMeta.chain.name.lowercased() == chain.lowercased())
                    })
                } else if let address = param.address, let chain = param.chain {
                    match = allItems.first(where: {
                        $0.address.lowercased() == address.lowercased() &&
                        ($0.coinMeta.chain.rawValue.lowercased() == chain.lowercased() ||
                         $0.coinMeta.chain.name.lowercased() == chain.lowercased())
                    })
                } else if let title = param.resolvedTitle {
                    match = allItems.first(where: { $0.title.lowercased() == title.lowercased() })
                } else if let address = param.address {
                    match = allItems.first(where: { $0.address.lowercased() == address.lowercased() })
                }

                if let found = match {
                    Storage.shared.delete(found)
                    results.append(AgentDeleteAddressBookResult(id: found.id.uuidString, title: found.title, chain: found.coinMeta.chain.rawValue, success: true, error: nil))
                    anySuccess = true
                } else {
                    results.append(AgentDeleteAddressBookResult(id: param.id, title: param.resolvedTitle, chain: param.chain, success: false, error: "not_found"))
                }
            }

            if anySuccess {
                try? Storage.shared.save()
            }

        } catch {
            return buildErrorResult(action: action, error: error.localizedDescription)
        }

        return AgentActionResult(action: action.type, actionId: action.id, success: results.contains(where: { $0.success }), data: encodeToAnyCodableDict(["results": results]))
    }

    // MARK: - Read-only Context Builders

    private static func executeGetBalances(action: AgentBackendAction, vault: Vault) -> AgentActionResult {
        let balances = vault.coins.map { coin in
            return [
                "chain": coin.chain.name,
                "ticker": coin.ticker,
                "balance": coin.balanceString,
                "fiatBalance": RateProvider.shared.fiatBalanceString(for: coin)
            ]
        }
        return buildSuccessResult(action: action, data: ["balances": balances])
    }

    private static func executeGetPortfolio(action: AgentBackendAction, vault: Vault) -> AgentActionResult {
        let totalFiat = vault.coins.reduce(Decimal.zero) { $0 + RateProvider.shared.fiatBalance(for: $1) }
        return buildSuccessResult(action: action, data: ["totalFiatBalance": totalFiat.formatToFiat(includeCurrencySymbol: true)])
    }

    private static func executeGetMarketPrice(action: AgentBackendAction, vault: Vault) -> AgentActionResult {
        guard let params = action.params,
              let assetProvider = params["asset"]?.value as? String else {
            return buildErrorResult(action: action, error: "missing_asset_param")
        }

        let asset = assetProvider.lowercased()

        if let coin = vault.coins.first(where: { $0.ticker.lowercased() == asset }) {
            if let rate = RateProvider.shared.rate(for: coin) {
                return buildSuccessResult(action: action, data: [
                    "asset": coin.ticker,
                    "price": rate.value,
                    "fiat": rate.fiat
                ])
            }
        }

        return buildErrorResult(action: action, error: "price_not_found_in_cache")
    }

    // MARK: - Helpers

    private static func buildErrorResult(action: AgentBackendAction, error: String) -> AgentActionResult {
        return AgentActionResult(action: action.type, actionId: action.id, success: false, data: nil, error: error)
    }

    private static func buildSuccessResult(action: AgentBackendAction, data: [String: Any]) -> AgentActionResult {
        let codableData = data.mapValues { AnyCodable($0) }
        return AgentActionResult(action: action.type, actionId: action.id, success: true, data: codableData, error: nil)
    }

    /// Encodes any Encodable value to [String: AnyCodable] via JSON round-trip.
    private static func encodeToAnyCodableDict<T: Encodable>(_ value: T) -> [String: AnyCodable] {
        guard let data = try? JSONEncoder().encode(value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict.mapValues { AnyCodable($0) }
    }
}
