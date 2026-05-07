//
//  CardanoSignedTxBuilder.swift
//  VultisigApp
//

import Foundation

enum CardanoSignedTxBuilderError: Error, Equatable {
    case invalidPublicKeyLength(Int)
    case invalidSignatureLength(Int)
    case bodyTooLarge(Int)
}

/// Hand-built signed Cardano transaction CBOR envelope.
///
/// Mirrors `vultisig-sdk/packages/core/mpc/tx/compile/cardano/buildSignedCardanoTx.ts`.
/// The body bytes are embedded verbatim — re-encoding can change CBOR map ordering
/// or integer widths, which would invalidate the signature.
enum CardanoSignedTxBuilder {

    static let publicKeyLength = 32
    static let signatureLength = 64
    private static let maxBodyLength = 0xFFFF

    static func build(txBody: Data, publicKey: Data, signature: Data) throws -> Data {
        guard publicKey.count == publicKeyLength else {
            throw CardanoSignedTxBuilderError.invalidPublicKeyLength(publicKey.count)
        }
        guard signature.count == signatureLength else {
            throw CardanoSignedTxBuilderError.invalidSignatureLength(signature.count)
        }
        guard txBody.count <= maxBodyLength else {
            throw CardanoSignedTxBuilderError.bodyTooLarge(txBody.count)
        }

        let witness = buildWitness(publicKey: publicKey, signature: signature)

        var output = Data(capacity: 1 + txBody.count + witness.count + 2)
        output.append(0x84)
        output.append(txBody)
        output.append(witness)
        output.append(0xF5)
        output.append(0xF6)
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
