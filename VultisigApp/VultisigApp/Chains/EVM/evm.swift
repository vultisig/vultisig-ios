//
//  eth.swift
//  VultisigApp
//

import BigInt
import Foundation
import Tss
import WalletCore
import CryptoSwift

class EVMHelper {
    static let defaultETHTransferGasUnit:Int64 = 23000 // Increased to 23000 to support swaps and transfers with memo
    static let defaultETHSwapGasUnit:Int64 = 600000
    static let defaultERC20TransferGasUnit:Int64 = 120000
    static let weiPerGWei: Int64 = 1_000_000_000
    static let wei: Int64 = 1_000_000_000_000_000_000
    
    static let ethDecimals = 18
    let coinType: CoinType
    
    init(coinType: CoinType) {
        self.coinType = coinType
    }
    
    static func getHelper(coin: Coin) -> EVMHelper {
        return EVMHelper(coinType: coin.coinType)
    }
    
    func getChainId(chain: Chain) -> String {
        switch chain {
        case .ethereumSepolia:
            return "11155111"
        case .hyperliquid:
            return "999"
        case .sei:
            return "1329"
        default:
            return self.coinType.chainId
        }
    }
    
    private func setGasParameters(
        input: inout EthereumSigningInput,
        chain: Chain,
        gas: BigUInt?,
        gasPrice: BigUInt?,
        gasLimit: BigInt,
        maxFeePerGasWei: BigInt,
        priorityFeeWei: BigInt
    ) {
        // BSC doesn't support EIP-1559, use legacy transaction
        if chain == .bscChain {
            input.txMode = .legacy
            if let gas, let gasPrice {
                input.gasLimit = gas.serialize()
                input.gasPrice = gasPrice.serialize()
            } else {
                input.gasLimit = gasLimit.magnitude.serialize()
                input.gasPrice = maxFeePerGasWei.magnitude.serialize()
            }
        } else {
            input.txMode = .enveloped
            if let gas, let gasPrice {
                input.gasLimit = gas.serialize()
                input.maxFeePerGas = gasPrice.serialize()
                input.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
            } else {
                input.gasLimit = gasLimit.magnitude.serialize()
                input.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
                input.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
            }
        }
    }
    
    private func configureGasForChain(
        _ input: inout EthereumSigningInput,
        chain: Chain,
        gasLimit: BigInt,
        maxFeePerGasWei: BigInt,
        priorityFeeWei: BigInt
    ) {
        input.gasLimit = gasLimit.magnitude.serialize()
        // BSC doesn't support EIP-1559, use legacy transaction
        if chain == .bscChain {
            input.txMode = .legacy
            input.gasPrice = maxFeePerGasWei.magnitude.serialize()
        } else {
            input.txMode = .enveloped
            input.maxFeePerGas = maxFeePerGasWei.magnitude.serialize()
            input.maxInclusionFeePerGas = priorityFeeWei.magnitude.serialize()
        }
    }
    
    func getPreSignedInputData(
        signingInput: EthereumSigningInput,
        keysignPayload: KeysignPayload,
        gas: BigUInt? = nil,
        gasPrice: BigUInt? = nil,
        incrementNonce: Bool = false) throws -> Data
    {
        guard let intChainID = Int(getChainId(chain: keysignPayload.coin.chain)) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        
        guard case .Ethereum(
            let maxFeePerGasWei,
            let priorityFeeWei,
            let nonce,
            let gasLimit
        ) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }
        
        let incrementNonceValue: Int64 = incrementNonce ? 1 : 0
        
        var input = signingInput
        input.chainID = Data(hexString: Int64(intChainID).hexString())!
        input.nonce = Data(hexString: (nonce + incrementNonceValue).hexString())!
        
        setGasParameters(
            input: &input,
            chain: keysignPayload.coin.chain,
            gas: gas,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            maxFeePerGasWei: maxFeePerGasWei,
            priorityFeeWei: priorityFeeWei
        )
        
        return try input.serializedData()
    }
    
    // method to get thorchain swap payload
    func getSwapPreSignedInputData(
        keysignPayload: KeysignPayload,
        gas: BigUInt? = nil,
        gasPrice: BigUInt? = nil,
        incrementNonce: Bool = false) throws -> Data
    {
        guard let intChainID = Int(getChainId(chain: keysignPayload.coin.chain)) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        
        guard let swapPayload = keysignPayload.swapPayload else {
            throw HelperError.runtimeError("swap payload is nil")
        }
        var thorChainSwapPayload: THORChainSwapPayload? = nil
        switch swapPayload {
        case .thorchain(let payload), .thorchainStagenet(let payload), .mayachain(let payload):
            thorChainSwapPayload = payload
        default:
            throw HelperError.runtimeError("fail to get swap payload")
        }
        guard let thorChainSwapPayload else {
            throw HelperError.runtimeError("fail to get swap payload")
        }
        guard let memo = keysignPayload.memo else {
            throw HelperError.runtimeError("memo is nil")
        }

        guard case .Ethereum(
            let maxFeePerGasWei,
            let priorityFeeWei,
            let nonce,
            let gasLimit
        ) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }

        let incrementNonceValue: Int64 = incrementNonce ? 1 : 0

        var input = EthereumSigningInput.with {
            $0.chainID = Data(hexString: Int64(intChainID).hexString())!
            $0.nonce = Data(hexString: (nonce + incrementNonceValue).hexString())!
            $0.toAddress = thorChainSwapPayload.toAddress
           
        }
        
        if swapPayload.fromCoin.isNativeToken {
            input.toAddress = thorChainSwapPayload.vaultAddress
            // send to asgard
            input.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = thorChainSwapPayload.fromAmount.serializeForEvm()
                    $0.data = Data(memo.utf8)
                }
            }
        } else {
            guard let routerAddress = thorChainSwapPayload.routerAddress else {
                throw HelperError.runtimeError("router address is nil")
            }
            input.toAddress = routerAddress
            let f = EthereumAbiFunction(name: "depositWithExpiry")
            guard let vaultAddr = AnyAddress(string: thorChainSwapPayload.vaultAddress, coin: .ethereum) else{
                throw HelperError.runtimeError("invalid vault address")
            }
            guard let contractAddress = AnyAddress(string: thorChainSwapPayload.fromCoin.contractAddress, coin: .ethereum) else {
                throw HelperError.runtimeError("invalid contract address")
            }
            f.addParamAddress(val: vaultAddr.data, isOutput: false)
            f.addParamAddress(val: contractAddress.data, isOutput: false)
            f.addParamUInt256(val: thorChainSwapPayload.fromAmount.serializeForEvm(), isOutput: false)
            f.addParamString(val: memo, isOutput: false)
            f.addParamUInt256(val: BigInt(thorChainSwapPayload.expirationTime).serializeForEvm(), isOutput: false)
            let abiData = EthereumAbi.encode(fn: f)
            input.transaction = EthereumTransaction.with {
                $0.contractGeneric =  EthereumTransaction.ContractGeneric.with {
                    $0.amount = BigInt.zero.serializeForEvm()
                    $0.data = abiData
                }
            }
        }
        
        setGasParameters(
            input: &input,
            chain: keysignPayload.coin.chain,
            gas: gas,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            maxFeePerGasWei: maxFeePerGasWei,
            priorityFeeWei: priorityFeeWei
        )

        return try input.serializedData()
    }
        
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) throws -> Data {
        guard let intChainID = Int(getChainId(chain: keysignPayload.coin.chain)) else {
            throw HelperError.runtimeError("fail to get chainID")
        }
        guard case .Ethereum(let maxFeePerGasWei,
                             let priorityFeeWei,
                             let nonce,
                             let gasLimit) = keysignPayload.chainSpecific
        else {
            throw HelperError.runtimeError("fail to get Ethereum chain specific")
        }
        var input = EthereumSigningInput.with {
            $0.chainID = Data(hexString: Int64(intChainID).hexString())!
            $0.nonce = Data(hexString: nonce.hexString())!
            $0.toAddress = keysignPayload.toAddress
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = keysignPayload.toAmount.serializeForEvm()
                    if let memo = keysignPayload.memo {
                        if memo.hasPrefix("0x") {
                            // if memo start with 0x , meaning it is hex encoded string , then let's hex decode it first
                            $0.data = Data(hex: memo)
                        } else {
                            $0.data = Data(memo.utf8)
                        }
                    }
                }
            }
        }
        
        configureGasForChain(
            &input,
            chain: keysignPayload.coin.chain,
            gasLimit: gasLimit,
            maxFeePerGasWei: maxFeePerGasWei,
            priorityFeeWei: priorityFeeWei
        )
        return try input.serializedData()
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }
    
    func getSignedTransaction(keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        let inputData = try getPreSignedInputData(keysignPayload: keysignPayload)
        let signedTransaction = try getSignedTransaction(ethPublicKey: keysignPayload.coin.hexPublicKey, inputData: inputData, signatures: signatures)
        return signedTransaction
    }
    
    func getSignedTransaction(ethPublicKey: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult
    {
        guard let pubkeyData = Data(hexString: ethPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw HelperError.runtimeError("public key \(ethPublicKey) is invalid")
        }

        let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        
        // Validate preSigningOutput before using it to prevent null pointer crashes
        guard preSigningOutput.error == .ok else {
            throw HelperError.runtimeError("preSigningOutput error: \(preSigningOutput.errorMessage)")
        }
        
        guard !preSigningOutput.dataHash.isEmpty else {
            throw HelperError.runtimeError("preSigningOutput.dataHash is empty")
        }
        
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
        
        // Validate signature before passing to WalletCore
        guard !signature.isEmpty else {
            throw HelperError.runtimeError("signature is empty after recovery ID calculation")
        }
        
        guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
            throw HelperError.runtimeError("fail to verify signature")
        }

        allSignatures.add(data: signature)

        // it looks like the pubkey compileWithSignature accept is extended public key
        // also , it can be empty as well , since we don't have extended public key , so just leave it empty
        let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                             txInputData: inputData,
                                                                             signatures: allSignatures,
                                                                             publicKeys: publicKeys)
        let output = try EthereumSigningOutput(serializedBytes: compileWithSignature)
        let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                             transactionHash: "0x"+output.encoded.sha3(.keccak256).toHexString())
        return result
    }
}
