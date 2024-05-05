//
//  Polkadot.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore
import BigInt

enum PolkadotHelper {
    
    static let defaultFeeInPlancks: BigInt = 10_000_000_000 //1 DOT, polkadot deletes your account if less than 1 DOT and you lose your dust.
    
    static func getPolkadot(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).flatMap { addr -> Result<Coin, Error> in
            TokensStore.createNewCoinInstance(ticker: "DOT", address: addr, hexPublicKey: hexPubKey, coinType: .polkadot)
        }
    }
    
    static func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        // Polkadot is using EdDSA , so it doesn't need to use HD derive
        guard let pubKeyData = Data(hexString: hexPubKey) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        guard let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        return .success(CoinType.polkadot.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "DOT" else {
            return .failure(HelperError.runtimeError("coin is not DOT"))
        }
        
        guard case .Polkadot(let recentBlockHash, let nonce, let currentBlockNumber, let specVersion, let transactionVersion, let genesisHash) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("getPreSignedInputData fail to get DOT transaction information from RPC"))
        }
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .polkadot) else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        
        let genesisHashData = Data(hexString: genesisHash)!
        let input = PolkadotSigningInput.with {
            $0.genesisHash = genesisHashData
            $0.blockHash = Data(hexString: recentBlockHash)!
            $0.nonce = nonce
            $0.specVersion = specVersion
            $0.network = CoinType.polkadot.ss58Prefix
            $0.transactionVersion = transactionVersion
            $0.era = PolkadotEra.with {
                $0.blockNumber = UInt64(currentBlockNumber)
                $0.period = 64
            }
            $0.balanceCall.transfer = PolkadotBalance.Transfer.with {
                $0.toAddress = toAddress.description
                $0.value = keysignPayload.toAmount.magnitude.serialize()
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
            }
        }
                
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            print(error.localizedDescription)
            return .failure(HelperError.runtimeError("fail to get PreSign input data"))
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .polkadot, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success([preSigningOutput.data.hexString])
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
                                     signatures: [String: TssKeysignResponse]) -> Result<SignedTransactionResult, Error>
    {
        guard let pubkeyData = Data(hexString: vaultHexPubKey) else {
            return .failure(HelperError.runtimeError("public key \(vaultHexPubKey) is invalid"))
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .ed25519) else {
            return .failure(HelperError.runtimeError("public key \(vaultHexPubKey) is invalid"))
        }
        
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .polkadot, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                let allSignatures = DataVector()
                let publicKeys = DataVector()
                let signatureProvider = SignatureProvider(signatures: signatures)
                let signature = signatureProvider.getSignature(preHash: preSigningOutput.data)
                guard publicKey.verify(signature: signature, message: preSigningOutput.data) else {
                    return .failure(HelperError.runtimeError("fail to verify signature"))
                }
                
                allSignatures.add(data: signature)
                publicKeys.add(data: pubkeyData)
                let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .polkadot,
                                                                                     txInputData: inputData,
                                                                                     signatures: allSignatures,
                                                                                     publicKeys: publicKeys)
                let output = try PolkadotSigningOutput(serializedData: compileWithSignature)
                let transactionHash = Hash.blake2b(data: output.encoded, size: 32).toHexString()
                let result = SignedTransactionResult(rawTransaction: output.encoded.hexString,
                                                     transactionHash: transactionHash)
                return .success(result)
            } catch {
                return .failure(HelperError.runtimeError("fail to get signed polkadot transaction,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
}
