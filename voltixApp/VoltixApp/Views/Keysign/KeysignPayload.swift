//
//  KeysignPayload.swift
//  VoltixApp
//

import Foundation

struct KeysignMessage: Codable, Hashable {
    let sessionID: String
    let serviceName: String
    let payload: KeysignPayload
    let encryptionKeyHex: String
    let isPremium: Bool
}

enum BlockChainSpecific: Codable, Hashable {
    case UTXO(byteFee: Int64) // byteFee
    case Ethereum(maxFeePerGasGwei: Int64, priorityFeeGwei: Int64, nonce: Int64, gasLimit: Int64) // maxFeePerGasGwei, priorityFeeGwei, nonce , gasLimit
    case ERC20(maxFeePerGasGwei: Int64, priorityFeeGwei: Int64, nonce: Int64, gasLimit: Int64, contractAddr: String)
    case THORChain(accountNumber: UInt64, sequence: UInt64)
    case Cosmos(accountNumber: UInt64, sequence:UInt64, gas: UInt64)
    case Solana(recentBlockHash: String, priorityFee: UInt64, feeInLamports: String) // priority fee is in microlamports

    var gas: String {
        switch self {
        case .UTXO(let byteFee):
            return String(byteFee)
        case .Ethereum(let maxFeePerGasGwei, _, _, _):
            return String(maxFeePerGasGwei)
        case .ERC20(let maxFeePerGasGwei, _, _, _, _):
            return String(maxFeePerGasGwei)
        case .THORChain:
            return "0.02"
        case .Cosmos:
            return "0.0075"
        case .Solana(_, _, let feeInLamports):
            return feeInLamports
        }
    }
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

    var toAmountString: String {
        if(coin.chainType == .EVM){
            return "\(Decimal(toAmount) / Decimal(EVMHelper.weiPerGWei)) \(coin.ticker)"
        }
        return "\(Decimal(toAmount) / pow(10, Int(coin.decimals) ?? 0)) \(coin.ticker)"
    }
        
    func getKeysignMessages(vault: Vault) -> Result<[String], Error> {
        // this is a swap
        if swapPayload != nil {
            let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return swaps.getPreSignedImageHash(keysignPayload: self)
        }
        switch coin.chain {
        case .bitcoin:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case .bitcoinCash:
            let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case .litecoin:
            let utxoHelper = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case .dogecoin:
            let utxoHelper = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case .ethereum:
            if coin.isNativeToken {
                return EVMHelper.getEthereumHelper().getPreSignedImageHash(keysignPayload: self)
            }else{
                return ERC20Helper.getEthereumERC20Helper().getPreSignedImageHash(keysignPayload: self)
            }
        case .avalanche:
            if coin.isNativeToken {
                return EVMHelper.getAvaxHelper().getPreSignedImageHash(keysignPayload: self)
            } else {
                return ERC20Helper.getAvaxERC20Helper().getPreSignedImageHash(keysignPayload: self)
            }
        case .bscChain:
            if coin.isNativeToken {
                return EVMHelper.getBSCHelper().getPreSignedImageHash(keysignPayload: self)
            } else {
                return ERC20Helper.getBSCBEP20Helper().getPreSignedImageHash(keysignPayload: self)
            }
        case .thorChain:
            return THORChainHelper.getPreSignedImageHash(keysignPayload: self)
        case .solana:
            return SolanaHelper.getPreSignedImageHash(keysignPayload: self)
        case .gaiaChain:
            return ATOMHelper().getPreSignedImageHash(keysignPayload: self)
        }
    }
    
    static let example = KeysignPayload(coin: Coin.example, toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100), utxos: [], memo: "Memo", swapPayload: nil)
}
