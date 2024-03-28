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
    case UTXO(byteFee: Int64) // byteFee
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
    
    var toAmountString: String {
        if(coin.chainType == .EVM){
            return "\(Decimal(toAmount) / Decimal(EVMHelper.weiPerGWei)) \(coin.ticker)"
        }
        return "\(Decimal(toAmount) / pow(10, Int(coin.decimals) ?? 0)) \(coin.ticker)"
    }
        
    func getKeysignMessages(vault:Vault) -> Result<[String], Error> {
        var result: Result<[String], Error>
        // this is a swap
        if swapPayload != nil {
            let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return swaps.getPreSignedImageHash(keysignPayload: self)
        }
        switch coin.chain.name.lowercased() {
        case Chain.Bitcoin.name.lowercased():
            let utxoHelper = UTXOChainsHelper(coin: .bitcoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case Chain.BitcoinCash.name.lowercased():
            let utxoHelper = UTXOChainsHelper(coin: .bitcoinCash, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case Chain.Litecoin.name.lowercased():
            let utxoHelper = UTXOChainsHelper(coin: .litecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case Chain.Dogecoin.name.lowercased():
            let utxoHelper = UTXOChainsHelper(coin: .dogecoin, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case Chain.Ethereum.name.lowercased():
            if coin.isNativeToken {
                result = EVMHelper.getEthereumHelper().getPreSignedImageHash(keysignPayload: self)
            }else{
                result = ERC20Helper.getEthereumERC20Helper().getPreSignedImageHash(keysignPayload: self)
            }
        case Chain.BSCChain.name.lowercased():
            if coin.isNativeToken {
                result = EVMHelper.getBSCHelper().getPreSignedImageHash(keysignPayload: self)
            }else{
                result = ERC20Helper.getBSCBEP20Helper().getPreSignedImageHash(keysignPayload: self)
            }
        case Chain.THORChain.name.lowercased():
            result = THORChainHelper.getPreSignedImageHash(keysignPayload: self)
        case Chain.Solana.name.lowercased():
            result = SolanaHelper.getPreSignedImageHash(keysignPayload: self)
        default:
            return .failure(HelperError.runtimeError("unsupported coin"))
        }
        return result
    }
    
    static let example = KeysignPayload(coin: Coin.example, toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100), utxos: [], memo: "Memo", swapPayload: nil)
}
