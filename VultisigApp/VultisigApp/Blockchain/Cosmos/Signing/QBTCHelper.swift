//
//  QBTCHelper.swift
//  VultisigApp
//
//  Custom Cosmos transaction builder for QBTC chain.
//  Bypasses WalletCore's TransactionCompiler because MLDSA keys
//  are incompatible with WalletCore's secp256k1 verification.
//  Builds Cosmos protobuf (SignDoc, TxRaw) manually.
//

import CryptoSwift
import Foundation
import VultisigCommonData
import WalletCore

struct QBTCHelper {
    // MARK: - Configuration

    let chainID: String
    let denom: String
    let gasLimit: UInt64

    static let pubKeyTypeURL = "/cosmos.crypto.mldsa.PubKey"

    // Cosmos message type URLs
    private static let msgSendTypeURL = "/cosmos.bank.v1beta1.MsgSend"
    private static let msgTransferTypeURL = "/ibc.applications.transfer.v1.MsgTransfer"
    private static let msgVoteTypeURL = "/cosmos.gov.v1beta1.MsgVote"
    private static let msgDelegateTypeURL = "/cosmos.staking.v1beta1.MsgDelegate"
    private static let msgUndelegateTypeURL = "/cosmos.staking.v1beta1.MsgUndelegate"
    private static let msgWithdrawRewardTypeURL = "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward"

    static func create() -> QBTCHelper {
        QBTCHelper(
            chainID: "qbtc-testnet",
            denom: "qbtc",
            gasLimit: 300_000
        )
    }

    // MARK: - Pre-image Hash

    func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let signDoc = try buildSignDoc(keysignPayload: keysignPayload)
        let hash = signDoc.sha256()
        return [hash.toHexString()]
    }

    // MARK: - Signed Transaction

    func getSignedTransaction(
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
            throw HelperError.runtimeError("QBTC: no signature found for hash \(hashHex)")
        }

        guard let sigData = Data(hexString: sig.signature) else {
            throw HelperError.runtimeError("QBTC: invalid signature hex")
        }

        let txRaw = QBTCProtoBuilder.buildTxRaw(bodyBytes: bodyBytes, authInfoBytes: authInfoBytes, signature: sigData)
        let txBytesBase64 = txRaw.base64EncodedString()
        let broadcastJSON = "{\"tx_bytes\":\"\(txBytesBase64)\",\"mode\":\"BROADCAST_MODE_SYNC\"}"
        let transactionHash = txRaw.sha256().toHexString().uppercased()

        return SignedTransactionResult(
            rawTransaction: broadcastJSON,
            transactionHash: transactionHash
        )
    }

    // MARK: - Transaction Building

    private func buildSignDoc(keysignPayload: KeysignPayload) throws -> Data {
        let (bodyBytes, authInfoBytes) = try buildTxComponents(keysignPayload: keysignPayload)
        return try buildSignDocFromComponents(
            bodyBytes: bodyBytes,
            authInfoBytes: authInfoBytes,
            keysignPayload: keysignPayload
        )
    }

    private func buildTxComponents(keysignPayload: KeysignPayload) throws -> (bodyBytes: Data, authInfoBytes: Data) {
        guard case let .Cosmos(_, sequence, gas, transactionTypeRawValue, ibcDenomTrace) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("QBTC: fail to get account number and sequence")
        }

        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("QBTC: invalid hex public key")
        }

        let bodyBytes = try buildTxBody(keysignPayload: keysignPayload, transactionTypeRawValue: transactionTypeRawValue, ibcDenomTrace: ibcDenomTrace)
        let authInfoBytes = buildAuthInfo(pubKeyData: pubKeyData, sequence: sequence, gas: gas)
        return (bodyBytes, authInfoBytes)
    }

    private func buildSignDocFromComponents(
        bodyBytes: Data,
        authInfoBytes: Data,
        keysignPayload: KeysignPayload
    ) throws -> Data {
        guard case let .Cosmos(accountNumber, _, _, _, _) = keysignPayload.chainSpecific else {
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

    // MARK: - Message Routing

    private func buildTxBody(keysignPayload: KeysignPayload, transactionTypeRawValue: Int, ibcDenomTrace: CosmosIbcDenomTraceDenomTrace?) throws -> Data {
        var transactionType: VSTransactionType = .unspecified
        if let vsTransactionType = VSTransactionType(rawValue: transactionTypeRawValue) {
            transactionType = vsTransactionType
        }

        let anyMsg: Data
        var memo = keysignPayload.memo

        switch transactionType {
        case .ibcTransfer:
            anyMsg = try buildIBCTransferAny(keysignPayload: keysignPayload, ibcDenomTrace: ibcDenomTrace)
            // IBC memo is embedded in the message; strip the routing prefix from the tx memo
            let splitMemo = memo?.split(separator: ":")
            if let splitMemo, splitMemo.count == 4 {
                memo = String(splitMemo[3])
            } else {
                memo = nil
            }

        case .vote:
            anyMsg = try buildVoteAny(keysignPayload: keysignPayload)
            memo = nil

        default:
            anyMsg = buildMsgSendAny(keysignPayload: keysignPayload)
        }

        // TxBody: field 1 = messages (repeated Any), field 2 = memo
        var txBody = Data()
        txBody.appendProtoBytes(fieldNumber: 1, data: anyMsg)
        if let memo, !memo.isEmpty {
            txBody.appendProtoString(fieldNumber: 2, value: memo)
        }
        return txBody
    }

    // MARK: - MsgSend

    private func buildMsgSendAny(keysignPayload: KeysignPayload) -> Data {
        let msgSend = buildMsgSend(keysignPayload: keysignPayload)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: Self.msgSendTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msgSend)
        return anyMsg
    }

    private func buildMsgSend(keysignPayload: KeysignPayload) -> Data {
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

    // MARK: - IBC Transfer (MsgTransfer)

    private func buildIBCTransferAny(keysignPayload: KeysignPayload, ibcDenomTrace: CosmosIbcDenomTraceDenomTrace?) throws -> Data {
        let msgTransfer = try buildMsgTransfer(keysignPayload: keysignPayload, ibcDenomTrace: ibcDenomTrace)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: Self.msgTransferTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msgTransfer)
        return anyMsg
    }

    private func buildMsgTransfer(keysignPayload: KeysignPayload, ibcDenomTrace: CosmosIbcDenomTraceDenomTrace?) throws -> Data {
        // Parse memo: format is "ibc:sourceChannel:...:optionalMemo"
        let splitMemo = keysignPayload.memo?.split(separator: ":")
        guard let splitMemo, splitMemo.count >= 2 else {
            throw HelperError.runtimeError("QBTC: IBC transfer requires memo with source channel (ibc:channel-N:...)")
        }
        let sourceChannel = String(splitMemo[1])

        // Parse timeout from ibcDenomTrace
        let timeouts = ibcDenomTrace?.height?.split(separator: "_") ?? []
        let timeout = UInt64(timeouts.last ?? "0") ?? 0

        let tokenDenom = keysignPayload.coin.isNativeToken ? denom : keysignPayload.coin.contractAddress

        // Coin (token): field 1 = denom, field 2 = amount
        var token = Data()
        token.appendProtoString(fieldNumber: 1, value: tokenDenom)
        token.appendProtoString(fieldNumber: 2, value: String(keysignPayload.toAmount))

        // Height: field 1 = revision_number, field 2 = revision_height
        // Both 0 = use timeout_timestamp instead
        let height = Data()

        // MsgTransfer:
        //   field 1 = source_port (string)
        //   field 2 = source_channel (string)
        //   field 3 = token (Coin)
        //   field 4 = sender (string)
        //   field 5 = receiver (string)
        //   field 6 = timeout_height (Height)
        //   field 7 = timeout_timestamp (uint64)
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: "transfer")
        msg.appendProtoString(fieldNumber: 2, value: sourceChannel)
        msg.appendProtoBytes(fieldNumber: 3, data: token)
        msg.appendProtoString(fieldNumber: 4, value: keysignPayload.coin.address)
        msg.appendProtoString(fieldNumber: 5, value: keysignPayload.toAddress)
        if !height.isEmpty {
            msg.appendProtoBytes(fieldNumber: 6, data: height)
        }
        msg.appendProtoVarint(fieldNumber: 7, value: timeout)
        return msg
    }

    // MARK: - Governance Vote (MsgVote)

    private func buildVoteAny(keysignPayload: KeysignPayload) throws -> Data {
        let msgVote = try buildMsgVote(keysignPayload: keysignPayload)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: Self.msgVoteTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msgVote)
        return anyMsg
    }

    private func buildMsgVote(keysignPayload: KeysignPayload) throws -> Data {
        // Memo format: "QBTC_VOTE:OPTION:PROPOSAL_ID"
        let voteStr = keysignPayload.memo?.replacingOccurrences(of: "QBTC_VOTE:", with: "")
            .replacingOccurrences(of: "DYDX_VOTE:", with: "") ?? ""
        let components = voteStr.split(separator: ":")

        guard components.count == 2, let proposalID = UInt64(components[1]) else {
            throw HelperError.runtimeError("QBTC: invalid vote memo format, expected OPTION:PROPOSAL_ID")
        }

        let option = voteOptionValue(from: String(components[0]))

        // MsgVote:
        //   field 1 = proposal_id (uint64)
        //   field 2 = voter (string)
        //   field 3 = option (enum as varint)
        var msg = Data()
        msg.appendProtoVarint(fieldNumber: 1, value: proposalID)
        msg.appendProtoString(fieldNumber: 2, value: keysignPayload.coin.address)
        msg.appendProtoVarint(fieldNumber: 3, value: option)
        return msg
    }

    private func voteOptionValue(from description: String) -> UInt64 {
        switch description.uppercased() {
        case "YES": return 1
        case "ABSTAIN": return 2
        case "NO": return 3
        case "NO_WITH_VETO", "NOWITHVETO": return 4
        default: return 0 // UNSPECIFIED
        }
    }

    // MARK: - Staking: MsgDelegate

    func buildDelegateAny(delegator: String, validator: String, amount: String) -> Data {
        let msg = buildMsgDelegate(delegator: delegator, validator: validator, amount: amount)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: Self.msgDelegateTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msg)
        return anyMsg
    }

    private func buildMsgDelegate(delegator: String, validator: String, amount: String) -> Data {
        // Coin: field 1 = denom, field 2 = amount
        var coin = Data()
        coin.appendProtoString(fieldNumber: 1, value: denom)
        coin.appendProtoString(fieldNumber: 2, value: amount)

        // MsgDelegate: field 1 = delegator_address, field 2 = validator_address, field 3 = amount
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: delegator)
        msg.appendProtoString(fieldNumber: 2, value: validator)
        msg.appendProtoBytes(fieldNumber: 3, data: coin)
        return msg
    }

    // MARK: - Staking: MsgUndelegate

    func buildUndelegateAny(delegator: String, validator: String, amount: String) -> Data {
        let msg = buildMsgUndelegate(delegator: delegator, validator: validator, amount: amount)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: Self.msgUndelegateTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msg)
        return anyMsg
    }

    private func buildMsgUndelegate(delegator: String, validator: String, amount: String) -> Data {
        // Same structure as MsgDelegate
        var coin = Data()
        coin.appendProtoString(fieldNumber: 1, value: denom)
        coin.appendProtoString(fieldNumber: 2, value: amount)

        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: delegator)
        msg.appendProtoString(fieldNumber: 2, value: validator)
        msg.appendProtoBytes(fieldNumber: 3, data: coin)
        return msg
    }

    // MARK: - Distribution: MsgWithdrawDelegatorReward

    func buildWithdrawRewardAny(delegator: String, validator: String) -> Data {
        let msg = buildMsgWithdrawReward(delegator: delegator, validator: validator)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: Self.msgWithdrawRewardTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msg)
        return anyMsg
    }

    private func buildMsgWithdrawReward(delegator: String, validator: String) -> Data {
        // MsgWithdrawDelegatorReward: field 1 = delegator_address, field 2 = validator_address
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: delegator)
        msg.appendProtoString(fieldNumber: 2, value: validator)
        return msg
    }

    // MARK: - AuthInfo

    private func buildAuthInfo(pubKeyData: Data, sequence: UInt64, gas: UInt64) -> Data {
        // PubKey message: field 1 = key (bytes)
        var pubKeyMsg = Data()
        pubKeyMsg.appendProtoBytes(fieldNumber: 1, data: pubKeyData)

        // Any wrapping PubKey
        var pubKeyAny = Data()
        pubKeyAny.appendProtoString(fieldNumber: 1, value: Self.pubKeyTypeURL)
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
}

// MARK: - Protobuf Wire Format Encoding

/// Shared protobuf helpers for manual wire-format encoding.
/// Used by QBTCHelper because WalletCore cannot handle MLDSA keys.
enum QBTCProtoBuilder {
    static func buildTxRaw(bodyBytes: Data, authInfoBytes: Data, signature: Data) -> Data {
        // TxRaw: field 1 = body_bytes, field 2 = auth_info_bytes, field 3 = signatures (repeated bytes)
        var txRaw = Data()
        txRaw.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        txRaw.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        txRaw.appendProtoBytes(fieldNumber: 3, data: signature)
        return txRaw
    }
}

extension Data {
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
