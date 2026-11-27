//
//  SubstrateSignerPayload.swift
//  VultisigApp
//

import BigInt
import Foundation

/// A dApp's polkadot.js `SignerPayloadJSON`, carried verbatim in the keysign memo by the
/// extension's Substrate `signPayload` route. The initiator signs the extrinsic payload it
/// describes and hands the raw signature back to the dApp, so a co-signer must read the memo the
/// same way or the ceremony signs two different messages.
///
/// Fields stay the strings the dApp sent; the typed readers are strict where the extension is
/// lenient, so a payload no real dApp produces is refused rather than guessed at.
struct SubstrateSignerPayload: Equatable {
    let method: String
    let era: String
    let nonce: String
    let tip: String
    let specVersion: String
    let transactionVersion: String
    let genesisHash: String
    let blockHash: String
    /// `CheckMetadataHash` mode as sent (polkadot.js sends a number), empty when omitted.
    let mode: String
    /// `CheckMetadataHash` hash, empty for polkadot.js's `null`.
    let metadataHash: String

    private static let modeDisabled: UInt8 = 0
    private static let modeEnabled: UInt8 = 1
    private static let hashLength = 32
    private static let optionNone: UInt8 = 0x00
    private static let optionSome: UInt8 = 0x01
    /// Balance is `u128` on both runtimes; a wider tip is no balance either decodes.
    private static let balanceBits = 128

    func methodBytes() throws -> Data { try Self.hexBytes("method", method) }
    func eraBytes() throws -> Data { try Self.hexBytes("era", era) }
    func genesisHashBytes() throws -> Data { try Self.hexBytes("genesisHash", genesisHash) }
    func blockHashBytes() throws -> Data {
        let hash = try Self.hexBytes("blockHash", blockHash)
        guard hash.count == Self.hashLength else {
            throw HelperError.runtimeError("Substrate signer payload blockHash is not 32 bytes")
        }
        return hash
    }
    func nonceValue() throws -> UInt32 { try Self.u32("nonce", nonce) }
    func specVersionValue() throws -> UInt32 { try Self.u32("specVersion", specVersion) }
    func transactionVersionValue() throws -> UInt32 { try Self.u32("transactionVersion", transactionVersion) }

    /// The tip as the extension's `BigInt(tip)` reads it: `0x` hex, a decimal string or a JSON
    /// number; absent is zero.
    func tipValue() throws -> BigInt {
        guard !tip.isEmpty else { return .zero }
        let hex = Self.withoutHexPrefix(tip)
        let value = hex.count < tip.count ? BigInt(hex, radix: 16) : BigInt(tip, radix: 10)
        guard let value, value.signum() >= 0, value < BigInt(1) << Self.balanceBits else {
            throw HelperError.runtimeError("Substrate signer payload has a malformed tip")
        }
        return value
    }

    /// The `CheckMetadataHash` mode byte; omitted is 0. The runtime decodes only 0 and 1.
    func modeByte() throws -> UInt8 {
        guard !mode.isEmpty else { return Self.modeDisabled }
        guard let value = UInt8(mode), value == Self.modeDisabled || value == Self.modeEnabled else {
            throw HelperError.runtimeError("Substrate signer payload has a malformed mode")
        }
        return value
    }

    /// SCALE `Option<[u8;32]>` of the metadata hash. The runtime derives it as
    /// `mode == 1 ? Some(hash) : None`, so a hash that disagrees with the mode is refused.
    func metadataHashOption() throws -> Data {
        let enabled = try modeByte() == Self.modeEnabled
        guard enabled == !metadataHash.isEmpty else {
            throw HelperError.runtimeError("Substrate signer payload metadataHash does not match its mode")
        }
        guard enabled else { return Data([Self.optionNone]) }
        let hash = try Self.hexBytes("metadataHash", metadataHash)
        guard hash.count == Self.hashLength else {
            throw HelperError.runtimeError("Substrate signer payload metadataHash is not 32 bytes")
        }
        return Data([Self.optionSome]) + hash
    }

    private static func hexBytes(_ field: String, _ value: String) throws -> Data {
        let hex = withoutHexPrefix(value)
        guard hex.allSatisfy(\.isHexDigit), let bytes = Data(hexString: hex) else {
            throw HelperError.runtimeError("Substrate signer payload field \(field) is not hex")
        }
        return bytes
    }

    private static func u32(_ field: String, _ value: String) throws -> UInt32 {
        guard let number = UInt32(withoutHexPrefix(value), radix: 16) else {
            throw HelperError.runtimeError("Substrate signer payload field \(field) is not a u32")
        }
        return number
    }

    /// Strips `0x` in either case, as Android does.
    private static func withoutHexPrefix(_ value: String) -> String {
        value.lowercased().hasPrefix("0x") ? String(value.dropFirst(2)) : value
    }
}

extension SubstrateSignerPayload {
    /// Reads a signer payload under the extension's rule: a JSON object whose `method` and
    /// `genesisHash` are non-empty strings. Anything else is a plain memo and returns nil.
    static func fromMemo(_ memo: String?) -> SubstrateSignerPayload? {
        guard let data = memo?.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        func string(_ key: String) -> String { json[key] as? String ?? .empty }
        let method = string("method")
        let genesisHash = string("genesisHash")
        guard !method.isEmpty, !genesisHash.isEmpty else { return nil }
        return SubstrateSignerPayload(
            method: method,
            era: string("era"),
            nonce: string("nonce"),
            tip: scalarText(json["tip"]),
            specVersion: string("specVersion"),
            transactionVersion: string("transactionVersion"),
            genesisHash: genesisHash,
            blockHash: string("blockHash"),
            mode: scalarText(json["mode"]),
            metadataHash: string("metadataHash")
        )
    }

    /// The dApp payload a keysign on `chain` carries, or nil for a native send. Only chains with a
    /// `substrateGenesisHash` have the route. The payload's genesis must be that chain's own:
    /// Polkadot and Bittensor sign with the same ed25519 key, so a payload labelled one chain but
    /// bound to the other's genesis would be refused rather than signed.
    static func fromKeysign(chain: Chain, memo: String?) throws -> SubstrateSignerPayload? {
        guard let genesisHash = chain.substrateGenesisHash,
              let payload = fromMemo(memo) else { return nil }
        guard payload.genesisHash.caseInsensitiveCompare(genesisHash) == .orderedSame else {
            throw HelperError.runtimeError("Substrate signer payload genesis hash does not belong to \(chain.name)")
        }
        return payload
    }

    /// A JSON number or string as text; a boolean or any other type is kept unreadable.
    private static func scalarText(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: return .empty
        case let text as String: return text
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): return number.stringValue
        default: return "invalid"
        }
    }
}

extension KeysignPayload {
    /// The dApp signer payload this keysign carries; see `SubstrateSignerPayload.fromKeysign`.
    var substrateDappPayload: SubstrateSignerPayload? {
        get throws { try SubstrateSignerPayload.fromKeysign(chain: coin.chain, memo: memo) }
    }
}
