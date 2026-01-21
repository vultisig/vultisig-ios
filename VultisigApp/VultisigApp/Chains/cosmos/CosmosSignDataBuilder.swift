//
//  CosmosSignDataBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/12/2025.
//

import WalletCore

enum CosmosSignDataBuilder {
    static func getSigningMode(keysignPayload: KeysignPayload) -> WalletCore.TW_Cosmos_Proto_SigningMode {
        switch keysignPayload.signData {
        case .signAmino:
            return .json
        case .signDirect:
            return .protobuf
        default:
            break
        }
        return .protobuf
    }

    static func getFee(keysignPayload: KeysignPayload) throws -> WalletCore.CosmosFee? {
        guard let signData = keysignPayload.signData else { return nil }
        switch signData {
        case .signAmino(let signAmino):
            return WalletCore.CosmosFee.with {
                $0.gas = UInt64(signAmino.fee.gas) ?? 0
                $0.amounts = signAmino.fee.amount.map { amount in
                    WalletCore.CosmosAmount.with {
                        $0.denom = amount.denom
                        $0.amount = amount.amount
                    }
                }
            }
        case .signDirect(let signDirect):
            // Try to extract fee from authInfoBytes
            guard
                let authInfoBytes = signDirect.authInfoBytes.fromBase64(),
                let feeInfo = CosmosSignDirectParser.extractFee(from: authInfoBytes)
            else {
                throw HelperError.runtimeError("Couldn't parse signDirect fee info")
            }

            return WalletCore.CosmosFee.with {
                $0.gas = feeInfo.gasLimit
                $0.amounts = feeInfo.amounts.map { coin in
                    WalletCore.CosmosAmount.with {
                        $0.denom = coin.denom
                        $0.amount = coin.amount
                    }
                }
            }
        }
    }

    static func getMessages(keysignPayload: KeysignPayload) throws -> (messages: [WalletCore.CosmosMessage], memo: String?)? {
        if let signAmino = keysignPayload.signAmino {
            let messages = signAmino.msgs.map { msg in
                WalletCore.CosmosMessage.with {
                    $0.rawJsonMessage = .with {
                        $0.type = msg.type
                        $0.value = msg.value
                    }
                }
            }
            return (messages: messages, memo: nil)
        }

        if let signDirect = keysignPayload.signDirect {
            // Decode bodyBytes and authInfoBytes from base64
            guard let bodyBytes = signDirect.bodyBytes.fromBase64(),
                  let authInfoBytes = signDirect.authInfoBytes.fromBase64() else {
                throw HelperError.runtimeError("Failed to decode signDirect bytes from base64")
            }

            // Parse protobuf to extract memo
            let extractedMemo = CosmosSignDirectParser.extractMemo(from: bodyBytes)

            // Create SignDirect message with raw protobuf bytes
            let messages = [WalletCore.CosmosMessage.with {
                $0.signDirectMessage = .with {
                    $0.bodyBytes = bodyBytes
                    $0.authInfoBytes = authInfoBytes
                }
            }]

            return (messages: messages, memo: extractedMemo)
        }

        return nil
    }
}
