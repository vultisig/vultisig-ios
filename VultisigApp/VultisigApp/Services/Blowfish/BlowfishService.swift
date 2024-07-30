//
//  BlowfishService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import Foundation
import BigInt

struct BlowfishService {
    static let shared = BlowfishService()
    
    func scanTransactions
    (
        chain: Chain,
        userAccount: String,
        origin: String,
        txObjects: [BlowfishRequest.BlowfishTxObject],
        simulatorConfig: BlowfishRequest.BlowfishSimulatorConfig? = nil
    ) async throws -> BlowfishEvmResponse? {
        
        guard let supportedChain = blowfishChainName(chain: chain) else {
            return nil
        }
        
        guard let supportedNetwork = blowfishNetwork(chain: chain) else {
            return nil
        }
        
        let blowfishRequest = BlowfishRequest(
            userAccount: userAccount,
            metadata: BlowfishRequest.BlowfishMetadata(origin: origin),
            txObjects: txObjects,
            simulatorConfig: simulatorConfig
        )
        
        let endpoint = Endpoint.fetchBlowfishTransactions(chain: supportedChain, network: supportedNetwork)
        let headers = ["X-Api-Version" : "2023-06-05"]
        let body = try JSONEncoder().encode(blowfishRequest)
        let dataResponse = try await Utils.asyncPostRequest(urlString: endpoint, headers: headers, body: body)
        let response = try JSONDecoder().decode(BlowfishEvmResponse.self, from: dataResponse)
        
        return response
    }
    
    func scanSolanaTransactions
    (
        userAccount: String,
        origin: String,
        transactions: [String]
    ) async throws -> BlowfishEvmResponse? {
        
        let blowfishRequest = BlowfishSolanaRequest(
            userAccount: userAccount,
            metadata: BlowfishSolanaRequest.BlowfishMetadata(origin: origin),
            transactions: transactions
        )
        
        let endpoint = Endpoint.fetchBlowfishSolanaTransactions()
        let headers = ["X-Api-Version" : "2023-06-05"]
        let body = try JSONEncoder().encode(blowfishRequest)
        let dataResponse = try await Utils.asyncPostRequest(urlString: endpoint, headers: headers, body: body)
        let response = try JSONDecoder().decode(BlowfishEvmResponse.self, from: dataResponse)
        
        return response
    }
    
    func blowfishEVMTransactionScan(
        fromAddress: String,
        toAddress: String,
        amountInRaw: BigInt,
        memo: String?,
        chain: Chain
    ) async throws -> BlowfishEvmResponse? {
        
        let amountDataHex = amountInRaw.serializeForEvm().map { byte in String(format: "%02x", byte) }.joined()
        let amountHex = "0x" + amountDataHex
        
        var memoHex: String? = nil
        
        if memo != nil {
            let memoDataHex = memo?.data(using: .utf8)?.map { byte in String(format: "%02x", byte) }.joined()
            if memoDataHex != nil {
                memoHex = "0x" + (memoDataHex ?? "")
            }
        }
        
        let txObjects = [
            BlowfishRequest.BlowfishTxObject(
                from: fromAddress,
                to: toAddress,
                value: amountHex,
                data: memoHex
            )
        ]
        
        let response = try await scanTransactions(
            chain: chain,
            userAccount: fromAddress,
            origin: "https://api.vultisig.com",
            txObjects: txObjects
        )
        
        return response
        
    }
    
    func blowfishSolanaTransactionScan(fromAddress: String, unsignedTransaction: String) async throws -> BlowfishEvmResponse? {
        
        let response = try await scanSolanaTransactions(
            userAccount: fromAddress,
            origin: "https://api.vultisig.com",
            transactions: [unsignedTransaction]
            
        )
        
        return response
        
    }
    
    
    func blowfishChainName(chain: Chain) -> String? {
        switch chain {
        case.ethereum:
            return "ethereum"
        case.polygon:
            return "polygon"
        case.avalanche:
            return "avalanche"
        case.arbitrum:
            return "arbitrum"
        case.optimism:
            return "optimism"
        case.base:
            return "base"
        case.blast:
            return "blast"
        case.bscChain:
            return "bnb"
        case.solana:
            return "solana"
        case.thorChain:
            return nil
        case.bitcoin,.bitcoinCash,.litecoin,.dogecoin,.dash,.gaiaChain,.kujira,.mayaChain,.cronosChain,.sui,.polkadot,.zksync,.dydx:
            return nil
        }
    }
    
    func blowfishNetwork(chain: Chain) -> String? {
        switch chain {
        case .ethereum:
            return "mainnet"
        case .polygon:
            return "mainnet"
        case .avalanche:
            return "mainnet"
        case .arbitrum:
            return "one"
        case .optimism:
            return "mainnet"
        case .base:
            return "mainnet"
        case .blast:
            return "mainnet"
        case .bscChain:
            return "mainnet"
        case .solana:
            return "mainnet"
        case .thorChain:
            return nil
        case .bitcoin,.bitcoinCash,.litecoin,.dogecoin,.dash,.gaiaChain,.kujira,.mayaChain,.cronosChain,.sui,.polkadot,.zksync,.dydx:
            return nil
        }
    }
    
}
