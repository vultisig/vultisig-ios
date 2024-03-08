//
//  KeysignPayload.swift
//  VoltixApp
//

import Foundation

struct KeysignMessage: Codable, Hashable {
    let sessionID: String
    let serviceName: String
    let payload: KeysignPayload
}

enum BlockChainSpecific: Codable, Hashable {
    case Bitcoin(byteFee: Int64) // byteFee
    case Ethereum(maxFeePerGasGwei: Int64, priorityFeeGwei: Int64, nonce: Int64, gasLimit: Int64) // maxFeePerGasGwei, priorityFeeGwei, nonce , gasLimit
    case ERC20(maxFeePerGasGwei: Int64, priorityFeeGwei: Int64, nonce: Int64, gasLimit: Int64, contractAddr: String)
    case THORChain(accountNumber: UInt64, sequence: UInt64)
    case Solana(recentBlockHash: String)
}

struct KeysignPayload: Codable, Hashable {
    let coin: Coin
    // only toAddress is required , from Address is our own address
    let toAddress: String
    let toAmount: Int64
    let chainSpecific: BlockChainSpecific

    // for UTXO chains , often it need to sign multiple UTXOs at the same time
    // here when keysign , the main device will only pass the utxo info to the keysign device
    // it is up to the signing device to get the presign keyhash , and sign it with the main device
    let utxos: [UtxoInfo]
    let memo: String? // optional memo
    let swapPayload: THORChainSwapPayload?

    func getKeysignMessages() -> Result<[String], Error> {
        var result: Result<[String], Error>
        // this is a swap
        if swapPayload != nil {
            return THORChainSwaps.getPreSignedImageHash(keysignPayload: self)
        }
        switch coin.ticker {
        case "BTC":
            result = BitcoinHelper.getPreSignedImageHash(keysignPayload: self)
        case "BCH":
            result = BitcoinCashHelper.getPreSignedImageHash(keysignPayload: self)
        case "LTC":
            result = LitecoinHelper.getPreSignedImageHash(keysignPayload: self)
        case "ETH":
            result = EthereumHelper.getPreSignedImageHash(keysignPayload: self)
        case "USDC":
            result = ERC20Helper.getPreSignedImageHash(keysignPayload: self)
        case "RUNE":
            result = THORChainHelper.getPreSignedImageHash(keysignPayload: self)
        case "SOL":
            result = SolanaHelper.getPreSignedImageHash(keysignPayload: self)
        default:
            return .failure(HelperError.runtimeError("unsupported coin"))
        }
        return result
    }
}
