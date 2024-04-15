//
//  FeeService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 08.04.2024.
//

import Foundation
import BigInt

final class BlockChainService {

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

    func fetchSpecific(for coin: Coin) async throws -> BlockChainSpecific {
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin:
            let sats = try await utxo.fetchSatsPrice(coin: coin)
            return .UTXO(byteFee: Int64(sats))

        case .thorChain:
            let account = try await thor.fetchAccountNumber(coin.address)

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

            let (recentBlockHash, feeInLamports) = try await recentBlockHashPromise
            let highPriorityFee = try await highPriorityFeePromise

            guard let recentBlockHash else {
                throw Errors.failToGetRecentBlockHash
            }
            return .Solana(recentBlockHash: recentBlockHash, priorityFee: highPriorityFee, feeInLamports: feeInLamports)

        case .ethereum, .avalanche, .bscChain:
            let service = try EvmServiceFactory.getService(forChain: coin)
            let (gasPrice, priorityFee, nonce) = try await service.getGasInfo(fromAddress: coin.address)

            if coin.isNativeToken {
                return .Ethereum(maxFeePerGasGwei: Int64(gasPrice) ?? 42, priorityFeeGwei: priorityFee, nonce: nonce, gasLimit: EVMHelper.defaultETHTransferGasUnit)
            } else {
                return BlockChainSpecific.ERC20(maxFeePerGasGwei: Int64(gasPrice) ?? 42, priorityFeeGwei: priorityFee, nonce: nonce, gasLimit: EVMHelper.defaultERC20TransferGasUnit, contractAddr: coin.contractAddress)
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
            
        case .ton:
            return .Ton(sequence: 0)
        }
    }
}
