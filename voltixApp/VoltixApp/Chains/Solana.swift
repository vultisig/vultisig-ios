//
//  Solana.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore

enum SolanaHelper {
    static func getSolana(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).map { addr in
            Coin(chain: Chain.Solana,
                 ticker: "SOL",
                 logo: "",
                 address: addr,
                 hexPublicKey: hexPubKey,
                 feeUnit: "")
        }
    }

    static func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        // Solana is using EdDSA , so it doesn't need to use HD derive
        guard var pubKeyData = Data(hexString: hexPubKey) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        pubKeyData.reverse()
        guard let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        return .success(CoinType.solana.deriveAddressFromPublicKey(publicKey: publicKey))
    }

    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "SOL" else {
            return .failure(HelperError.runtimeError("coin is not SOL"))
        }
        guard case .Solana(let recentBlockHash) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .solana) else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }

        let input = SolanaSigningInput.with {
            $0.transferTransaction = SolanaTransfer.with {
                $0.recipient = toAddress.description
                $0.value = UInt64(keysignPayload.toAmount)
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
            }
            $0.recentBlockhash = recentBlockHash
            $0.sender = keysignPayload.coin.address
        }
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get PreSign input data"))
        }
    }

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                print("hash:\(preSigningOutput.dataHash.hexString)")
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
        guard var pubkeyData = Data(hexString: vaultHexPubKey) else {
            return .failure(HelperError.runtimeError("public key \(vaultHexPubKey) is invalid"))
        }
        pubkeyData.reverse()
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            return .failure(HelperError.runtimeError("public key \(vaultHexPubKey) is invalid"))
        }

        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                let allSignatures = DataVector()
                let publicKeys = DataVector()
                let signatureProvider = SignatureProvider(signatures: signatures)
                let signature = signatureProvider.getSignature(preHash: preSigningOutput.dataHash)
                print("signature: \(signature.hexString) , dataHash: \(preSigningOutput.dataHash.hexString) , public key: \(publicKey.data.hexString)")
                guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                    return .failure(HelperError.runtimeError("fail to verify signature"))
                }

                allSignatures.add(data: signature)
                let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .solana,
                                                                                     txInputData: inputData,
                                                                                     signatures: allSignatures,
                                                                                     publicKeys: publicKeys)
                let output = try EthereumSigningOutput(serializedData: compileWithSignature)
                return .success(output.encoded.hexString)
            } catch {
                return .failure(HelperError.runtimeError("fail to get signed solana transaction,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
}
