//
//  CosmosStakingHelper.swift
//  VultisigApp
//
//  Pure stateless byte-builder for Cosmos-SDK x/staking + x/distribution
//  messages. Ports the agent-app `buildCosmosStakingTx` + SDK
//  `buildCosmosStakingTx` byte-for-byte so the iOS encoder stays byte-equal
//  with the SDK reference encoder under the SignDoc / TxBody contract.
//
//  Each `encode*` method returns the `Any`-wrapped message bytes
//  (`{ type_url, value }`) ready to drop into a TxBody. `buildTxBodyMulti`
//  packs N `Any`-wrapped messages into a single TxBody — used both by the
//  single-msg flows (delegate / undelegate / redelegate) and by the
//  multi-msg batched-claim flow (one TxBody covering claims from N
//  validators, signed in a single MPC ceremony).
//
//  Reuses the proto encoders from QBTCHelper (`Data.appendProto*`
//  extensions) — proto3 default-skip semantics match the SDK and the wire
//  format is identical.
//

import CryptoSwift
import Foundation

enum CosmosStakingHelper {
    // MARK: - Type URLs

    static let msgDelegateTypeURL = "/cosmos.staking.v1beta1.MsgDelegate"
    static let msgUndelegateTypeURL = "/cosmos.staking.v1beta1.MsgUndelegate"
    static let msgBeginRedelegateTypeURL = "/cosmos.staking.v1beta1.MsgBeginRedelegate"
    static let msgWithdrawDelegatorRewardTypeURL = "/cosmos.distribution.v1beta1.MsgWithdrawDelegatorReward"
    static let pubKeyTypeURL = "/cosmos.crypto.secp256k1.PubKey"

    /// Proto SignMode value for SIGN_MODE_DIRECT — the only mode the iOS
    /// staking path uses. Amino sign-mode is reserved for legacy hardware
    /// paths and not exercised here.
    private static let signModeDirect: UInt64 = 1

    struct SignDocArtifacts: Equatable {
        let bytes: Data
        let hashHex: String
    }

    // MARK: - Msg encoders (each returns Any-wrapped bytes)

    /// Encodes a `MsgDelegate` into `Any { type_url, value }`.
    /// Wire shape of `value`: `{ delegator_address(1), validator_address(2),
    /// Coin { denom(1), amount(2) }(3) }`.
    static func encodeDelegate(
        delegator: String,
        validator: String,
        amount: String,
        denom: String
    ) -> Data {
        let coin = encodeCoin(denom: denom, amount: amount)
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: delegator)
        msg.appendProtoString(fieldNumber: 2, value: validator)
        msg.appendProtoBytes(fieldNumber: 3, data: coin)
        return wrapAny(typeURL: msgDelegateTypeURL, value: msg)
    }

    /// Encodes a `MsgUndelegate` — identical wire shape to `MsgDelegate`,
    /// distinguished only by the `Any` typeUrl.
    static func encodeUndelegate(
        delegator: String,
        validator: String,
        amount: String,
        denom: String
    ) -> Data {
        let coin = encodeCoin(denom: denom, amount: amount)
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: delegator)
        msg.appendProtoString(fieldNumber: 2, value: validator)
        msg.appendProtoBytes(fieldNumber: 3, data: coin)
        return wrapAny(typeURL: msgUndelegateTypeURL, value: msg)
    }

    /// Encodes a `MsgBeginRedelegate`.
    /// Wire shape of `value`: `{ delegator_address(1),
    /// validator_src_address(2), validator_dst_address(3),
    /// Coin { denom(1), amount(2) }(4) }`.
    ///
    /// Note the 2/3 order — field 2 is the SOURCE validator, field 3 is the
    /// DESTINATION. Swapping them silently produces a tx that redelegates
    /// the wrong way; the SDK test suite calls this out as a regression
    /// guard at `cosmos-staking.test.ts:153-162`.
    static func encodeBeginRedelegate(
        delegator: String,
        validatorSrc: String,
        validatorDst: String,
        amount: String,
        denom: String
    ) -> Data {
        let coin = encodeCoin(denom: denom, amount: amount)
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: delegator)
        msg.appendProtoString(fieldNumber: 2, value: validatorSrc)
        msg.appendProtoString(fieldNumber: 3, value: validatorDst)
        msg.appendProtoBytes(fieldNumber: 4, data: coin)
        return wrapAny(typeURL: msgBeginRedelegateTypeURL, value: msg)
    }

    /// Encodes a `MsgWithdrawDelegatorReward`.
    /// Wire shape: `{ delegator_address(1), validator_address(2) }` — no
    /// Coin field. The distribution-module typeUrl carries the discriminator.
    static func encodeWithdrawDelegatorReward(
        delegator: String,
        validator: String
    ) -> Data {
        var msg = Data()
        msg.appendProtoString(fieldNumber: 1, value: delegator)
        msg.appendProtoString(fieldNumber: 2, value: validator)
        return wrapAny(typeURL: msgWithdrawDelegatorRewardTypeURL, value: msg)
    }

    // MARK: - TxBody + AuthInfo + SignDoc

    /// Packs N `Any`-wrapped messages into a single TxBody, preserving order.
    /// Single-msg flows pass a one-element array; batched claim passes one
    /// `Any`-wrapped `MsgWithdrawDelegatorReward` per validator.
    ///
    /// Wire shape: `{ messages(1, repeated Any), memo(2, optional) }`.
    /// `timeout_height` (field 3) and extension options (4/5) are intentionally
    /// omitted — they default to 0 / unset, matching the SDK encoder.
    static func buildTxBodyMulti(msgsAny: [Data], memo: String = "") -> Data {
        var txBody = Data()
        for anyMsg in msgsAny {
            txBody.appendProtoBytes(fieldNumber: 1, data: anyMsg)
        }
        if !memo.isEmpty {
            txBody.appendProtoString(fieldNumber: 2, value: memo)
        }
        return txBody
    }

    /// Builds the `AuthInfo` for a single-signer tx in SIGN_MODE_DIRECT.
    ///
    /// `pubKeyTypeURL` defaults to secp256k1 (the Terra path). QBTC passes the
    /// ML-DSA URL (`/cosmos.crypto.mldsa.PubKey`) so the post-quantum signing
    /// path reuses this single AuthInfo encoder rather than maintaining a
    /// divergent copy — only the inner `Any` type URL differs by scheme.
    ///
    /// AuthInfo wire shape: `{ signer_infos(1, repeated), fee(2) }`.
    /// SignerInfo: `{ public_key(1, Any), mode_info(2), sequence(3) }`.
    /// ModeInfo: `{ single(1) }` → Single: `{ mode(1) }`.
    /// Fee: `{ amount(1, repeated Coin), gas_limit(2) }`.
    static func buildAuthInfo(
        pubKey: Data,
        sequence: UInt64,
        gasLimit: UInt64,
        feeDenom: String,
        feeAmount: UInt64,
        pubKeyTypeURL: String = CosmosStakingHelper.pubKeyTypeURL
    ) -> Data {
        // Inner PubKey: { key(1, bytes) }
        var pubKeyInner = Data()
        pubKeyInner.appendProtoBytes(fieldNumber: 1, data: pubKey)

        // Any-wrapped pub key: { type_url(1), value(2) }
        var pubKeyAny = Data()
        pubKeyAny.appendProtoString(fieldNumber: 1, value: pubKeyTypeURL)
        pubKeyAny.appendProtoBytes(fieldNumber: 2, data: pubKeyInner)

        // ModeInfo.Single: { mode(1, varint) }
        var single = Data()
        single.appendProtoVarint(fieldNumber: 1, value: signModeDirect)
        // ModeInfo: { single(1) }
        var modeInfo = Data()
        modeInfo.appendProtoBytes(fieldNumber: 1, data: single)

        // SignerInfo: { public_key(1, Any), mode_info(2), sequence(3) }
        var signerInfo = Data()
        signerInfo.appendProtoBytes(fieldNumber: 1, data: pubKeyAny)
        signerInfo.appendProtoBytes(fieldNumber: 2, data: modeInfo)
        signerInfo.appendProtoVarint(fieldNumber: 3, value: sequence)

        // Fee.amount Coin: { denom(1), amount(2) }
        let feeCoin = encodeCoin(denom: feeDenom, amount: String(feeAmount))

        // Fee: { amount(1, repeated Coin), gas_limit(2) }
        var fee = Data()
        fee.appendProtoBytes(fieldNumber: 1, data: feeCoin)
        fee.appendProtoVarint(fieldNumber: 2, value: gasLimit)

        // AuthInfo: { signer_infos(1, repeated), fee(2) }
        var authInfo = Data()
        authInfo.appendProtoBytes(fieldNumber: 1, data: signerInfo)
        authInfo.appendProtoBytes(fieldNumber: 2, data: fee)
        return authInfo
    }

    /// Builds the SignDoc bytes and returns them alongside their SHA-256
    /// hex digest — the digest is the pre-image hash that the MPC layer
    /// signs.
    ///
    /// SignDoc wire shape:
    /// `{ body_bytes(1), auth_info_bytes(2), chain_id(3), account_number(4) }`.
    static func buildSignDoc(
        bodyBytes: Data,
        authInfoBytes: Data,
        chainId: String,
        accountNumber: UInt64
    ) -> SignDocArtifacts {
        var signDoc = Data()
        signDoc.appendProtoBytes(fieldNumber: 1, data: bodyBytes)
        signDoc.appendProtoBytes(fieldNumber: 2, data: authInfoBytes)
        signDoc.appendProtoString(fieldNumber: 3, value: chainId)
        signDoc.appendProtoVarint(fieldNumber: 4, value: accountNumber)
        return SignDocArtifacts(bytes: signDoc, hashHex: signDoc.sha256().toHexString())
    }

    // MARK: - Helpers

    /// `Coin` wire shape: `{ denom(1), amount(2) }`. Used in MsgDelegate,
    /// MsgUndelegate, MsgBeginRedelegate, and Fee.amount.
    private static func encodeCoin(denom: String, amount: String) -> Data {
        var coin = Data()
        coin.appendProtoString(fieldNumber: 1, value: denom)
        coin.appendProtoString(fieldNumber: 2, value: amount)
        return coin
    }

    /// Wraps an inner message body in `google.protobuf.Any`: `{ type_url(1),
    /// value(2) }`. Cosmos-SDK msgs are always Any-wrapped inside TxBody.
    private static func wrapAny(typeURL: String, value: Data) -> Data {
        var anyMsg = Data()
        anyMsg.appendProtoString(fieldNumber: 1, value: typeURL)
        anyMsg.appendProtoBytes(fieldNumber: 2, data: value)
        return anyMsg
    }
}
