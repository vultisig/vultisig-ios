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
    private static let msgVoteWeightedTypeURL = "/cosmos.gov.v1beta1.MsgVoteWeighted"

    static func create() -> QBTCHelper {
        QBTCHelper(
            chainID: QBTCChain.chainID,
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
    //
    // The QBTC claim flow does NOT go through this helper any more — the
    // proof service signs and broadcasts `MsgClaimWithProof` directly
    // (qbtc#158). This path handles regular sends, IBC transfers, votes,
    // and staking only.

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
        // Staking ops (delegate / undelegate / redelegate / claim) ship the
        // fully-formed TxBody + AuthInfo bytes via `signData.signDirect`, built
        // upstream by `CosmosStakingSignDataResolver.resolveMLDSA` with the
        // ML-DSA pubkey type URL. Those bytes round-trip through the proto, so
        // both devices reconstruct the identical SignDoc hash. Consume them
        // verbatim — no rebuild — to keep the signed bytes byte-exact.
        if let signDirect = keysignPayload.signDirect {
            guard let bodyBytes = Data(base64Encoded: signDirect.bodyBytes),
                  let authInfoBytes = Data(base64Encoded: signDirect.authInfoBytes) else {
                throw HelperError.runtimeError("QBTC: invalid signDirect base64 in keysign payload")
            }
            return (bodyBytes, authInfoBytes)
        }

        guard case let .Cosmos(_, sequence, gas, transactionTypeRawValue, ibcDenomTrace, relayedGasLimit) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("QBTC: fail to get account number and sequence")
        }

        guard let pubKeyData = Data(hexString: keysignPayload.coin.hexPublicKey) else {
            throw HelperError.runtimeError("QBTC: invalid hex public key")
        }

        // Honor the relayed dynamic gas limit when present; otherwise fall back
        // to the static per-chain limit. Both co-signers hash this value (it is
        // part of the SignDoc), so they must resolve to the identical limit.
        let effectiveGasLimit = relayedGasLimit ?? gasLimit

        let bodyBytes = try buildTxBody(keysignPayload: keysignPayload, transactionTypeRawValue: transactionTypeRawValue, ibcDenomTrace: ibcDenomTrace)
        let authInfoBytes = buildAuthInfo(pubKeyData: pubKeyData, sequence: sequence, gas: gas, gasLimit: effectiveGasLimit)
        return (bodyBytes, authInfoBytes)
    }

    private func buildSignDocFromComponents(
        bodyBytes: Data,
        authInfoBytes: Data,
        keysignPayload: KeysignPayload
    ) throws -> Data {
        // For staking, `chain_id` + `account_number` come from the round-tripped
        // `signDirect` so the SignDoc is reconstructed byte-for-byte on both
        // devices, independent of any per-device chainSpecific drift. The
        // send/IBC/vote path reads them from chainSpecific as before.
        let docChainID: String
        let accountNumber: UInt64
        if let signDirect = keysignPayload.signDirect {
            docChainID = signDirect.chainID
            guard let parsed = UInt64(signDirect.accountNumber) else {
                throw HelperError.runtimeError("QBTC: invalid account number in signDirect")
            }
            accountNumber = parsed
        } else {
            guard case let .Cosmos(chainSpecificAccountNumber, _, _, _, _, _) = keysignPayload.chainSpecific else {
                throw HelperError.runtimeError("QBTC: fail to get account number")
            }
            docChainID = chainID
            accountNumber = chainSpecificAccountNumber
        }

        // SignDoc proto: field 1 = body_bytes, field 2 = auth_info_bytes, field 3 = chain_id, field 4 = account_number
        var signDoc = Data()
        signDoc.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        signDoc.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        signDoc.appendProtoString(fieldNumber: 3, value: docChainID)
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
            // A weighted vote and a single-option vote share the `.vote`
            // transaction type; the memo prefix disambiguates them.
            if keysignPayload.memo?.hasPrefix("QBTC_VOTEW:") == true {
                anyMsg = try buildVoteWeightedAny(keysignPayload: keysignPayload)
            } else {
                anyMsg = try buildVoteAny(keysignPayload: keysignPayload)
            }
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
        //
        // The arg order (option before id) differs from the weighted memo
        // ("QBTC_VOTEW:PROPOSAL_ID:OPTIONS", id first). This divergence is
        // intentional and dictated by the QBTC chain's on-chain memo parser —
        // each parser is internally consistent and realigning the order here
        // would break parsing/consensus. Do not "fix" the ordering.
        let voteStr = keysignPayload.memo?.replacingOccurrences(of: "QBTC_VOTE:", with: "")
            .replacingOccurrences(of: "DYDX_VOTE:", with: "") ?? ""
        let components = voteStr.split(separator: ":")

        guard components.count == 2, let proposalID = UInt64(components[1]) else {
            throw HelperError.runtimeError("QBTC: invalid vote memo format, expected OPTION:PROPOSAL_ID")
        }

        guard let option = Self.voteOptionInt(from: String(components[0])) else {
            throw HelperError.runtimeError("QBTC: invalid vote option '\(components[0])'")
        }

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

    // MARK: - Governance Weighted Vote (MsgVoteWeighted)

    private func buildVoteWeightedAny(keysignPayload: KeysignPayload) throws -> Data {
        let msg = try buildMsgVoteWeighted(keysignPayload: keysignPayload)
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: Self.msgVoteWeightedTypeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: msg)
        return anyMsg
    }

    private func buildMsgVoteWeighted(keysignPayload: KeysignPayload) throws -> Data {
        // Memo format: "QBTC_VOTEW:PROPOSAL_ID:OPTION=WEIGHT,OPTION=WEIGHT,..."
        // e.g. "QBTC_VOTEW:42:YES=0.7,ABSTAIN=0.3"
        //
        // Note the id-first order here vs. option-first in the single-vote
        // memo ("QBTC_VOTE:OPTION:PROPOSAL_ID"). The divergence is intentional
        // and chain-contract-defined: the QBTC on-chain parser expects each
        // memo in its own order. Do not realign them — it would break parsing.
        let body = keysignPayload.memo?.replacingOccurrences(of: "QBTC_VOTEW:", with: "") ?? ""
        let firstColon = body.firstIndex(of: ":")
        guard let firstColon else {
            throw HelperError.runtimeError("QBTC: invalid weighted-vote memo, expected PROPOSAL_ID:OPTIONS")
        }
        let proposalIDPart = String(body[body.startIndex..<firstColon])
        let optionsPart = String(body[body.index(after: firstColon)...])

        guard let proposalID = UInt64(proposalIDPart) else {
            throw HelperError.runtimeError("QBTC: invalid weighted-vote proposal id")
        }

        let weightedOptions = try Self.parseWeightedOptions(optionsPart)
        guard !weightedOptions.isEmpty else {
            throw HelperError.runtimeError("QBTC: weighted vote requires at least one option")
        }

        // MsgVoteWeighted:
        //   field 1 = proposal_id (uint64)
        //   field 2 = voter (string)
        //   field 3 = options (repeated WeightedVoteOption)
        var msg = Data()
        msg.appendProtoVarint(fieldNumber: 1, value: proposalID)
        msg.appendProtoString(fieldNumber: 2, value: keysignPayload.coin.address)
        for option in weightedOptions {
            // WeightedVoteOption: field 1 = option (enum varint), field 2 = weight (cosmos.Dec string)
            var optionMsg = Data()
            optionMsg.appendProtoVarint(fieldNumber: 1, value: option.option)
            optionMsg.appendProtoString(fieldNumber: 2, value: option.weight)
            msg.appendProtoBytes(fieldNumber: 3, data: optionMsg)
        }
        return msg
    }

    /// Parses the `OPTION=WEIGHT,OPTION=WEIGHT` body into proto option ints +
    /// canonical 18-decimal `cosmos.Dec` weight strings. Preserves order
    /// (the chain rejects duplicate options, but order is the caller's).
    static func parseWeightedOptions(_ raw: String) throws -> [(option: UInt64, weight: String)] {
        let pairs = raw.split(separator: ",")
        var out: [(option: UInt64, weight: String)] = []
        for pair in pairs {
            let kv = pair.split(separator: "=")
            guard kv.count == 2 else {
                throw HelperError.runtimeError("QBTC: invalid weighted-vote option '\(pair)'")
            }
            guard let option = QBTCHelper.voteOptionInt(from: String(kv[0])) else {
                throw HelperError.runtimeError("QBTC: invalid weighted-vote option '\(kv[0])'")
            }
            guard let weight = QBTCHelper.legacyDecString(from: String(kv[1])) else {
                throw HelperError.runtimeError("QBTC: invalid weighted-vote weight '\(kv[1])'")
            }
            out.append((option: option, weight: weight))
        }
        return out
    }

    /// Maps a vote-option token (e.g. "YES", "NO_WITH_VETO") to the canonical
    /// proto enum integer. Shared by the single-option and weighted paths.
    /// Returns `nil` for an unknown token so callers fail fast rather than
    /// signing `VOTE_OPTION_UNSPECIFIED` for a malformed memo.
    static func voteOptionInt(from description: String) -> UInt64? {
        switch description.uppercased() {
        case "YES": return 1
        case "ABSTAIN": return 2
        case "NO": return 3
        case "NO_WITH_VETO", "NOWITHVETO": return 4
        default: return nil
        }
    }

    /// Normalizes a decimal weight (e.g. "0.7", ".3", "1") to the canonical
    /// `cosmossdk.io/math.LegacyDec` string the chain emits: a fixed 18
    /// fractional digits (e.g. "0.700000000000000000"). Returns `nil` for a
    /// non-numeric or negative input. Truncates beyond 18 fractional digits.
    static func legacyDecString(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = parts[0].isEmpty ? "0" : String(parts[0])
        let fracPart = parts.count == 2 ? String(parts[1]) : ""

        // Reject anything that isn't pure digits in either part (no signs).
        guard intPart.allSatisfy(\.isNumber), fracPart.allSatisfy(\.isNumber) else {
            return nil
        }

        let scale = 18
        let paddedFrac = String((fracPart + String(repeating: "0", count: scale)).prefix(scale))
        return "\(intPart).\(paddedFrac)"
    }

    // MARK: - AuthInfo

    private func buildAuthInfo(pubKeyData: Data, sequence: UInt64, gas: UInt64, gasLimit: UInt64) -> Data {
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
