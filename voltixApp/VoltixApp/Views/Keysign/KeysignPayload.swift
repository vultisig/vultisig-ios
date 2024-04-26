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
    case UTXO(byteFee: BigInt) // byteFee
    case Ethereum(maxFeePerGasWei: BigInt, priorityFeeWei: BigInt, nonce: Int64, gasLimit: BigInt) // maxFeePerGasWei, priorityFeeWei, nonce , gasLimit
    case THORChain(accountNumber: UInt64, sequence: UInt64)
    case Cosmos(accountNumber: UInt64, sequence: UInt64, gas: UInt64)
    case Solana(recentBlockHash: String, priorityFee: BigInt) // priority fee is in microlamports

    var gas: BigInt {
        switch self {
        case .UTXO(let byteFee):
            return byteFee
        case .Ethereum(let maxFeePerGas, _, _, _):
            return maxFeePerGas
        case .THORChain:
            return 2_000_000
        case .Cosmos:
            return 7500
        case .Solana:
            return SolanaHelper.defaultFeeInLamports
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
    let approvePayload: ERC20ApprovePayload?
    let vaultPubKeyECDSA: String

    init(coin: Coin, toAddress: String, toAmount: BigInt, chainSpecific: BlockChainSpecific, utxos: [UtxoInfo], memo: String?, swapPayload: THORChainSwapPayload?, approvePayload: ERC20ApprovePayload? = nil, vaultPubKeyECDSA: String = "") {
        self.coin = coin
        self.toAddress = toAddress
        self.toAmount = toAmount
        self.chainSpecific = chainSpecific
        self.utxos = utxos
        self.memo = memo
        self.swapPayload = swapPayload
        self.approvePayload = approvePayload
        self.vaultPubKeyECDSA = vaultPubKeyECDSA
    }

    var toAmountString: String {
        let decimalAmount = Decimal(string: toAmount.description) ?? Decimal.zero
        let power = Decimal(sign: .plus, exponent: -(Int(coin.decimals) ?? 0), significand: 1)
        return "\(decimalAmount * power) \(coin.ticker)"
    }

    func getKeysignMessages(vault: Vault) -> Result<[String], Error> {
        if let swapPayload {
            let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return swaps.getPreSignedImageHash(swapPayload: swapPayload, keysignPayload: self)
        }
        
        if let approvePayload {
            let swaps = THORChainSwaps(vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return swaps.getPreSignedApproveImageHash(approvePayload: approvePayload, keysignPayload: self)
        }

        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash:
            guard let coinType = CoinType.from(string: coin.chain.name.replacingOccurrences(of: "-", with: "")) else {
                print("Coin type not found on Wallet Core")
                return .failure("Coin type not found on Wallet Core" as! Error)
            }
            let utxoHelper = UTXOChainsHelper(coin: coinType, vaultHexPublicKey: vault.pubKeyECDSA, vaultHexChainCode: vault.hexChainCode)
            return utxoHelper.getPreSignedImageHash(keysignPayload: self)
        case .ethereum, .arbitrum, .base, .optimism, .polygon, .avalanche, .bscChain, .blast, .cronosChain:
            if coin.isNativeToken {
                let helper = EVMHelper.getHelper(coin: coin)
                return helper.getPreSignedImageHash(keysignPayload: self)
            } else {
                let helper = ERC20Helper.getHelper(coin: coin)
                return helper.getPreSignedImageHash(keysignPayload: self)
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
    
    static let example = KeysignPayload(coin: Coin.example, toAddress: "toAddress", toAmount: 100, chainSpecific: BlockChainSpecific.UTXO(byteFee: 100), utxos: [], memo: "Memo", swapPayload: nil, vaultPubKeyECDSA: "12345")
}
