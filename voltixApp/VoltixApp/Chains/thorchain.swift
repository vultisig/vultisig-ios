//
//  thorchain.swift
//  VoltixApp
//

import Foundation
import WalletCore

enum THORChainHelper {
    static func getAddressFromPublicKey(hexPubKey: String, hexChainCode: String) -> Result<String, Error> {
        let derivePubKey = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPubKey,
                                                            hexChainCode: hexChainCode,
                                                            derivePath: CoinType.thorchain.derivationPath())
        if derivePubKey.isEmpty {
            return .failure(HelperError.runtimeError("derived public key is empty"))
        }
        guard let pubKeyData = Data(hexString: derivePubKey), let publicKey = PublicKey(data: pubKeyData, type: .secp256k1) else {
            return .failure(HelperError.runtimeError("public key: \(derivePubKey) is invalid"))
        }
        return .success(CoinType.ethereum.deriveAddressFromPublicKey(publicKey: publicKey))
    }

    static func getPreSignedInputData(keysignPayload: KeysignPayload) -> Result<Data, Error> {
        guard keysignPayload.coin.chain.ticker == "RUNE" else {
            return .failure(HelperError.runtimeError("coin is not RUNE"))
        }
        guard let fromAddr = keysignPayload.coin.address.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("\(keysignPayload.coin.address) is invalid"))
        }
        guard let toAddress = keysignPayload.toAddress.data(using: .utf8) else {
            return .failure(HelperError.runtimeError("\(keysignPayload.toAddress) is invalid"))
        }
        guard case .THORChain(let accountNumber, let sequence) = keysignPayload.chainSpecific else {
            return .failure(HelperError.runtimeError("fail to get account number and sequence"))
        }
        let coin = CoinType.thorchain
        let input = CosmosSigningInput.with {
            $0.signingMode = .protobuf
            $0.chainID = coin.chainId
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            if let memo = keysignPayload.memo {
                $0.memo = memo
            }
            $0.messages = [CosmosMessage.with {
                $0.thorchainSendMessage = CosmosMessage.THORChainSend.with {
                    $0.fromAddress = fromAddr
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = "rune"
                        $0.amount = String(keysignPayload.toAmount)
                    }]
                    $0.toAddress = toAddress
                }
            }]
            // THORChain fee is 0.02 RUNE
            $0.fee = CosmosFee.with {
                $0.amounts = [CosmosAmount.with {
                    $0.denom = "rune"
                    $0.amount = "200000"
                }]
                $0.gas = 200000
            }
        }

        do {
            let inputData = try input.serializedData()
            return .success(inputData)
        } catch {
            return .failure(HelperError.runtimeError("fail to get plan"))
        }
    }
}
