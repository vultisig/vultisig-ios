//
//  PolkadotService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 28/04/24.
//

import Foundation
import BigInt

class PolkadotService: RpcService {
    static let rpcEndpoint = Endpoint.polkadotServiceRpc
    static let shared = PolkadotService(rpcEndpoint)
    
    private var cachePolkadotBalance: [String: (data: BigInt, timestamp: Date)] = [:]
    
    private func fetchBalance(address: String) async throws -> BigInt {
        //let storageKey = generateStorageKey(for: accountAddress)
        //return try await intRpcCall(method: "state_getStorage", params: [address])
        
        let cacheKey = "polkadot-\(address)-balance"
        if let cachedData: BigInt = await Utils.getCachedData(cacheKey: cacheKey, cache: cachePolkadotBalance, timeInSeconds: 60*5) {
            return cachedData
        }
        
        let body = ["key": address]
        do {
            let requestBody = try JSONEncoder().encode(body)
            let responseBodyData = try await Utils.asyncPostRequest(urlString: Endpoint.polkadotServiceBalance, headers: [:], body: requestBody)
            
            if let balance = Utils.extractResultFromJson(fromData: responseBodyData, path: "data.account.balance") as? String {
                let decimalBalance = (Decimal(string: balance) ?? Decimal.zero) * pow(10, 10)
                let bigIntResult = decimalBalance.description.toBigInt()
                self.cachePolkadotBalance[cacheKey] = (data: bigIntResult, timestamp: Date())
                return bigIntResult
            }
        } catch {
            print("PolkadotService > fetchBalance > Error encoding JSON: \(error)")
            return BigInt.zero
        }
        
        return BigInt.zero
    }
    
    private func fetchNonce(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "system_accountNextIndex", params: [address])
    }
    
    private func fetchBlockHash() async throws -> String {
        return try await strRpcCall(method: "chain_getBlockHash", params: [])
    }
    
    private func fetchBlockHeader() async throws -> BigInt {
        return try await intRpcCall(method: "chain_getHeader", params: [])
    }
    
    func broadcastTransaction(hex: String) async throws -> String {
        let hexWithPrefix = hex.hasPrefix("0x") ? hex : "0x\(hex)"
        return try await strRpcCall(method: "eth_sendRawTransaction", params: [hexWithPrefix])
    }
    
    func getBalance(coin: Coin) async throws ->(rawBalance: String,priceRate: Double){
        // Start fetching all information concurrently
        let cryptoPrice = await CryptoPriceService.shared.getPrice(priceProviderId: coin.priceProviderId)
        var rawBalance = ""
        do{
            if coin.isNativeToken {
                rawBalance = String(try await fetchBalance(address: coin.address))
            } else {
                //TODO: Implement for tokens
            }
        } catch {
            print("getBalance:: \(error.localizedDescription)")
            throw error
        }
        return (rawBalance,cryptoPrice)
    }
    
    func getGasInfo(fromAddress: String) async throws -> (recentBlockHash: String, currentBlockNumber: BigInt, nonce: Int64) {
        async let recentBlockHash = fetchBlockHash()
        async let nonce = fetchNonce(address: fromAddress)
        async let currentBlockNumber = fetchBlockHeader()
        return (try await recentBlockHash, try await currentBlockNumber, Int64(try await nonce))
    }
}

/*
 {
 "code": 0,
 "message": "Success",
 "generated_at": 1714289374,
 "data": {
 "account": {
 "address": "133aNPNmMZjKJNyKmueFpQoDwmyW72gtSjSpNZ1yJhRPQjfe",
 "balance": "1.084781797",
 "lock": "0",
 "balance_lock": "0",
 "is_evm_contract": false,
 "account_display": {
 "address": "133aNPNmMZjKJNyKmueFpQoDwmyW72gtSjSpNZ1yJhRPQjfe"
 },
 "substrate_account": null,
 "evm_account": "",
 "registrar_info": null,
 "count_extrinsic": 0,
 "reserved": "0",
 "bonded": "0",
 "unbonding": "0",
 "democracy_lock": "0",
 "conviction_lock": "0",
 "election_lock": "0",
 "staking_info": null,
 "nonce": 0,
 "role": "",
 "stash": "",
 "is_council_member": false,
 "is_techcomm_member": false,
 "is_registrar": false,
 "is_fellowship_member": false,
 "is_module_account": false,
 "assets_tag": null,
 "is_erc20": false,
 "is_erc721": false,
 "vesting": null,
 "proxy": {},
 "multisig": {},
 "delegate": null
 }
 }
 }
 */
