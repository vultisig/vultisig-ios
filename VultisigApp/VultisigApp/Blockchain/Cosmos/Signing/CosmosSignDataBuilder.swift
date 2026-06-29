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
        let chain = keysignPayload.coin.chain
        let feeDenom = chain.feeUnit.lowercased()
        switch signData {
        case .signAmino(let signAmino):
            // signAmino is JSON re-encoded per device, so flooring the fee here
            // is hash-safe. Raise a sub-floor fee on the chain's own fee denom
            // to the network minimum (e.g. a Keplr-injected Akash staking fee
            // of 7_500 uakt at ~300k gas is floored to 25_000 uakt).
            let gasLimit = UInt64(signAmino.fee.gas) ?? 0
            return WalletCore.CosmosFee.with {
                $0.gas = gasLimit
                $0.amounts = signAmino.fee.amount.map { amount in
                    WalletCore.CosmosAmount.with {
                        $0.denom = amount.denom
                        if amount.denom.lowercased() == feeDenom, let computed = UInt64(amount.amount) {
                            $0.amount = String(CosmosFeeFloorConfig.flooredFee(
                                for: chain,
                                computedFee: computed,
                                gasLimit: gasLimit
                            ))
                        } else {
                            $0.amount = amount.amount
                        }
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

            // The fee lives inside peer-shared authInfoBytes that every cosigner
            // hashes; rewriting it would diverge the cosigner hash and break the
            // threshold signature. So for a floored chain we VALIDATE the
            // supplied fee and reject a sub-floor request, rather than silently
            // rewriting the bytes.
            let suppliedFee = feeInfo.amounts
                .filter { $0.denom.lowercased() == feeDenom }
                .compactMap { UInt64($0.amount) }
                .reduce(0, +)
            if !CosmosFeeFloorConfig.meetsFloor(for: chain, fee: suppliedFee, gasLimit: feeInfo.gasLimit) {
                throw HelperError.runtimeError("Cosmos signDirect fee \(suppliedFee) \(feeDenom) is below the network minimum of \(CosmosFeeFloorConfig.requiredFloor(for: chain, gasLimit: feeInfo.gasLimit)) \(feeDenom)")
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
        case .signSolana, .signTon, .signBitcoin, .signSui:
            return nil
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
