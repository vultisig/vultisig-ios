//
//  KeysignPayload.swift
//  VoltixApp
//

import Foundation
import BigInt
import WalletCore

struct KeysignMessage: Codable, Hashable {
    let sessionID: String
    let serviceName: String
    let payload: KeysignPayload
    let encryptionKeyHex: String
    let useVoltixRelay: Bool
}

enum BlockChainSpecific: Codable, Hashable {
    case UTXO(byteFee: Int64) // byteFee
    case Ethereum(maxFeePerGasWei: Int64, priorityFeeGwei: Int64, nonce: Int64, gasLimit: Int64) // maxFeePerGasWei, priorityFeeGwei, nonce , gasLimit
    case ERC20(maxFeePerGasWei: Int64, priorityFeeGwei: Int64, nonce: Int64, gasLimit: Int64, contractAddr: String)
    case THORChain(accountNumber: UInt64, sequence: UInt64)
    case Cosmos(accountNumber: UInt64, sequence:UInt64, gas: UInt64)
    case Solana(recentBlockHash: String, priorityFee: UInt64, feeInLamports: String) // priority fee is in microlamports
    
    var gas: String {
        switch self {
        case .UTXO(let byteFee):
            return String(byteFee)
        case .Ethereum(let maxFeePerGasWei, _, _, _):
            return String(maxFeePerGasWei)
        case .ERC20(let maxFeePerGasWei, _, _, _, _):
            return String(maxFeePerGasWei)
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
    let toAmount: BigInt
    let chainSpecific: BlockChainSpecific
    
    // for UTXO chains , often it need to sign multiple UTXOs at the same time
    // here when keysign , the main device will only pass the utxo info to the keysign device
    // it is up to the signing device to get the presign keyhash , and sign it with the main device
    let utxos: [UtxoInfo]
    let memo: String? // optional memo
    let swapPayload: THORChainSwapPayload?
    
    var toAmountString: String {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal(0)
        
        if coin.chainType == .EVM {
            let divisor = Decimal(EVMHelper.weiPerGWei)
            return "\(decimalAmount / divisor) \(coin.ticker)"
        }
        let power = Decimal(sign: .plus, exponent: -(Int(coin.decimals) ?? 0), significand: 1)
        return "\(decimalAmount * power) \(coin.ticker)"
    }
    
    func getKeysignMessages(vault: Vault) -> Result<[String], Error> {
        if swapPayload != nil {
            let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return swaps.getPreSignedImageHash(keysignPayload: self)
        }
        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            guard let coinType = CoinType.from(string: coin.chain.name.replacingOccurrences(of: "-", with: "")) else {
                print("Coin type not found on Wallet Core")
                return .failure("Coin type not found on Wallet Core" as! Error)
            }
            let utxoHelper = UTXOChainsHelper(coin: coinType, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case .ethereum, .arbitrum, .base, .optimism, .polygon:
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
        case .mayaChain:
            return MayaChainHelper.getPreSignedImageHash(keysignPayload: self)
        case .solana:
            return SolanaHelper.getPreSignedImageHash(keysignPayload: self)
        case .gaiaChain:
            return ATOMHelper().getPreSignedImageHash(keysignPayload: self)
        case .kujira:
            return KujiraHelper().getPreSignedImageHash(keysignPayload: self)
        }
    }
    
    static let example = KeysignPayload(coin: Coin.example, toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100), utxos: [], memo: "Memo", swapPayload: nil)
}
