//
//  Polkadot.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore
import BigInt

enum PolkadotHelper {
    
    static let defaultFeeInPlancks: BigInt = 200000000 //0.02
    
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
        
        guard case .Polkadot(let recentBlockHash, let nonce, let currentBlockNumber, let specVersion, let transactionVersion) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .polkadot) else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        
        let genesisHash = Data(hexString: "0x91b171bb158e2d3848fa23a9f1c25182fb8e20313b2c1eb49219da7a70ce90c3")!
        
        let input = PolkadotSigningInput.with {
            $0.genesisHash = genesisHash
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
                //$0.value = keysignPayload.toAmount.serializeForEvm()
                $0.value = Data(hexString: "0x02540be400")! // 1 DOT
                if let memo = keysignPayload.memo {
                    $0.memo = memo
                }
            }
        }
        
        print("Genesis Hash:", genesisHash.map { String(format: "%02x", $0) }.joined())
        print("Block Hash:", recentBlockHash)
        print("Nonce:", nonce)
        print("Spec Version:", input.specVersion)
        print("Network:", input.network.description)
        print("Transaction Version:", input.transactionVersion)
        print("Era Block Number:", input.era.blockNumber)
        print("Era Period:", input.era.period)
        print("To Address:", toAddress)
        print("Value in DOT:", "1 DOT (Hex: 0x02540be400)")
        print("Memo:", keysignPayload.memo ?? "No memo")
        print("Serialized toAmount for EVM:", keysignPayload.toAmount.serializeForEvm().map { String(format: "%02x", $0) }.joined())
        print("Original BigInt toAmount:", keysignPayload.toAmount)
        print("Complete PolkadotSigningInput:", input.debugDescription)
        
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
                print("hash:\(preSigningOutput.data.hexString)")
                print("error presing POLKADOT:\(preSigningOutput.errorMessage)")
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
                print("error presing POLKADOT:\(preSigningOutput.errorMessage)")
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
                
                
                print("getSignedTransaction > output", output.debugDescription)
                print("getSignedTransaction > output.errorMessage", output.errorMessage)
                
                let transactionHash = Hash.blake2b(data: output.encoded, size: 32).toHexString()
                
                print("getSignedTransaction > transactionHash", transactionHash)
                print("getSignedTransaction > output.encoded.hexString", output.encoded.hexString)
                
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
