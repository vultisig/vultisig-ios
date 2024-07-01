//
//  KeysignPayload.swift
//  VultisigApp
//

import Foundation
import BigInt
import WalletCore

struct KeysignMessage: Codable, Hashable {
    var sessionID: String
    let serviceName: String
    let payload: KeysignPayload
    let encryptionKeyHex: String
    let useVultisigRelay: Bool
}

enum BlockChainSpecific: Codable, Hashable {
    case UTXO(byteFee: BigInt, sendMaxAmount: Bool) // byteFee
    case Ethereum(maxFeePerGasWei: BigInt, priorityFeeWei: BigInt, nonce: Int64, gasLimit: BigInt) // maxFeePerGasWei, priorityFeeWei, nonce , gasLimit
    case THORChain(accountNumber: UInt64, sequence: UInt64, fee: UInt64)
    case MayaChain(accountNumber: UInt64, sequence: UInt64)
    case Cosmos(accountNumber: UInt64, sequence: UInt64, gas: UInt64)
    case Solana(recentBlockHash: String, priorityFee: BigInt) // priority fee is in microlamports
    case Sui(referenceGasPrice: BigInt, coins: [[String:String]])
    case Polkadot(recentBlockHash: String, nonce: UInt64, currentBlockNumber: BigInt, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String)
    
    var gas: BigInt {
        switch self {
        case .UTXO(let byteFee, _):
            return byteFee
        case .Ethereum(let baseFee, let priorityFeeWei, _, _):
            return baseFee + priorityFeeWei
        case .THORChain(_, _, let fee):
            return fee.description.toBigInt()
        case .MayaChain:
            return MayaChainHelper.MayaChainGas.description.toBigInt() //Maya uses 10e10
        case .Cosmos(_,_,let gas):
            return gas.description.toBigInt()
        case .Solana:
            return SolanaHelper.defaultFeeInLamports
        case .Sui(let referenceGasPrice, _):
            return referenceGasPrice
        case .Polkadot:
            return PolkadotHelper.defaultFeeInPlancks
        }
    }

    var fee: BigInt {
        switch self {
        case .Ethereum(let baseFee, let priorityFeeWei, _, let gasLimit):
            return (baseFee + priorityFeeWei) * gasLimit
        case .UTXO, .THORChain, .MayaChain, .Cosmos, .Solana, .Sui, .Polkadot:
            return gas
        }
    }
}

struct KeysignPayload: Codable, Hashable {
    let coin: Coin
    let toAddress: String
    let toAmount: BigInt
    let chainSpecific: BlockChainSpecific
    let utxos: [UtxoInfo]
    let memo: String?
    let swapPayload: SwapPayload?
    let approvePayload: ERC20ApprovePayload?
    let vaultPubKeyECDSA: String
    let vaultLocalPartyID: String

    var toAmountString: String {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -coin.decimals, significand: 1)
        return "\(decimalAmount * power) \(coin.ticker)"
    }

    static let example = KeysignPayload(coin: Coin.example, toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100, sendMaxAmount: false), utxos: [], memo: "Memo", swapPayload: nil, approvePayload: nil, vaultPubKeyECDSA: "12345", vaultLocalPartyID: "iPhone-100")
}
