//
//  eth.swift
//  VoltixApp
//

import BigInt
import Foundation
import Tss
import WalletCore

class EVMHelper {
    static let defaultETHTransferGasUnit:Int64 = 23000 // Increased to 23000 to support swaps and transfers with memo
    static let defaultERC20TransferGasUnit:Int64 = 120000
    static let weiPerGWei: Int64 = 1_000_000_000
    static let wei: Int64 = 1_000_000_000_000_000_000
    
    static let ethDecimals = 18
    let coinType: CoinType
    
    init(coinType: CoinType) {
        self.coinType = coinType
    }
    
    static func getEthereumHelper() -> EVMHelper{
        return EVMHelper(coinType: CoinType.ethereum)
    }
    static func getAvaxHelper() -> EVMHelper{
        return EVMHelper(coinType: CoinType.avalancheCChain)
    }
    static func getBSCHelper() -> EVMHelper{
        return EVMHelper(coinType: CoinType.smartChain)
    }
    func getCoin(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: coinType.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).flatMap { addr -> Result<Coin, Error> in
            var ticker = ""
            switch self.coinType{
            case .ethereum:
                ticker = "ETH"
            case .avalancheCChain:
                ticker = "AVAX"
            case .smartChain:
                ticker = "BNB"
            default:
                ticker = ""
            }
            return TokensStore.createNewCoinInstance(ticker:ticker, address: addr, hexPublicKey: derivePubKey)
        }
    }
    
    func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: coinType.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        guard let pubKeyData = Data(hexString: derivePubKey), let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
            return .failure(HelperError.runtimeError("public key: \(derivePubKey) is invalid"))
        }
        return .success(coinType.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    // this method convert GWei to Wei, and in little endian encoded Data
    static func convertEthereumNumber(input: BigInt) -> Data {
        return input.magnitude.serialize()
    }
    
    func getPreSignedInputData(signingInput: EthereumSigningInput, keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let coin = self.coinType
        guard let intChainID = Int(coin.chainId) else {
            return .failure(HelperError.runtimeError("fail to get chainID"))
        }
        guard case .Ethereum(let maxFeePerGasWei,
                             let priorityFeeGWei,
                             let nonce,
                             let gasLimit) = keysignPayload.chainSpecific
        else {
            return .failure(HelperError.runtimeError("fail to get Ethereum chain specific"))
        }
        var input = signingInput
        input.chainID = Data(hexString: Int64(intChainID).hexString())!
        input.nonce = Data(hexString: nonce.hexString())!
        input.gasLimit = Data(hexString: gasLimit.hexString())!
        input.maxFeePerGas = EVMHelper.convertEthereumNumber(input: BigInt(maxFeePerGasWei))
        input.maxInclusionFeePerGas = EVMHelper.convertEthereumNumber(input: BigInt(priorityFeeGWei))
        input.txMode = .enveloped

        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let coin = self.coinType
        guard let intChainID = Int(coin.chainId) else {
            return .failure(HelperError.runtimeError("fail to get chainID"))
        }
        guard case .Ethereum(let maxFeePerGasWei,
                             let priorityFeeGWei,
                             let nonce,
                             let gasLimit) = keysignPayload.chainSpecific
        else {
            return .failure(HelperError.runtimeError("fail to get Ethereum chain specific"))
        }
        let input = EthereumSigningInput.with {
            $0.chainID = Data(hexString: Int64(intChainID).hexString())!
            $0.nonce = Data(hexString: nonce.hexString())!
            $0.gasLimit = Data(hexString: gasLimit.hexString())!
            $0.maxFeePerGas = EVMHelper.convertEthereumNumber(input: BigInt(maxFeePerGasWei))
            $0.maxInclusionFeePerGas = EVMHelper.convertEthereumNumber(input: BigInt(priorityFeeGWei))
            $0.toAddress = keysignPayload.toAddress
            $0.txMode = .enveloped
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = EVMHelper.convertEthereumNumber(input: keysignPayload.toAmount)
                    if let memo = keysignPayload.memo {
                        $0.data = Data(memo.utf8)
                    }
                }
            }
        }
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
    
    func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([preSigningOutput.dataHash.hexString])
            } catch {
                return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              keysignPayload: KeysignPayload,
                              signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            return getSignedTransaction(vaultHexPubKey: vaultHexPubKey, vaultHexChainCode: vaultHexChainCode, inputData: inputData, signatures: signatures)
        case .failure(let err):
            return .failure(err)
        }
    }
    
    func getSignedTransaction(vaultHexPubKey: String,
                              vaultHexChainCode: String,
                              inputData: Data,
                              signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let ethPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: self.coinType.derivationPath())
        guard let pubkeyData = Data(hexString: ethPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(ethPublicKey) is invalid"))
        }
        
        do {
            let hashes = TransactionCompiler.preImageHashes(coinType: self.coinType, txInputData: inputData)
            let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
            let allSignatures = DataVector()
            let publicKeys = DataVector()
            let signatureProvider = SignatureProvider(signatures: signatures)
            let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
            guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                return .failure(HelperError.runtimeError("fail to verify signature"))
            }
            
            allSignatures.add(data: signature)
            
            // it looks like the pubkey compileWithSignature accept is extended public key
            // also , it can be empty as well , since we don't have extended public key , so just leave it empty
            let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: self.coinType,
                                                                                 txInputData: inputData,
                                                                                 signatures: allSignatures,
                                                                                 publicKeys: publicKeys)
            let output = try EthereumSigningOutput(serializedData: compileWithSignature)
            return .success(output.encoded.hexString)
        } catch {
            return .failure(HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)"))
        }
    }
}
