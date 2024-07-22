//
//  BlowfishService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import Foundation

struct BlowfishService {
    static let shared = BlowfishService()
    
    func scanTransactions
    (
        chain: Chain,
        userAccount: String,
        origin: String,
        txObjects: [BlowfishRequest.BlowfishTxObject],
        simulatorConfig: BlowfishRequest.BlowfishSimulatorConfig? = nil
    ) async throws -> BlowfishResponse? {
        
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
        let response = try JSONDecoder().decode(BlowfishResponse.self, from: dataResponse)
        
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
