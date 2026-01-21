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
    func broadcastTransaction(jsonString: String) async -> Result<String, Error>
    func fetchTcyStakedAmount(address: String) async -> Decimal
    func fetchTcyAutoCompoundAmount(address: String) async -> Decimal
    func fetchMergeAccounts(address: String) async -> [MergeAccountResponse.ResponseData.Node.AccountMerge.MergeAccount]
    func resolveTNS(name: String, chain: Chain) async throws -> String
    func fetchYieldTokenPrice(for contract: String) async -> Double?
    func getAssetPriceInUSD(assetName: String) async -> Double
}

extension ThorchainService: ThorchainServiceProtocol {}
extension ThorchainStagenetService: ThorchainServiceProtocol {}

enum ThorchainServiceFactory {

    static func getService(for chain: Chain) -> ThorchainServiceProtocol {
        switch chain {
        case .thorChainStagenet:
            return ThorchainStagenetService.shared
        default:
            guard chain.chainType == .THORChain else {
                fatalError("Chain \(chain) is not a THORChain variant")
            }

            return ThorchainService.shared
        }
    }
}
