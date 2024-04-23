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
        case approve
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
    private let thor = ThorchainService.shared
    private let atom = GaiaService.shared
    private let maya = MayachainService.shared
    private let kuji = KujiraService.shared

    func fetchSpecific(for coin: Coin, action: Action = .transfer) async throws -> BlockChainSpecific {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            let sats = try await utxo.fetchSatsPrice(coin: coin)
            return .UTXO(byteFee: sats)

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

        case .ethereum, .avalanche, .bscChain, .arbitrum, .base, .optimism, .polygon, .blast, .cronosChain:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: coin.address)
            let gasLimit = BigInt(coin.feeDefault) ?? 0

            switch action {
            case .transfer:
                if coin.isNativeToken {
                    return .Ethereum(maxFeePerGasWei: gasPrice, priorityFeeWei: priorityFee, nonce: nonce, gasLimit: gasLimit)
                } else {
                    return .ERC20(maxFeePerGasWei: gasPrice, priorityFeeWei: priorityFee, nonce: nonce, gasLimit: gasLimit, contractAddr: coin.contractAddress)
                }
            case .approve:
                return .Ethereum(maxFeePerGasWei: gasPrice, priorityFeeWei: priorityFee, nonce: nonce, gasLimit: gasLimit)
            }

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
}
