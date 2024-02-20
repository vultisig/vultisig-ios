//
//  bitcoin.swift
//  VoltixApp
//

import Foundation
import Tss
import WalletCore

struct UtxoInfo: Codable, Hashable {
    let hash: String
    let amount: Int64
    let index: UInt32
}

enum BitcoinHelper {
    enum BitcoinTransactionError: Error {
        case tssError(String)
        case runtimeError(String)
    }

    static func getBitcoin(hexPubKey: String, hexChainCode: String) -> Result<Coin, Error> {
        return getAddressFromPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode)
            .map { addr in
                Coin(chain: Chain.Bitcoin, ticker: "BTC", logo: "", address: addr)
            }
    }

    static func getAddressFromPubKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        print(hexPubKey)
        var nsErr: NSError?
        let derivedPubKey = TssGetDerivedPubKey(hexPubKey, hexChainCode, CoinType.bitcoin.derivationPath(), false, &nsErr)
        print(derivedPubKey)
        if let nsErr {
            return .failure(BitcoinTransactionError.tssError("fail to derive pubkey,error:\(nsErr.localizedDescription)"))
        }
        guard let pubkeyData = Data(hexString: derivedPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(BitcoinTransactionError.runtimeError("public key \(derivedPubKey) is invalid"))
        }

        return .success(CoinType.bitcoin.deriveAddressFromPublicKey(publicKey: publicKey))
    }

    // before keysign , we need to get the preSignedImageHash , so it can be signed with TSS
    static func getPreSignedImageHash(utxos: [UtxoInfo],
                                      hexPubKey: String,
                                      fromAddress: String,
                                      toAddress: String,
                                      toAmount: Int64,
                                      byteFee: Int64) -> Result<[String], Error>
    {
        guard let pubkeyData = Data(hexString: hexPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(BitcoinTransactionError.runtimeError("public key \(hexPubKey) is invalid"))
        }

        let result = getBitcoinPreSigningInputData(utxos: utxos, pubKey: publicKey, fromAddress: fromAddress, toAddress: toAddress, toAmount: toAmount, byteFee: byteFee)
        switch result {
        case .success(let inputData):
            do {
                let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: inputData)
                let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)
                return .success(preSignOutputs.hashPublicKeys.map { $0.dataHash.hexString })
            } catch {
                return .failure(BitcoinTransactionError.runtimeError("fail to get presigned image hashes,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    static func getBitcoinPreSigningInputData(utxos: [UtxoInfo],
                                              pubKey: PublicKey,
                                              fromAddress: String,
                                              toAddress: String,
                                              toAmount: Int64,
                                              byteFee: Int64) -> Result<Data, Error>
    {
        do {
            let coin = CoinType.bitcoin
            var input = BitcoinSigningInput.with {
                $0.hashType = BitcoinSigHashType.all.rawValue
                $0.amount = toAmount
                $0.toAddress = toAddress
                $0.changeAddress = fromAddress
                $0.byteFee = byteFee
                $0.coinType = coin.rawValue
                $0.scripts = [String: Data]()
            }
            for inputUtxo in utxos {
                let lockScript = BitcoinScript.lockScriptForAddress(address: fromAddress, coin: .bitcoin)
                print("lock script: \(lockScript.scriptHash.hexString)")
                let keyHash = lockScript.matchPayToWitnessPublicKeyHash()
                guard let keyHash else {
                    return .failure(BitcoinTransactionError.runtimeError("fail to get key hash from lock script"))
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
            return .success(inputData)

        } catch {
            print("fail to construct bitcoin presigning output,err:\(error)")
            return .failure(error)
        }
    }

    static func getSignedBitcoinTransaction(utxos: [UtxoInfo],
                                            hexPubKey: String,
                                            fromAddress: String,
                                            toAddress: String,
                                            toAmount: Int64,
                                            byteFee: Int64,
                                            signatureProvider: (Data) -> Data) -> Result<String, Error>
    {
        guard let pubkeyData = Data(hexString: hexPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(BitcoinTransactionError.runtimeError("public key \(hexPubKey) is invalid"))
        }

        let result = getBitcoinPreSigningInputData(utxos: utxos,
                                                   pubKey: publicKey,
                                                   fromAddress: fromAddress,
                                                   toAddress: toAddress,
                                                   toAmount: toAmount,
                                                   byteFee: byteFee)
        switch result {
        case .success(let preSignInputData):
            do {
                let preHashes = TransactionCompiler.preImageHashes(coinType: .bitcoin, txInputData: preSignInputData)
                let preSignOutputs = try BitcoinPreSigningOutput(serializedData: preHashes)

                let allSignatures = DataVector()
                let publicKeys = DataVector()
                for h in preSignOutputs.hashPublicKeys {
                    let preImageHash = h.dataHash
                    let signature = signatureProvider(preImageHash)
                    guard publicKey.verifyAsDER(signature: signature, message: preImageHash) else {
                        return .failure(BitcoinTransactionError.runtimeError("fail to verify signature"))
                    }
                    allSignatures.add(data: signature)
                    publicKeys.add(data: pubkeyData)
                }

                let compileWithSignatures = TransactionCompiler.compileWithSignatures(coinType: .bitcoin, txInputData: preSignInputData, signatures: allSignatures, publicKeys: publicKeys)
                let output = try BitcoinSigningOutput(serializedData: compileWithSignatures)
                return .success(output.encoded.hexString)
            } catch {
                return .failure(BitcoinTransactionError.runtimeError("fail to construct raw transaction,error: \(error.localizedDescription)"))
            }

        case .failure(let error):
            return .failure(error)
        }
    }
}
