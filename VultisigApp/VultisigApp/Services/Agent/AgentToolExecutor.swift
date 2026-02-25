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
        case "add_token":
            return await executeAddToken(action: action, vault: vault)
        case "add_chain":
            return await executeAddChain(action: action, vault: vault)
        case "get_address_book":
            return await executeGetAddressBook(action: action)
        case "add_address_book":
            return await executeAddAddressBook(action: action)
        case "delete_address_book":
            return await executeDeleteAddressBook(action: action)
        case "sign_transaction_bundle":
            // TODO: Implement tx bundle flow
            return buildErrorResult(action: action, error: "not_implemented_yet")
        case "get_balances":
            return await executeGetBalances(action: action, vault: vault)
        case "get_portfolio":
            return await executeGetPortfolio(action: action, vault: vault)
        case "get_market_price":
            return await executeGetMarketPrice(action: action, vault: vault)
        default:
            return buildErrorResult(action: action, error: "unknown_action_type")
        }
    }
    
    // MARK: - Add Token
    
    private static func executeAddToken(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict),
              let params = try? JSONDecoder().decode(AgentAddTokenParams.self, from: paramsData) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }
        
        var results: [AgentAddTokenResult] = []
        var anySuccess = false
        
        for tokenParam in params.tokens {
            guard let chainObj = Chain.allCases.first(where: { $0.rawValue.lowercased() == tokenParam.chain.lowercased() }) else {
                results.append(AgentAddTokenResult(chain: tokenParam.chain, ticker: tokenParam.ticker, address: nil, contractAddress: tokenParam.contractAddress, success: false, error: "unknown_chain"))
                continue
            }
            
            let isNative = tokenParam.isNative ?? (tokenParam.contractAddress == nil || tokenParam.contractAddress!.isEmpty)
            // Use TokensStore to resolve native decimals, fallback to 18
            let defaultDecimals = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chainObj })?.decimals ?? 18
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
            
            // Check if chain added
            let hasChain = vault.coins.contains(where: { $0.chain == chainObj && $0.isNativeToken })
            
            do {
                if let newCoin = try await CoinService.addIfNeeded(asset: coinMeta, to: vault, priceProviderId: coinMeta.priceProviderId) {
                    if isNative {
                        await CoinService.addDiscoveredTokens(nativeToken: newCoin, to: vault)
                    }
                    results.append(AgentAddTokenResult(
                        chain: chainObj.rawValue,
                        ticker: newCoin.ticker,
                        address: newCoin.address,
                        contractAddress: newCoin.contractAddress,
                        success: true,
                        error: nil,
                        chainAdded: !hasChain
                    ))
                    anySuccess = true
                    
                    // Add to defiChains if not already there to show up in dashboard
                    if !vault.defiChains.contains(chainObj) && vault.availableDefiChains.contains(chainObj) {
                        vault.defiChains.append(chainObj)
                    }
                    
                } else {
                    results.append(AgentAddTokenResult(chain: chainObj.rawValue, ticker: tokenParam.ticker, contractAddress: tokenParam.contractAddress, success: false, error: "failed_to_add"))
                }
            } catch {
                results.append(AgentAddTokenResult(chain: chainObj.rawValue, ticker: tokenParam.ticker, contractAddress: tokenParam.contractAddress, success: false, error: error.localizedDescription))
            }
        }
        
        if anySuccess {
            try? Storage.shared.save()
        }
        
        let dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(["results": results])) as? [String: Any]) ?? [:]
        let anyCodableDict = dict.mapValues { AnyCodable($0) }
        
        return AgentActionResult(action: action.type, actionId: action.id, success: true, data: anyCodableDict)
    }
    
    // MARK: - Add Chain
    
    private static func executeAddChain(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict),
              let params = try? JSONDecoder().decode(AgentAddChainParams.self, from: paramsData) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }
        
        var results: [AgentAddChainResult] = []
        var anySuccess = false
        
        for chainParam in params.chains {
            guard let chainObj = Chain.allCases.first(where: { $0.rawValue.lowercased() == chainParam.chain.lowercased() }) else {
                results.append(AgentAddChainResult(chain: chainParam.chain, success: false, error: "unknown_chain"))
                continue
            }
            
            if vault.coins.contains(where: { $0.chain == chainObj && $0.isNativeToken }) {
                results.append(AgentAddChainResult(chain: chainObj.rawValue, success: false, error: "already_exists"))
                continue
            }
            
            let defaultDecimals = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chainObj })?.decimals ?? 18
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
        
        let dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(["results": results])) as? [String: Any]) ?? [:]
        let anyCodableDict = dict.mapValues { AnyCodable($0) }
        
        return AgentActionResult(action: action.type, actionId: action.id, success: true, data: anyCodableDict)
    }
    
    // MARK: - Get Address Book
    
    private static func executeGetAddressBook(action: AgentBackendAction) async -> AgentActionResult {
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
                allItems = allItems.filter { $0.coinMeta.chain.rawValue.lowercased() == chainParam.lowercased() }
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
            let dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any]) ?? [:]
            let anyCodableDict = dict.mapValues { AnyCodable($0) }
            
            return AgentActionResult(action: action.type, actionId: action.id, success: true, data: anyCodableDict)
            
        } catch {
            return buildErrorResult(action: action, error: error.localizedDescription)
        }
    }
    
    // MARK: - Add Address Book
    
    private static func executeAddAddressBook(action: AgentBackendAction) async -> AgentActionResult {
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict),
              let params = try? JSONDecoder().decode(AgentAddAddressBookParams.self, from: paramsData) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }
        
        var results: [AgentAddAddressBookResult] = []
        var anySuccess = false
        
        for entryParam in params.entries {
            guard let chainObj = Chain.allCases.first(where: { $0.rawValue.lowercased() == entryParam.chain.lowercased() }) else {
                results.append(AgentAddAddressBookResult(id: "", title: entryParam.title, address: entryParam.address, chain: entryParam.chain, success: false, error: "unknown_chain"))
                continue
            }
            
            let defaultDecimals = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chainObj })?.decimals ?? 18
            let meta = CoinMeta(chain: chainObj, ticker: chainObj.ticker, logo: chainObj.logo, decimals: defaultDecimals, priceProviderId: "", contractAddress: "", isNativeToken: true)
            let item = AddressBookItem(title: entryParam.title, address: entryParam.address, coinMeta: meta, order: 0)
            
            Storage.shared.insert(item)
            results.append(AgentAddAddressBookResult(
                id: item.id.uuidString,
                title: entryParam.title,
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
        
        let dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(["results": results])) as? [String: Any]) ?? [:]
        let anyCodableDict = dict.mapValues { AnyCodable($0) }
        
        return AgentActionResult(action: action.type, actionId: action.id, success: true, data: anyCodableDict)
    }
    
    // MARK: - Delete Address Book
    
    private static func executeDeleteAddressBook(action: AgentBackendAction) async -> AgentActionResult {
        guard let context = Storage.shared.modelContext else {
            return buildErrorResult(action: action, error: "storage_unavailable")
        }
        
        guard let paramsDict = action.params,
              let paramsData = try? JSONEncoder().encode(paramsDict),
              let params = try? JSONDecoder().decode(AgentDeleteAddressBookParams.self, from: paramsData) else {
            return buildErrorResult(action: action, error: "invalid_params")
        }
        
        var results: [AgentDeleteAddressBookResult] = []
        var anySuccess = false
        
        do {
            let allItems = try context.fetch(FetchDescriptor<AddressBookItem>())
            
            for param in params.entries {
                var match: AddressBookItem?
                
                if let idParam = param.id, let uuid = UUID(uuidString: idParam) {
                    match = allItems.first(where: { $0.id == uuid })
                } else if let title = param.title, let chain = param.chain {
                    match = allItems.first(where: { $0.title.lowercased() == title.lowercased() && $0.coinMeta.chain.rawValue.lowercased() == chain.lowercased() })
                } else if let address = param.address, let chain = param.chain {
                    match = allItems.first(where: { $0.address.lowercased() == address.lowercased() && $0.coinMeta.chain.rawValue.lowercased() == chain.lowercased() })
                }
                
                if let found = match {
                    Storage.shared.delete(found)
                    results.append(AgentDeleteAddressBookResult(id: found.id.uuidString, title: found.title, chain: found.coinMeta.chain.rawValue, success: true, error: nil))
                    anySuccess = true
                } else {
                    results.append(AgentDeleteAddressBookResult(id: param.id, title: param.title, chain: param.chain, success: false, error: "not_found"))
                }
            }
            
            if anySuccess {
                try? Storage.shared.save()
            }
            
        } catch {
            return buildErrorResult(action: action, error: error.localizedDescription)
        }
        
        let dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(["results": results])) as? [String: Any]) ?? [:]
        let anyCodableDict = dict.mapValues { AnyCodable($0) }
        
        return AgentActionResult(action: action.type, actionId: action.id, success: true, data: anyCodableDict)
    }
    
    // MARK: - Read-only Context Builders
    
    private static func executeGetBalances(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
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
    
    private static func executeGetPortfolio(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
        let totalFiat = vault.coins.reduce(Decimal.zero) { $0 + RateProvider.shared.fiatBalance(for: $1) }
        return buildSuccessResult(action: action, data: ["totalFiatBalance": totalFiat.formatToFiat(includeCurrencySymbol: true)])
    }
    
    private static func executeGetMarketPrice(action: AgentBackendAction, vault: Vault) async -> AgentActionResult {
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
}
