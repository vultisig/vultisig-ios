//
//  eth.swift
//  VoltixApp
//

import BigInt
import Foundation
import Tss
import WalletCore

enum EthereumHelper {
    static func getSignatureFromTssResponse(tssResponse: TssKeysignResponse) -> Result<Data, Error> {
        guard let rData = Data(hexString: tssResponse.r) else {
            return .failure(HelperError.runtimeError("fail to get r data"))
        }

        guard let v = UInt8(tssResponse.recoveryID, radix: 16) else {
            return .failure(HelperError.runtimeError("fail to get recovery data"))
        }
        let n = BigInt("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141", radix: 16)!
        let sValue = BigInt(tssResponse.s, radix: 16)!
        let lowS = min(sValue, n - sValue)

        let lowSHex = String(lowS, radix: 16)
        guard let lowSData = Data(hexString: lowSHex) else {
            return .failure(HelperError.runtimeError("fail to get s data"))
        }
        var signature = Data()
        signature.append(rData)
        signature.append(lowSData)

        signature.append(Data([v+35+2]))
        return .success(signature)
    }

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
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey, hexChainCode: hexChainCode, derivePath: CoinType.ethereum.derivationPath())
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
        var inputInt = BigInt(input * weiPerGWei).serialize()
        return inputInt
    }

    static func getPreSignedInputData(toAddress: String,
                                      toAmountGWei: Int64,
                                      nonce: Int64,
                                      maxFeePerGasGwei: Int64,
                                      priorityFeeGwei: Int64,
                                      memo: String?) -> Result<Data, Error>
    {
        let coin = CoinType.ethereum
        
        guard let chainID = coin.chainId.data(using:.utf8) else {
            return .failure(HelperError.runtimeError("fail to get chainID"))
        }
        let input = EthereumSigningInput.with {
            $0.chainID = chainID
            $0.nonce = Data(hexString: String(nonce, radix: 16))!
            $0.gasLimit = Data(hexString: String(21_000,radix: 16))!
            $0.maxFeePerGas = convertEthereumNumber(input: maxFeePerGasGwei)
            $0.maxInclusionFeePerGas = convertEthereumNumber(input: priorityFeeGwei)
            $0.toAddress = toAddress
            $0.txMode = .enveloped
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = convertEthereumNumber(input: toAmountGWei)
                    if let memo {
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

    static func getPreSignedImageHash(toAddress: String,
                                      toAmountGWei: Int64,
                                      nonce: Int64,
                                      maxFeePerGasGwei: Int64,
                                      priorityFeeGwei: Int64,
                                      memo: String?) -> Result<String, Error>
    {
        let result = getPreSignedInputData(toAddress: toAddress, toAmountGWei: toAmountGWei, nonce: nonce, maxFeePerGasGwei: maxFeePerGasGwei, priorityFeeGwei: priorityFeeGwei, memo: memo)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                return .success(preSigningOutput.dataHash.hexString)
            } catch {
                return .failure(HelperError.runtimeError("fail to get preSignedImageHash,error:\(error.localizedDescription)"))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    static func getSignedEthereumTransaction(hexPubKey: String,
                                             toAddress: String,
                                             toAmountGWei: Int64,
                                             nonce: Int64,
                                             maxFeePerGasGwei: Int64,
                                             priorityFeeGwei: Int64,
                                             memo: String?,
                                             signatureProvider: (Data) -> Data) -> Result<String, Error>
    {
        guard let pubkeyData = Data(hexString: hexPubKey),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            return .failure(HelperError.runtimeError("public key \(hexPubKey) is invalid"))
        }
        let result = getPreSignedInputData(toAddress: toAddress, toAmountGWei: toAmountGWei, nonce: nonce, maxFeePerGasGwei: maxFeePerGasGwei, priorityFeeGwei: priorityFeeGwei, memo: memo)
        switch result {
        case .success(let inputData):
            do {
                let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: inputData)
                let preSigningOutput = try TxCompilerPreSigningOutput(serializedData: hashes)
                let allSignatures = DataVector()
                let publicKeys = DataVector()
                let signature = signatureProvider(preSigningOutput.dataHash)

                guard publicKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
                    return .failure(HelperError.runtimeError("fail to verify signature"))
                }

                allSignatures.add(data: signature)
                publicKeys.add(data: pubkeyData)
                let compileWithSignature = TransactionCompiler.compileWithSignatures(coinType: .ethereum, txInputData: inputData, signatures: allSignatures, publicKeys: publicKeys)
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
