//
//  CardanoSignedTxBuilder.swift
//  VultisigApp
//

import Foundation

enum CardanoSignedTxBuilderError: Error, Equatable {
    case invalidPublicKeyLength(Int)
    case invalidSignatureLength(Int)
}

/// Hand-built signed Cardano transaction CBOR envelope.
///
/// Mirrors `vultisig-sdk/packages/core/mpc/tx/compile/cardano/buildSignedCardanoTx.ts`.
/// The body bytes are embedded verbatim — re-encoding can change CBOR map ordering
/// or integer widths, which would invalidate the signature.
enum CardanoSignedTxBuilder {

    static let publicKeyLength = 32
    static let signatureLength = 64

    /// Assemble the signed transaction array `[body, witness_set, is_valid,
    /// auxiliary_data]`.
    ///
    /// - Parameter auxData: canonical CIP-20 auxiliary-data CBOR (label 674).
    ///   When `nil` the envelope carries the `null` (`0xF6`) auxiliary-data
    ///   sentinel, as before. When set, WalletCore's `TransactionCompiler` has
    ///   already committed `blake2b-256(auxData)` into the body at map key 7, so
    ///   the aux bytes are embedded verbatim as element [3]. The body, witness,
    ///   and this aux element are byte-identical to what WalletCore's `AnySigner`
    ///   emits; only the envelope framing differs — this SDK/mainnet-verified
    ///   builder uses the 4-element `[body, witness, is_valid, aux]` array while
    ///   `AnySigner` uses the 3-element Shelley `[body, witness, aux]`. The txid
    ///   (`blake2b-256(body)`) is identical either way.
    static func build(txBody: Data, publicKey: Data, signature: Data, auxData: Data? = nil) throws -> Data {
        guard publicKey.count == publicKeyLength else {
            throw CardanoSignedTxBuilderError.invalidPublicKeyLength(publicKey.count)
        }
        guard signature.count == signatureLength else {
            throw CardanoSignedTxBuilderError.invalidSignatureLength(signature.count)
        }

        let witness = buildWitness(publicKey: publicKey, signature: signature)
        let auxElement = auxData ?? Data([0xF6])

        var output = Data(capacity: 1 + txBody.count + witness.count + 1 + auxElement.count)
        output.append(0x84)
        output.append(txBody)
        output.append(witness)
        output.append(0xF5)
        output.append(auxElement)
        return output
    }

    static func cborBytes(_ data: Data) -> Data {
        var out = Data()
        let length = data.count

        if length < 24 {
            out.append(0x40 | UInt8(length))
        } else if length < 256 {
            out.append(0x58)
            out.append(UInt8(length))
        } else {
            out.append(0x59)
            out.append(UInt8((length >> 8) & 0xFF))
            out.append(UInt8(length & 0xFF))
        }
        out.append(data)
        return out
    }

    private static func buildWitness(publicKey: Data, signature: Data) -> Data {
        let vkey = cborBytes(publicKey)
        let sig = cborBytes(signature)

        var witness = Data()
        witness.append(0xA1) // map(1)
        witness.append(0x00) // key: uint(0)
        witness.append(0x81) // array(1)
        witness.append(0x82) // array(2)
        witness.append(vkey)
        witness.append(sig)
        return witness
    }
}
