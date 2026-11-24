//
//  SubstrateDappSigner.swift
//  VultisigApp
//

import Foundation
import WalletCore

/// Signs a dApp's Substrate `SignerPayloadJSON` the way the extension does
/// (`constructPolkadotSigningPayload`): the extrinsic payload is assembled from the dApp's fields
/// and signed as-is. The dApp wraps the signature around its own call and submits it, so nothing
/// is compiled or broadcast here (`KeysignPayload.skipsBroadcast`).
enum SubstrateDappSigner {

    /// Past this many bytes the runtime signs `blake2b_256(payload)` instead of the payload.
    private static let hashThresholdBytes = 256

    /// `method ‖ era ‖ compact(nonce) ‖ compact(tip) ‖ mode ‖ u32le(specVersion) ‖
    /// u32le(transactionVersion) ‖ genesisHash ‖ blockHash ‖ Option<metadataHash>`.
    /// The `CheckMetadataHash` bytes are always present: both runtimes sign that extension and
    /// the extension appends them whatever `signedExtensions` lists. Bittensor's own extensions
    /// (`SubtensorTransactionExtension`, `DrandPriority`, …) add no bytes.
    static func signingBytes(_ payload: SubstrateSignerPayload) throws -> Data {
        var raw = try payload.methodBytes()
        raw += try payload.eraBytes()
        raw += BittensorHelper.compactEncode(UInt64(try payload.nonceValue()))
        raw += BittensorHelper.compactEncode(try payload.tipValue())
        raw.append(try payload.modeByte())
        raw += littleEndian(try payload.specVersionValue())
        raw += littleEndian(try payload.transactionVersionValue())
        raw += try payload.genesisHashBytes()
        raw += try payload.blockHashBytes()
        raw += try payload.metadataHashOption()
        return raw.count > hashThresholdBytes ? Hash.blake2b(data: raw, size: 32) : raw
    }

    static func getPreSignedImageHash(_ payload: SubstrateSignerPayload) throws -> [String] {
        [try signingBytes(payload).hexString]
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
