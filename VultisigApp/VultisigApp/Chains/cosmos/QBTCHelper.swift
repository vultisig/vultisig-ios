//
//  QBTCHelper.swift
//  VultisigApp
//
//  Custom Cosmos transaction builder for QBTC chain.
//  Bypasses WalletCore's TransactionCompiler because MLDSA keys
//  are incompatible with WalletCore's secp256k1 verification.
//  Builds Cosmos protobuf (SignDoc, TxRaw) manually.
//

import Foundation
import WalletCore
import CryptoSwift
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-helper")

struct QBTCHelper {

    static let chainID = "qbtc-testnet"
    static let denom = "qbtc"
    static let gasLimit: UInt64 = 200_000
    static let pubKeyTypeURL = "/cosmos.crypto.mldsa.PubKey"
    static let msgSendTypeURL = "/cosmos.bank.v1beta1.MsgSend"

    // MARK: - Pre-image Hash

    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let signDoc = try buildSignDoc(keysignPayload: keysignPayload)
        let hash = signDoc.sha256()
        return [hash.toHexString()]
    }

    // MARK: - Signed Transaction

    static func getSignedTransaction(
        keysignPayload: KeysignPayload,
        signatures: [String: DilithiumKeysignResponse]
    ) throws -> SignedTransactionResult {
        let (bodyBytes, authInfoBytes) = try buildTxComponents(keysignPayload: keysignPayload)

        let signDoc = try buildSignDocFromComponents(
            bodyBytes: bodyBytes,
            authInfoBytes: authInfoBytes,
            keysignPayload: keysignPayload
        )
        let hashHex = signDoc.sha256().toHexString()

        guard let sig = signatures[hashHex] else {
            logger.error("No MLDSA signature found for hash: \(hashHex)")
            throw HelperError.runtimeError("QBTC: no signature found for hash \(hashHex)")
        }

        guard let sigData = Data(hexString: sig.signature) else {
            throw HelperError.runtimeError("QBTC: invalid signature hex")
        }

        let txRaw = buildTxRaw(bodyBytes: bodyBytes, authInfoBytes: authInfoBytes, signature: sigData)
        let txBytesBase64 = txRaw.base64EncodedString()
        let broadcastJSON = "{\"tx_bytes\":\"\(txBytesBase64)\",\"mode\":\"BROADCAST_MODE_SYNC\"}"
        let transactionHash = txRaw.sha256().toHexString().uppercased()

        return SignedTransactionResult(
            rawTransaction: broadcastJSON,
            transactionHash: transactionHash
        )
    }

    // MARK: - Transaction Building

    private static func buildSignDoc(keysignPayload: KeysignPayload) throws -> Data {
        let (bodyBytes, authInfoBytes) = try buildTxComponents(keysignPayload: keysignPayload)
        return try buildSignDocFromComponents(
            bodyBytes: bodyBytes,
            authInfoBytes: authInfoBytes,
            keysignPayload: keysignPayload
        )
    }

    private static func buildTxComponents(keysignPayload: KeysignPayload) throws -> (bodyBytes: Data, authInfoBytes: Data) {
        guard case .Cosmos(_, let sequence, let gas, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("QBTC: fail to get account number and sequence")
        }

        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("QBTC: invalid hex public key")
        }

        let bodyBytes = buildTxBody(keysignPayload: keysignPayload)
        let authInfoBytes = buildAuthInfo(pubKeyData: pubKeyData, sequence: sequence, gas: gas)
        return (bodyBytes, authInfoBytes)
    }

    private static func buildSignDocFromComponents(
        bodyBytes: Data,
        authInfoBytes: Data,
        keysignPayload: KeysignPayload
    ) throws -> Data {
        guard case .Cosmos(let accountNumber, _, _, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("QBTC: fail to get account number")
        }

        // SignDoc proto: field 1 = body_bytes, field 2 = auth_info_bytes, field 3 = chain_id, field 4 = account_number
        var signDoc = Data()
        signDoc.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        signDoc.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        signDoc.appendProtoString(fieldNumber: 3, value: chainID)
        signDoc.appendProtoVarint(fieldNumber: 4, value: accountNumber)
        return signDoc
    }

    private static func buildTxBody(keysignPayload: KeysignPayload) -> Data {
        let msgSend = buildMsgSend(keysignPayload: keysignPayload)

        // Wrap MsgSend in google.protobuf.Any
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: msgSendTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msgSend)

        // TxBody: field 1 = messages (repeated Any), field 2 = memo
        var txBody = Data()
        txBody.appendProtoBytes(fieldNumber: 1, data: anyMsg)
        if let memo = keysignPayload.memo, !memo.isEmpty {
            txBody.appendProtoString(fieldNumber: 2, value: memo)
        }
        return txBody
    }

    private static func buildMsgSend(keysignPayload: KeysignPayload) -> Data {
        let coinDenom = keysignPayload.coin.isNativeToken ? denom : keysignPayload.coin.contractAddress

        // Coin: field 1 = denom, field 2 = amount
        var coin = Data()
        coin.appendProtoString(fieldNumber: 1, value: coinDenom)
        coin.appendProtoString(fieldNumber: 2, value: String(keysignPayload.toAmount))

        // MsgSend: field 1 = from_address, field 2 = to_address, field 3 = amount (repeated Coin)
        var msgSend = Data()
        msgSend.appendProtoString(fieldNumber: 1, value: keysignPayload.coin.address)
        msgSend.appendProtoString(fieldNumber: 2, value: keysignPayload.toAddress)
        msgSend.appendProtoBytes(fieldNumber: 3, data: coin)
        return msgSend
    }

    private static func buildAuthInfo(pubKeyData: Data, sequence: UInt64, gas: UInt64) -> Data {
        // PubKey message: field 1 = key (bytes)
        var pubKeyMsg = Data()
        pubKeyMsg.appendProtoBytes(fieldNumber: 1, data: pubKeyData)

        // Any wrapping PubKey
        var pubKeyAny = Data()
        pubKeyAny.appendProtoString(fieldNumber: 1, value: pubKeyTypeURL)
        pubKeyAny.appendProtoBytes(fieldNumber: 2, data: pubKeyMsg)

        // ModeInfo.Single: field 1 = mode (SIGN_MODE_DIRECT = 1)
        var singleMode = Data()
        singleMode.appendProtoVarint(fieldNumber: 1, value: 1)

        // ModeInfo: field 1 = single
        var modeInfo = Data()
        modeInfo.appendProtoBytes(fieldNumber: 1, data: singleMode)

        // SignerInfo: field 1 = public_key (Any), field 2 = mode_info, field 3 = sequence
        var signerInfo = Data()
        signerInfo.appendProtoBytes(fieldNumber: 1, data: pubKeyAny)
        signerInfo.appendProtoBytes(fieldNumber: 2, data: modeInfo)
        signerInfo.appendProtoVarint(fieldNumber: 3, value: sequence)

        // Fee Coin
        var feeCoin = Data()
        feeCoin.appendProtoString(fieldNumber: 1, value: denom)
        feeCoin.appendProtoString(fieldNumber: 2, value: String(gas))

        // Fee: field 1 = amount (repeated Coin), field 2 = gas_limit
        var fee = Data()
        fee.appendProtoBytes(fieldNumber: 1, data: feeCoin)
        fee.appendProtoVarint(fieldNumber: 2, value: gasLimit)

        // AuthInfo: field 1 = signer_infos (repeated), field 2 = fee
        var authInfo = Data()
        authInfo.appendProtoBytes(fieldNumber: 1, data: signerInfo)
        authInfo.appendProtoBytes(fieldNumber: 2, data: fee)
        return authInfo
    }

    private static func buildTxRaw(bodyBytes: Data, authInfoBytes: Data, signature: Data) -> Data {
        // TxRaw: field 1 = body_bytes, field 2 = auth_info_bytes, field 3 = signatures (repeated bytes)
        var txRaw = Data()
        txRaw.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        txRaw.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        txRaw.appendProtoBytes(fieldNumber: 3, data: signature)
        return txRaw
    }
}

// MARK: - Protobuf Wire Format Encoding

private extension Data {

    /// Appends a varint field (wire type 0). Skips if value is 0 (proto3 default).
    mutating func appendProtoVarint(fieldNumber: Int, value: UInt64) {
        guard value != 0 else { return }
        let tag = UInt64(fieldNumber << 3 | 0)
        appendVarint(tag)
        appendVarint(value)
    }

    /// Appends a length-delimited field (wire type 2) for raw bytes.
    mutating func appendProtoBytes(fieldNumber: Int, data: Data) {
        guard !data.isEmpty else { return }
        let tag = UInt64(fieldNumber << 3 | 2)
        appendVarint(tag)
        appendVarint(UInt64(data.count))
        append(data)
    }

    /// Appends a length-delimited field (wire type 2) for a UTF-8 string.
    mutating func appendProtoString(fieldNumber: Int, value: String) {
        guard !value.isEmpty else { return }
        appendProtoBytes(fieldNumber: fieldNumber, data: Data(value.utf8))
    }

    /// Encodes a UInt64 as a protobuf base-128 varint.
    mutating func appendVarint(_ value: UInt64) {
        var v = value
        while v > 0x7F {
            append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        append(UInt8(v))
    }
}
