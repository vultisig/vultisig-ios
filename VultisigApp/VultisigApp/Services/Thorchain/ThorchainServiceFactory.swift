//
//  ThorchainServiceFactory.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/10/2025.
//

import Foundation

protocol ThorchainServiceProtocol {
    var network: String { get set }
    func fetchBalances(_ address: String) async throws -> [CosmosBalance]
    func fetchTokens(_ address: String) async throws -> [CoinMeta]
    func fetchAccountNumber(_ address: String) async throws -> THORChainAccountValue?
    func fetchFeePrice() async throws -> UInt64
    func fetchThorchainInboundAddress() async -> [InboundAddress]
    func getTHORChainChainID() async throws -> String
    func ensureTHORChainChainID() -> String
    func broadcastTransaction(jsonString: String) async -> Result<String,Error>
}

extension ThorchainService: ThorchainServiceProtocol {}
extension ThorchainStagenetService: ThorchainServiceProtocol {}

enum ThorchainServiceFactory {
    
    static func getService(for chain: Chain) -> ThorchainServiceProtocol {
        switch chain {
        case .thorChain:
            return ThorchainService.shared
        case .thorChainStagenet:
            return ThorchainStagenetService.shared
        default:
            fatalError("Chain \(chain) is not a THORChain variant")
        }
    }
}

