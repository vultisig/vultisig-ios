//
//  eth.swift
//  VoltixApp
//

import BigInt
import Foundation
import Tss
import WalletCore

enum EthereumHelper {
    static let weiPerGWei: Int64 = 1_000_000_000
    static func getEthereum(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).map { addr in
            Coin(chain: Chain.Ethereum,
                 ticker: "ETH",
                 logo: "",
                 address: addr)
        }
    }

    static func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: CoinType.ethereum.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        guard let pubKeyData = Data(hexString: derivePubKey), let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
            return .failure(HelperError.runtimeError("public key: \(derivePubKey) is invalid"))
        }
        return .success(CoinType.ethereum.deriveAddressFromPublicKey(publicKey: publicKey))
    }

    // this method convert GWei to Wei, and in little endian encoded Data
    static func convertEthereumNumber(input: Int64) -> Data {
        let inputInt = BigInt(input * weiPerGWei).magnitude.serialize()
        return inputInt
    }

    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "ETH" else {
            return .failure(HelperError.runtimeError("coin is not ETH"))
        }
        let coin = CoinType.ethereum
        guard let intChainID = Int(coin.chainId) else {
            return .failure(HelperError.runtimeError("fail to get chainID"))
        }
        guard case .Ethereum(let maxFeePerGasGWei,
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
            $0.maxFeePerGas = convertEthereumNumber(input: maxFeePerGasGWei)
            $0.maxInclusionFeePerGas = convertEthereumNumber(input: priorityFeeGWei)
            $0.toAddress = keysignPayload.toAddress
            $0.txMode = .enveloped
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = convertEthereumNumber(input: keysignPayload.toAmount)
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

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([preSigningOutput.dataHash.hexString])
            } catch {
                return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    static func getSignedTransaction(vaultHexPubKey: String,
                                     vaultHexChainCode: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) -> Result<String, Error>
    {
        let ethPublicKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: vaultHexPubKey, hexChainCode: vaultHexChainCode, derivePath: CoinType.ethereum.derivationPath())
        guard let pubkeyData = Data(hexString: ethPublicKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(ethPublicKey) is invalid"))
        }
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: inputData)
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
                let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .ethereum,
                                                                                     txInputData: inputData,
                                                                                     signatures: allSignatures,
                                                                                     publicKeys: publicKeys)
                let output = try EthereumSigningOutput(serializedData: compileWithSignature)
                return .success(output.encoded.hexString)
            } catch {
                return .failure(HelperError.runtimeError("fail to get signed ethereum transaction,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
}
