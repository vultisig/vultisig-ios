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
    
    private func fetchBalance(address: String) async throws -> BigInt {
        return try await intRpcCall(method: "eth_getBalance", params: [address, "latest"])
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
