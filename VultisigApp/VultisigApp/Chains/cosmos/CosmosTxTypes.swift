//
//  CosmosTxTypes.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-12-19.
//
//  Swift equivalent of cosmjs-types cosmos/tx/v1beta1/tx.ts

import Foundation

// MARK: - Tx
/// Tx is the standard type used for broadcasting transactions.
struct CosmosTx: Codable {
    /// body is the processable content of the transaction
    let body: TxBody?

    /// auth_info is the authorization related content of the transaction,
    /// specifically signers, signer modes and fee
    let authInfo: AuthInfo?

    /// signatures is a list of signatures that matches the length and order of
    /// AuthInfo's signer_infos to allow connecting signature meta information like
    /// public key and signing mode by position.
    let signatures: [Base64Data]

    enum CodingKeys: String, CodingKey {
        case body
        case authInfo = "auth_info"
        case signatures
    }
}

// MARK: - TxRaw
/// TxRaw is a variant of Tx that pins the signer's exact binary representation
/// of body and auth_info. This is used for signing, broadcasting and
/// verification. The binary `serialize(tx: TxRaw)` is stored in Tendermint and
/// the hash `sha256(serialize(tx: TxRaw))` becomes the "txhash", commonly used
/// as the transaction ID.
struct TxRaw: Codable {
    /// body_bytes is a protobuf serialization of a TxBody that matches the
    /// representation in SignDoc.
    let bodyBytes: Base64Data

    /// auth_info_bytes is a protobuf serialization of an AuthInfo that matches the
    /// representation in SignDoc.
    let authInfoBytes: Base64Data

    /// signatures is a list of signatures that matches the length and order of
    /// AuthInfo's signer_infos to allow connecting signature meta information like
    /// public key and signing mode by position.
    let signatures: [Base64Data]

    enum CodingKeys: String, CodingKey {
        case bodyBytes = "body_bytes"
        case authInfoBytes = "auth_info_bytes"
        case signatures
    }
}

// MARK: - SignDoc
/// SignDoc is the type used for generating sign bytes for SIGN_MODE_DIRECT.
struct SignDoc: Codable {
    /// body_bytes is protobuf serialization of a TxBody that matches the
    /// representation in TxRaw.
    let bodyBytes: Base64Data

    /// auth_info_bytes is a protobuf serialization of an AuthInfo that matches the
    /// representation in TxRaw.
    let authInfoBytes: Base64Data

    /// chain_id is the unique identifier of the chain this transaction targets.
    /// It prevents signed transactions from being used on another chain by an
    /// attacker
    let chainId: String

    /// account_number is the account number of the account in state
    let accountNumber: UInt64

    enum CodingKeys: String, CodingKey {
        case bodyBytes = "body_bytes"
        case authInfoBytes = "auth_info_bytes"
        case chainId = "chain_id"
        case accountNumber = "account_number"
    }
}

// MARK: - SignDocDirectAux
/// SignDocDirectAux is the type used for generating sign bytes for
/// SIGN_MODE_DIRECT_AUX.
struct SignDocDirectAux: Codable {
    /// body_bytes is protobuf serialization of a TxBody that matches the
    /// representation in TxRaw.
    let bodyBytes: Base64Data

    /// public_key is the public key of the signing account.
    let publicKey: CosmosAny?

    /// chain_id is the identifier of the chain this transaction targets.
    /// It prevents signed transactions from being used on another chain by an
    /// attacker.
    let chainId: String

    /// account_number is the account number of the account in state.
    let accountNumber: UInt64

    /// sequence is the sequence number of the signing account.
    let sequence: UInt64

    /// Tip is the optional tip used for transactions fees paid in another denom.
    let tip: Tip?

    enum CodingKeys: String, CodingKey {
        case bodyBytes = "body_bytes"
        case publicKey = "public_key"
        case chainId = "chain_id"
        case accountNumber = "account_number"
        case sequence
        case tip
    }
}

// MARK: - TxBody
/// TxBody is the body of a transaction that all signers sign over.
struct TxBody: Codable {
    /// messages is a list of messages to be executed. The required signers of
    /// those messages define the number and order of elements in AuthInfo's
    /// signer_infos and Tx's signatures. Each required signer address is added to
    /// the list only the first time it occurs.
    let messages: [CosmosAny]

    /// memo is any arbitrary note/comment to be added to the transaction.
    let memo: String

    /// timeout is the block height after which this transaction will not
    /// be processed by the chain
    let timeoutHeight: UInt64

    /// extension_options are arbitrary options that can be added by chains
    /// when the default options are not sufficient. If any of these are present
    /// and can't be handled, the transaction will be rejected
    let extensionOptions: [CosmosAny]

    /// extension_options are arbitrary options that can be added by chains
    /// when the default options are not sufficient. If any of these are present
    /// and can't be handled, they will be ignored
    let nonCriticalExtensionOptions: [CosmosAny]

    enum CodingKeys: String, CodingKey {
        case messages
        case memo
        case timeoutHeight = "timeout_height"
        case extensionOptions = "extension_options"
        case nonCriticalExtensionOptions = "non_critical_extension_options"
    }
}

// MARK: - AuthInfo
/// AuthInfo describes the fee and signer modes that are used to sign a
/// transaction.
struct AuthInfo: Codable {
    /// signer_infos defines the signing modes for the required signers. The number
    /// and order of elements must match the required signers from TxBody's
    /// messages. The first element is the primary signer and the one which pays
    /// the fee.
    let signerInfos: [SignerInfo]

    /// Fee is the fee and gas limit for the transaction. The first signer is the
    /// primary signer and the one which pays the fee. The fee can be calculated
    /// based on the cost of evaluating the body and doing signature verification
    /// of the signers. This can be estimated via simulation.
    let fee: Fee?

    /// Tip is the optional tip used for transactions fees paid in another denom.
    let tip: Tip?

    enum CodingKeys: String, CodingKey {
        case signerInfos = "signer_infos"
        case fee
        case tip
    }
}

// MARK: - SignerInfo
/// SignerInfo describes the public key and signing mode of a single top-level
/// signer.
struct SignerInfo: Codable {
    /// public_key is the public key of the signer. It is optional for accounts
    /// that already exist in state. If unset, the verifier can use the required
    /// signer address for this position and lookup the public key.
    let publicKey: CosmosAny?

    /// mode_info describes the signing mode of the signer and is a nested
    /// structure to support nested multisig pubkey's
    let modeInfo: ModeInfo?

    /// sequence is the sequence of the account, which describes the
    /// number of committed transactions signed by a given address. It is used to
    /// prevent replay attacks.
    let sequence: UInt64

    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case modeInfo = "mode_info"
        case sequence
    }
}

// MARK: - ModeInfo
/// ModeInfo describes the signing mode of a single or nested multisig signer.
struct ModeInfo: Codable {
    let single: Single?
    let multi: Multi?

    /// Single is the mode info for a single signer. It is structured as a message
    /// to allow for additional fields such as locale for SIGN_MODE_TEXTUAL in the
    /// future
    struct Single: Codable {
        /// mode is the signing mode of the single signer
        let mode: SignMode
    }

    /// Multi is the mode info for a multisig public key
    struct Multi: Codable {
        /// bitarray specifies which keys within the multisig are signing
        let bitarray: CompactBitArray?

        /// mode_infos is the corresponding modes of the signers of the multisig
        /// which could include nested multisig public keys
        let modeInfos: [ModeInfo]

        enum CodingKeys: String, CodingKey {
            case bitarray
            case modeInfos = "mode_infos"
        }
    }
}

// MARK: - SignMode
/// SignMode represents a signing mode with its own security guarantees.
enum SignMode: String, Codable {
    /// SIGN_MODE_UNSPECIFIED specifies an unknown signing mode and will be rejected
    case unspecified = "SIGN_MODE_UNSPECIFIED"

    /// SIGN_MODE_DIRECT specifies a signing mode which uses SignDoc and is
    /// verified with raw bytes from Tx
    case direct = "SIGN_MODE_DIRECT"

    /// SIGN_MODE_TEXTUAL is a future signing mode that will verify some
    /// human-readable textual representation on top of the binary representation
    /// from SIGN_MODE_DIRECT
    case textual = "SIGN_MODE_TEXTUAL"

    /// SIGN_MODE_DIRECT_AUX specifies a signing mode which uses
    /// SignDocDirectAux. As opposed to SIGN_MODE_DIRECT, this sign mode does not
    /// require signers signing over other signers' `signer_info`
    case directAux = "SIGN_MODE_DIRECT_AUX"

    /// SIGN_MODE_LEGACY_AMINO_JSON is a backwards compatibility mode which uses
    /// Amino JSON and will be removed in the future
    case legacyAminoJson = "SIGN_MODE_LEGACY_AMINO_JSON"

    /// SIGN_MODE_EIP_191 specifies the sign mode for EIP 191 signing on the Cosmos
    /// SDK. Ref: https://eips.ethereum.org/EIPS/eip-191
    case eip191 = "SIGN_MODE_EIP_191"
}

// MARK: - Fee
/// Fee includes the amount of coins paid in fees and the maximum
/// gas to be used by the transaction. The ratio yields an effective "gasprice",
/// which must be above some miminum to be accepted into the mempool.
struct Fee: Codable {
    /// amount is the amount of coins to be paid as a fee
    let amount: [CosmosCoin]

    /// gas_limit is the maximum gas that can be used in transaction processing
    /// before an out of gas error occurs
    let gasLimit: String?

    /// payer is the account paying the transaction fee, not the same as the signer.
    /// If unset, defaults to the first signer
    let payer: String

    /// granter is the account granting the fee allowance to the payer, if any
    let granter: String

    enum CodingKeys: String, CodingKey {
        case amount
        case gasLimit = "gas_limit"
        case payer
        case granter
    }
}

// MARK: - Tip
/// Tip is the tip used for meta-transactions.
struct Tip: Codable {
    /// amount is the amount of the tip
    let amount: [CosmosCoin]

    /// tipper is the address of the account paying for the tip
    let tipper: String
}

// MARK: - AuxSignerData
/// AuxSignerData is the intermediary format that an auxiliary signer (e.g. a
/// tipper) builds and sends to the fee payer (who will build and broadcast the
/// actual tx). AuxSignerData is not a valid tx in itself, and will be rejected
/// by the node if sent directly as-is.
struct AuxSignerData: Codable {
    /// address is the bech32-encoded address of the auxiliary signer. If using
    /// AuxSignerData across different chains, the bech32 prefix of the target
    /// chain (where the final transaction is broadcasted) should be used.
    let address: String

    /// sign_doc is the SIGN_MODE_DIRECT_AUX sign doc that the auxiliary signer
    /// signs. Note: we use the same sign doc even if we're signing with
    /// LEGACY_AMINO_JSON.
    let signDoc: SignDocDirectAux?

    /// mode is the signing mode of the single signer
    let mode: SignMode

    /// sig is the signature of the sign doc.
    let sig: Base64Data

    enum CodingKeys: String, CodingKey {
        case address
        case signDoc = "sign_doc"
        case mode
        case sig
    }
}

// MARK: - Helper Types

/// CosmosAny is used to pack arbitrary content
struct CosmosAny: Codable {
    /// A URL/resource name that uniquely identifies the type of the serialized
    /// protocol buffer message.
    let typeUrl: String

    /// Must be a valid serialized protocol buffer of the above specified type.
    let value: Base64Data

    enum CodingKeys: String, CodingKey {
        case typeUrl = "type_url"
        case value
    }
}

/// CompactBitArray is an implementation of a space efficient bit array.
/// This is used to ensure that the encoded data takes up a minimal amount of
/// space after proto encoding.
struct CompactBitArray: Codable {
    let extraBitsStored: UInt32
    let elems: Base64Data

    enum CodingKeys: String, CodingKey {
        case extraBitsStored = "extra_bits_stored"
        case elems
    }
}

// MARK: - Base64Data Wrapper

/// A dedicated wrapper type for Data that should be encoded/decoded as base64 strings.
/// This avoids the pitfalls of a global Data extension that affects all Data instances.
struct Base64Data: Codable, Hashable {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let base64String = try container.decode(String.self)

        guard let data = base64String.fromBase64() else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid base64 string"
            )
        }

        self.data = data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data.base64EncodedString())
    }
}
