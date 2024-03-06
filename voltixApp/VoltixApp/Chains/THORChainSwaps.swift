//
//  THORChainSwaps.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore

enum THORChainSwaps {
    static let affiliateFeeAddress = ""
    static func getPreSignedInputData(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload) -> Result<Data, Error> {
        let input = THORChainSwapSwapInput.with {
            $0.fromAsset = swapPayload.fromAsset
            $0.fromAddress = swapPayload.fromAddress
            $0.toAsset = swapPayload.toAsset
            $0.toAddress = swapPayload.toAddress
            $0.vaultAddress = swapPayload.vaultAddress
            $0.fromAmount = swapPayload.fromAmount
            $0.toAmountLimit = swapPayload.toAmountLimit
            $0.affiliateFeeAddress = THORChainSwaps.affiliateFeeAddress
        }
        do {
            let inputData = try input.serializedData()
            let outputData = THORChainSwap.buildSwap(input: inputData)
            let output = try THORChainSwapSwapOutput(serializedData: outputData)
            switch swapPayload.fromAsset.chain {
            case .thor:
                return THORChainHelper.getSwapPreSignedInputData(keysignPayload: keysignPayload, signingInput: output.cosmos)
            case .btc:
                return BitcoinHelper.getSigningInputData(keysignPayload: keysignPayload, signingInput: output.bitcoin)
            case .eth:
                return EthereumHelper.getPreSignedInputData(signingInput: output.ethereum, keysignPayload: keysignPayload)
            default:
                return .failure(HelperError.runtimeError("not support yet"))
            }
        } catch {
            return .failure(error)
        }
    }

    static func getPreSignedImageHash(swapPayload: THORChainSwapPayload, keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload)
        do {
            switch result {
            case .success(let inputData):
                switch swapPayload.fromAsset.chain {
                case .thor:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    return .success([preSigningOutput.dataHash.hexString])
                case .btc:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .thorchain, txInputData: inputData)
                    let preSigningOutput = try BitcoinPreSigningOutput(serializedData: hashes)
                    return .success(preSigningOutput.hashPublicKeys.map { $0.dataHash.hexString })
                case .eth:
                    let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    return .success([preSigningOutput.dataHash.hexString])

                default:
                    return .failure(HelperError.runtimeError("not support yet"))
                }
            case .failure(let err):
                return .failure(err)
            }

        } catch {
            return .failure(error)
        }
    }

    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     swapPayload: THORChainSwapPayload,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let result = getPreSignedInputData(swapPayload: swapPayload, keysignPayload: keysignPayload)
        do {
            var coin = swapPayload.fromAsset.chain.getCoinType()
            guard let coin else {
                return .failure(HelperError.runtimeError("coin type is invalid"))
            }
            let publicKeyData = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: coin.derivationPath())
            guard let pubkeyData = Data(hexString: publicKeyData),
                  let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
            else {
                return .failure(HelperError.runtimeError("public key \(publicKeyData) is invalid"))
            }
            switch result {
            case .success(let inputData):
                switch swapPayload.fromAsset.chain {
                case .thor:
                    let hashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
                    let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                    let allSignatures = DataVector()
                    let publicKeys = DataVector()
                    let signatureProvider = SignatureProvider(signatures: signatures)
                    let signature = signatureProvider.getSignatureWithRecoveryID(preHash: preSigningOutput.dataHash)
                    guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                        return .failure(HelperError.runtimeError("fail to verify signature"))
                    }

                    allSignatures.add(data: signature)
                    publicKeys.add(data: pubkeyData)
                    let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: coin,
                                                                                         txInputData: inputData,
                                                                                         signatures: allSignatures,
                                                                                         publicKeys: publicKeys)
                    let output = try CosmosSigningOutput(serializedData: compileWithSignature)
                    let serializedData = output.serialized
                    print(serializedData)
                    return .success(serializedData)
                case .btc:
                    let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: inputData)
                    let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)
                    let allSignatures = DataVector()
                    let publicKeys = DataVector()
                    let signatureProvider = SignatureProvider(signatures: signatures)
                    for h in preSignOutputs.hashPublicKeys {
                        let preImageHash = h.dataHash
                        let signature = signatureProvider.getDerSignature(preHash: preImageHash)
                        guard publicKey.verifyAsDER(signature: signature, message: preImageHash) else {
                            return .failure(HelperError.runtimeError("fail to verify signature"))
                        }
                        allSignatures.add(data: signature)
                        publicKeys.add(data: pubkeyData)
                    }
                    let compileWithSignatures = TransactionCompiler.compileWithSignatures(coinType: coin, txInputData: inputData, signatures: allSignatures, publicKeys: publicKeys)
                    let output = try BitcoinSigningOutput(serializedData: compileWithSignatures)
                    return .success(output.encoded.hexString)
                case .eth:
                    let hashes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: inputData)
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
                    let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: coin,
                                                                                         txInputData: inputData,
                                                                                         signatures: allSignatures,
                                                                                         publicKeys: publicKeys)
                    let output = try EthereumSigningOutput(serializedData: compileWithSignature)
                    return .success(output.encoded.hexString)
                default:
                    return .failure(HelperError.runtimeError("not support"))
                }
            case .failure(let err):
                return .failure(err)
            }
        } catch {
            return .failure(HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)"))
        }
    }
}
