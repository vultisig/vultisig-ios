//
//  BlockChainSpecific.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.07.2024.
//

import Foundation
import BigInt
import VultisigCommonData

enum BlockChainSpecific: Codable, Hashable {
    case UTXO(byteFee: BigInt, sendMaxAmount: Bool)
    case Cardano(byteFee: BigInt, sendMaxAmount: Bool, ttl: UInt64)
    case Ethereum(maxFeePerGasWei: BigInt, priorityFeeWei: BigInt, nonce: Int64, gasLimit: BigInt)
    case THORChain(accountNumber: UInt64, sequence: UInt64, fee: UInt64, isDeposit: Bool, transactionType: Int = 0)
    case MayaChain(accountNumber: UInt64, sequence: UInt64, isDeposit: Bool)
    case Cosmos(accountNumber: UInt64, sequence: UInt64, gas: UInt64, transactionType: Int, ibcDenomTrace: CosmosIbcDenomTraceDenomTrace?)
    case Solana(recentBlockHash: String, priorityFee: BigInt, priorityLimit: BigInt, fromAddressPubKey: String?, toAddressPubKey: String?, hasProgramId: Bool) // priority fee is in microlamports
    case Sui(referenceGasPrice: BigInt, coins: [[String: String]], gasBudget: BigInt)
    case Polkadot(recentBlockHash: String, nonce: UInt64, currentBlockNumber: BigInt, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String, gas: BigInt? = nil)
    case Ton(sequenceNumber: UInt64, expireAt: UInt64, bounceable: Bool, sendMaxAmount: Bool, jettonAddress: String = "", isActiveDestination: Bool = false)
    case Ripple(sequence: UInt64, gas: UInt64, lastLedgerSequence: UInt64)
    
    case Tron(
        timestamp: UInt64,
        expiration: UInt64,
        blockHeaderTimestamp: UInt64,
        blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64,
        blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String,
        blockHeaderWitnessAddress: String,
        gasFeeEstimation: UInt64
    )
    
    var gas: BigInt {
        switch self {
        case .UTXO(let byteFee, _):
            return byteFee
        case .Cardano(let byteFee, _, _):
            return byteFee
        case .Ethereum(let maxFeePerGasWei, _, _, _):
            return maxFeePerGasWei
        case .THORChain(_, _, let fee, _, _):
            return fee.description.toBigInt()
        case .MayaChain:
            return MayaChainHelper.MayaChainGas.description.toBigInt() // Maya uses 10e10
        case .Cosmos(_,_,let gas, _, _):
            return gas.description.toBigInt()
        case .Solana:
            return SolanaHelper.defaultFeeInLamports
        case .Sui(_, _, let gasBudget):
            return gasBudget
        case .Polkadot(_, _, _, _, _, _, let gas):
            guard let dynamicGas = gas else {
                return 0 // We should throw
            }
            return dynamicGas
        case .Ton:
            return TonHelper.defaultFee
        case .Ripple(_, let gas, _):
            return gas.description.toBigInt()
        case .Tron(_, _, _, _, _, _, _, _, let gasFeeEstimation):
            return gasFeeEstimation.description.toBigInt()
        }
    }
    
    var fee: BigInt {
        switch self {
        case .Ethereum(let maxFeePerGas, _, _, let gasLimit):
            return maxFeePerGas * gasLimit
        case .UTXO:
            return gas // For UTXO, gas represents the byteFee (sats/byte rate), not the total fee
        case .Sui(_, _, let gasBudget):
            return gasBudget // For Sui, return the actual gas budget (total fee estimate)
        case .Cardano, .THORChain, .MayaChain, .Cosmos, .Solana, .Polkadot, .Ton, .Ripple, .Tron:
            return gas
        }
    }
    
    var gasLimit: BigInt? {
        switch self {
        case .Ethereum(_, _, _, let gasLimit):
            return gasLimit
        case .UTXO, .Cardano, .THORChain, .MayaChain, .Cosmos, .Solana, .Sui, .Polkadot, .Ton, .Ripple, .Tron:
            return nil
        }
    }
}
