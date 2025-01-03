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
    case Ethereum(maxFeePerGasWei: BigInt, priorityFeeWei: BigInt, nonce: Int64, gasLimit: BigInt)
    case THORChain(accountNumber: UInt64, sequence: UInt64, fee: UInt64, isDeposit: Bool)
    case MayaChain(accountNumber: UInt64, sequence: UInt64, isDeposit: Bool)
    case Cosmos(accountNumber: UInt64, sequence: UInt64, gas: UInt64, transactionType: Int, ibcDenomTrace: CosmosIbcDenomTraceDenomTrace?)
    case Solana(recentBlockHash: String, priorityFee: BigInt, fromAddressPubKey: String?, toAddressPubKey: String?) // priority fee is in microlamports
    case Sui(referenceGasPrice: BigInt, coins: [[String:String]])
    case Polkadot(recentBlockHash: String, nonce: UInt64, currentBlockNumber: BigInt, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String)
    case Ton(sequenceNumber: UInt64, expireAt: UInt64, bounceable: Bool)
    case Ripple(sequence: UInt64, gas: UInt64)
    
    case Tron(
        timestamp: UInt64,
        expiration: UInt64,
        blockHeaderTimestamp: UInt64,
        blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64,
        blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String,
        blockHeaderWitnessAddress: String
    )
    
    var gas: BigInt {
        switch self {
        case .UTXO(let byteFee, _):
            return byteFee
        case .Ethereum(let baseFee, let priorityFeeWei, _, _):
            return baseFee + priorityFeeWei
        case .THORChain(_, _, let fee, _):
            return fee.description.toBigInt()
        case .MayaChain:
            return MayaChainHelper.MayaChainGas.description.toBigInt() //Maya uses 10e10
        case .Cosmos(_,_,let gas, _, _):
            return gas.description.toBigInt()
        case .Solana:
            return SolanaHelper.defaultFeeInLamports
        case .Sui(let referenceGasPrice, _):
            return referenceGasPrice
        case .Polkadot:
            return PolkadotHelper.defaultFeeInPlancks
        case .Ton(_,_,_):
            return BigInt(0.001 * 10e9)
        case .Ripple(_, let gas):
            return gas.description.toBigInt()
        case .Tron(_, _, _, _, _, _, _, _):
            return gas.description.toBigInt()
        }
    }
    
    var fee: BigInt {
        switch self {
        case .Ethereum(let maxFeePerGas, _, _, let gasLimit):
            return maxFeePerGas * gasLimit
        case .UTXO, .THORChain, .MayaChain, .Cosmos, .Solana, .Sui, .Polkadot, .Ton, .Ripple, .Tron:
            return gas
        }
    }
    
    var baseFee: BigInt? {
        switch self {
        case .Ethereum(let maxFeePerGas, let priorityFee, _, _):
            return maxFeePerGas - priorityFee
        case .UTXO, .THORChain, .MayaChain, .Cosmos, .Solana, .Sui, .Polkadot, .Ton, .Ripple, .Tron:
            return nil
        }
    }

    var gasLimit: BigInt? {
        switch self {
        case .Ethereum(_, _, _, let gasLimit):
            return gasLimit
        case .UTXO, .THORChain, .MayaChain, .Cosmos, .Solana, .Sui, .Polkadot, .Ton, .Ripple, .Tron:
            return nil
        }
    }
}
