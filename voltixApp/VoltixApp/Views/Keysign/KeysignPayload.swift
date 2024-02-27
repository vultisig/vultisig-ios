//
//  KeysignPayload.swift
//  VoltixApp
//

import Foundation

struct KeysignMessage: Codable, Hashable {
    let sessionID: String
    let payload: KeysignPayload
}

enum BlockChainSpecific: Codable, Hashable {
    case Bitcoin(byteFee: Int64) // byteFee
    case Ethereum(maxFeePerGasGwei: Int64, priorityFeeGwei: Int64, nonce: Int64, gasLimit: Int64) // maxFeePerGasGwei, priorityFeeGwei, nonce , gasLimit
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

    func getKeysignMessages() -> Result<[String], Error> {
        switch self.coin.ticker {
        case "BTC":
            guard case .Bitcoin(let feeByte) = chainSpecific else {
                return .failure(HelperError.runtimeError("fail to get feeByte"))
            }
            let result = BitcoinHelper.getPreSignedImageHash(utxos: self.utxos,
                                                             fromAddress: self.coin.address,
                                                             toAddress: self.toAddress,
                                                             toAmount: self.toAmount,
                                                             byteFee: feeByte,
                                                             memo: self.memo)
            switch result {
            case .success(let preSignedImageHash):
                return.success(preSignedImageHash)
                
            case .failure(let err):
                return .failure(err)
            }
        case "ETH":
            guard case .Ethereum(let maxFeePerGasGWei, let priorityFeeGwei, let nonce, let gasLimit) = self.chainSpecific else {
                return .failure(HelperError.runtimeError("fail to get Ethereum chain specific"))
            }
            let result = EthereumHelper.getPreSignedImageHash(toAddress: self.toAddress,
                                                              toAmountGWei: self.toAmount,
                                                              nonce: nonce,
                                                              gasLimit: gasLimit,
                                                              maxFeePerGasGwei: maxFeePerGasGWei,
                                                              priorityFeeGwei: priorityFeeGwei,
                                                              memo: self.memo)
            switch result {
            case .success(let preSignedImageHash):
                return .success([preSignedImageHash])
               
            case .failure(let err):
                return .failure(err)
            }
        default:
            return .failure(HelperError.runtimeError("unsupported coin"))
        }
    }
}
