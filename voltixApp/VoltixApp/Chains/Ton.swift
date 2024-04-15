import Foundation
import Tss
import WalletCore

enum TONHelper {
    
    static func getTon(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPublicKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode).flatMap { addr -> Result<Coin, Error> in
            TokensStore.createNewCoinInstance(ticker: "TON", address: addr, hexPublicKey: hexPubKey)
        }
    }
    
    static func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        guard let pubKeyData = Data(hexString: hexPubKey) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        guard let publicKey = PublicKey(data: pubKeyData, type: .ed25519) else {
            return .failure(HelperError.runtimeError("public key: \(hexPubKey) is invalid"))
        }
        return .success(CoinType.ton.deriveAddressFromPublicKey(publicKey: publicKey))
    }
    
    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "TON" else {
            return .failure(HelperError.runtimeError("coin is not TON"))
        }
        
        guard case .Ton(let sequence) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get the sequence"))
        }
        
        guard let toAddress = AnyAddress(string: keysignPayload.toAddress, coin: .ton) else {
            return .failure(HelperError.runtimeError("fail to get to address"))
        }
        
        
        let input = TheOpenNetworkSigningInput.with {
            $0.transfer = TheOpenNetworkTransfer.with {
                $0.dest = keysignPayload.toAddress
                $0.amount = UInt64(keysignPayload.toAmount)
                $0.comment = keysignPayload.memo ?? ""
                $0.walletVersion = .walletV3R2
                $0.bounceable = true
                $0.sequenceNumber = sequence  // Update this based on your use case
            }
        }
        
        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get PreSign input data, error: \(error.localizedDescription)"))
        }
    }
    
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) -> Result<[String], Error> {
        let result = getPreSignedInputData(keysignPayload: keysignPayload)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .ton, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                print("hash:\(preSigningOutput.data.hexString)")
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
                                     signatures: [String: TssKeysignResponse]) -> Result<String, Error>
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
                let hashes = TransactionCompiler.preImageHashes(coinType: .solana, txInputData: inputData)
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
                let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .solana,
                                                                                     txInputData: inputData,
                                                                                     signatures: allSignatures,
                                                                                     publicKeys: publicKeys)
                let output = try SolanaSigningOutput(serializedData: compileWithSignature)
                return .success(output.encoded)
            } catch {
                return .failure(HelperError.runtimeError("fail to get signed solana transaction,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }
}
