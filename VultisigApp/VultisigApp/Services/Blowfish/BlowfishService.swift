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
    
    enum BlowfishServiceError: Error {
        case unsupportedChain
        case unsupportedNetwork
    }
    
    func scanTransactions(
        chain: Chain,
        userAccount: String,
        origin: String,
        txObjects: [BlowfishRequest.BlowfishTxObject],
        simulatorConfig: BlowfishRequest.BlowfishSimulatorConfig? = nil
    ) async throws -> BlowfishResponse {
        
        let supportedChain = try blowfishChainName(chain: chain)
        let supportedNetwork = try blowfishNetwork(chain: chain)
        
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
        let response = try JSONDecoder().decode(BlowfishResponse.self, from: dataResponse)
        
        return response
    }
    
    enum DecodingCustomError: Error {
        case dataCorrupted(DecodingError.Context)
        case keyNotFound(CodingKey, DecodingError.Context)
        case valueNotFound(Any.Type, DecodingError.Context)
        case typeMismatch(Any.Type, DecodingError.Context)
    }
    
    func scanSolanaTransactions(
        userAccount: String,
        origin: String,
        transactions: [String]
    ) async throws -> BlowfishResponse {
        
        let blowfishRequest = BlowfishSolanaRequest(
            userAccount: userAccount,
            metadata: BlowfishSolanaRequest.BlowfishMetadata(origin: origin),
            transactions: transactions
        )
        
        let endpoint = Endpoint.fetchBlowfishSolanaTransactions()
        let headers = ["X-Api-Version" : "2023-06-05"]
        let body = try JSONEncoder().encode(blowfishRequest)
        let dataResponse = try await Utils.asyncPostRequest(urlString: endpoint, headers: headers, body: body)
        
        let response = try JSONDecoder().decode(BlowfishResponse.self, from: dataResponse)
        return response
    }
    
    func blowfishEVMTransactionScan(
        fromAddress: String,
        toAddress: String,
        amountInRaw: BigInt,
        memo: String?,
        chain: Chain
    ) async throws -> BlowfishResponse {
        
        let amountDataHex = amountInRaw.serializeForEvm().map { byte in String(format: "%02x", byte) }.joined()
        let amountHex = "0x" + amountDataHex
        
        let memoHex: String
        if let memo = memo, let memoDataHex = memo.data(using: .utf8)?.map({ String(format: "%02x", $0) }).joined() {
            memoHex = "0x" + memoDataHex
        } else {
            memoHex = "0x"
        }
        
        let txObjects = [
            BlowfishRequest.BlowfishTxObject(
                from: fromAddress,
                to: toAddress,
                value: amountHex,
                data: memoHex
            )
        ]
        
        return try await scanTransactions(
            chain: chain,
            userAccount: fromAddress,
            origin: "https://api.vultisig.com",
            txObjects: txObjects
        )
    }
    
    func blowfishSolanaTransactionScan(fromAddress: String, zeroSignedTransaction: String) async throws -> BlowfishResponse {
        return try await scanSolanaTransactions(
            userAccount: fromAddress,
            origin: "https://api.vultisig.com",
            transactions: [zeroSignedTransaction]
        )
    }
    
    func blowfishChainName(chain: Chain) throws -> String {
        switch chain {
        case .ethereum:
            return "ethereum"
        case .polygon:
            return "polygon"
        case .avalanche:
            return "avalanche"
        case .arbitrum:
            return "arbitrum"
        case .optimism:
            return "optimism"
        case .base:
            return "base"
        case .blast:
            return "blast"
        case .bscChain:
            return "bnb"
        case .solana:
            return "solana"
        case .thorChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .cronosChain, .sui, .polkadot, .zksync, .dydx, .ton, .osmosis, .terra, .terraClassic:
            throw BlowfishServiceError.unsupportedChain
        }
    }
    
    func blowfishNetwork(chain: Chain) throws -> String {
        switch chain {
        case .ethereum, .polygon, .avalanche, .optimism, .base, .blast, .bscChain, .solana:
            return "mainnet"
        case .arbitrum:
            return "one"
        case .thorChain, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .cronosChain, .sui, .polkadot, .zksync, .dydx, .ton, .osmosis, .terra, .terraClassic:
            throw BlowfishServiceError.unsupportedNetwork
        }
    }
}
