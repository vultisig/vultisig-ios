//
//  bitcoin.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore

struct UtxoInfo {
    let hash: String
    let amount: Int64
    let index: UInt32
}

struct BitcoinHelper {
    enum BitcoinTransactionError: String, Error {
        case invalidPubKey = "invalid public key"
        case failToGetKeyHash = "fail to get key hash"
        case invalidSignature = "Signature is invalid"
    }

    static func getBitcoin(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        let result = getAddressFromPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode)
        switch result {
        case .failure(let err):
            return .failure(err)
        case .success(let addr):
            return .success(Coin(chain: Chain.Bitcoin, symbol: "btc", logo: "", address: addr))
        }
    }

    static func getAddressFromPubKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        var nsErr: NSError?
        let derivedPubKey = TssGetDerivedPubKey(hexPubKey, hexChainCode, CoinType.bitcoin.derivationPath(), false, &nsErr)
        guard let pubkeyData = Data(hexString: derivedPubKey) else {
            return .failure(BitcoinTransactionError.invalidPubKey)
        }

        guard let publicKey = PublicKey(data: pubkeyData, type: .secp256k1) else {
            return .failure(BitcoinTransactionError.invalidPubKey)
        }
        return .success(CoinType.bitcoin.deriveAddressFromPublicKey(publicKey: publicKey))
    }

    private func getSignedBitcoinTransaction(utxos: [UtxoInfo],
                                             hexPubKey: String,
                                             fromAddress: String,
                                             toAddress: String,
                                             toAmount: Int64,
                                             signatureProvider: (Data) -> Data) -> Result<String, Error>
    {
        guard let pubkeyData = Data(hexString: hexPubKey) else {
            return .failure(BitcoinTransactionError.invalidPubKey)
        }
        guard let publicKey = PublicKey(data: pubkeyData, type: .secp256k1) else {
            return .failure(BitcoinTransactionError.invalidPubKey)
        }
        do {
            let coin = CoinType.bitcoin
            var input = BitcoinSigningInput.with {
                $0.hashType = BitcoinSigHashType.all.rawValue
                $0.amount = toAmount
                $0.toAddress = toAddress
                $0.changeAddress = fromAddress
                $0.coinType = coin.rawValue
                $0.scripts = [String: Data]()
            }
            for inputUtxo in utxos {
                let lockScript = BitcoinScript.lockScriptForAddress(address: fromAddress, coin: .bitcoin)
                print("lock script: \(lockScript.scriptHash.hexString)")
                let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
                guard let keyHash else {
                    return .failure(BitcoinTransactionError.failToGetKeyHash)
                }
                let redeemScript = BitcoinScript.buildPayToPublicKeyHash(hash: keyHash)
                input.scripts[keyHash.hexString] = redeemScript.data
                let utxo = BitcoinUnspentTransaction.with {
                    $0.outPoint = BitcoinOutPoint.with {
                        $0.hash = Data(hexString: inputUtxo.hash)!
                        $0.index = inputUtxo.index
                        $0.sequence = UInt32.max
                    }
                    $0.amount = inputUtxo.amount
                    $0.script = lockScript.data
                }
                input.utxo.append(utxo)
            }

            let inputData = try input.serializedData()
            let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: inputData)
            let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)

            let allSignatures = DataVector()
            let publicKeys = DataVector()

            for h in preSignOutputs.hashPublicKeys {
                let preImageHash = h.dataHash
                let signature = signatureProvider(preImageHash)
                if !publicKey.verifyAsDER(signature: signature, message: preImageHash) {
                    return .failure(BitcoinTransactionError.invalidSignature)
                }
                allSignatures.add(data: signature)
                publicKeys.add(data: pubkeyData)
            }
            let compileWithSignatures = TransactionCompiler.compileWithSignatures(coinType: .bitcoin, txInputData: inputData, signatures: allSignatures, publicKeys: publicKeys)
            let output = try BitcoinSigningOutput(serializedData: compileWithSignatures)
            return .success(output.encoded.hexString)
        } catch {
            print("fail to construct transaction,err:\(error)")
            return .failure(error)
        }
    }
}
