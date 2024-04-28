//
//  FeeService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt

final class BlockChainService {
    
    enum Action {
        case transfer
        case swap
    }
    
    enum Errors: String, Error, LocalizedError {
        case failToGetAccountNumber
        case failToGetSequenceNo
        case failToGetRecentBlockHash
        
        var errorDescription: String? {
            return String(NSLocalizedString(rawValue, comment: ""))
        }
    }
    
    static let shared = BlockChainService()
    
    private let utxo = BlockchairService.shared
    private let sol = SolanaService.shared
    private let dot = PolkadotService.shared
    private let thor = ThorchainService.shared
    private let atom = GaiaService.shared
    private let maya = MayachainService.shared
    private let kuji = KujiraService.shared
    
    func fetchSpecific(for coin: Coin, action: Action = .transfer) async throws -> BlockChainSpecific {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let sats = try await utxo.fetchSatsPrice(coin: coin)
            let normalized = normalize(sats, action: action)
            return .UTXO(byteFee: normalized)
            
        case .thorChain:
            let account = try await thor.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .THORChain(accountNumber: accountNumber, sequence: sequence)
        case .mayaChain:
            let account = try await maya.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .THORChain(accountNumber: accountNumber, sequence: sequence)
        case .solana:
            async let recentBlockHashPromise = sol.fetchRecentBlockhash()
            async let highPriorityFeePromise = sol.fetchHighPriorityFee(account: coin.address)
            
            let recentBlockHash = try await recentBlockHashPromise
            let highPriorityFee = try await highPriorityFeePromise
            
            guard let recentBlockHash else {
                throw Errors.failToGetRecentBlockHash
            }
            return .Solana(recentBlockHash: recentBlockHash, priorityFee: BigInt(highPriorityFee))
            
        case .polkadot:
            let gasInfo = try await dot.getGasInfo(fromAddress: coin.address)
            return .Polkadot(recentBlockHash: gasInfo.recentBlockHash, nonce: UInt64(gasInfo.nonce), currentBlockNumber: gasInfo.currentBlockNumber, specVersion: gasInfo.specVersion, transactionVersion: gasInfo.transactionVersion)
            
        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: coin.address)
            let gasLimit = BigInt(coin.feeDefault) ?? 0
            let normalizedGasPrice = normalize(gasPrice, action: action)
            
            return .Ethereum(maxFeePerGasWei: normalizedGasPrice, priorityFeeWei: priorityFee, nonce: nonce, gasLimit: gasLimit)
            
        case .gaiaChain:
            let account = try await atom.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500)
        case .kujira:
            let account = try await kuji.fetchAccountNumber(coin.address)
            
            guard let accountNumberString = account?.accountNumber, let accountNumber = UInt64(accountNumberString) else {
                throw Errors.failToGetAccountNumber
            }
            
            guard let sequence = UInt64(account?.sequence ?? "0") else {
                throw Errors.failToGetSequenceNo
            }
            return .Cosmos(accountNumber: accountNumber, sequence: sequence, gas: 7500)
        }
    }
    
    func normalize(_ value: BigInt, action: Action) -> BigInt {
        switch action {
        case .transfer:
            return value
        case .swap:
            return value + value / 2 // x1.5 fee for swaps
        }
    }
}
