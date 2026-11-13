//
//  HyperliquidTypedData.swift
//  VultisigApp
//
//  The two EIP-712 shapes Hyperliquid signs:
//    - L1 actions (orders, leverage, cancels): a "phantom agent"
//      `Agent{source, connectionId}` under domain Exchange/1/1337/0x0, where
//      `connectionId = keccak(msgpack(action) ‖ nonce(BE8) ‖ vaultMarker)`.
//    - User-signed actions (approveAgent, approveBuilderFee, withdraw, ...):
//      the action's own fields under domain HyperliquidSignTransaction/1/
//      signatureChainId/0x0.
//
//  The digest is computed natively here (flat structs only, which is all
//  Hyperliquid uses) AND rendered as `eth_signTypedData_v4` JSON so the vault
//  signs it through the existing `CustomMessagePayload` keysign path. Unit
//  tests pin both against the Vultisig SDK's `hlOrder.ts` vectors and
//  WalletCore's `EthereumAbi.encodeTyped`.
//

import Foundation
import WalletCore

enum HLTypedValue: Equatable, Sendable {
    case string(String)
    /// 20-byte address, rendered as lowercase 0x-hex.
    case address(Data)
    case bytes32(Data)
    case uint64(UInt64)
    /// A uint256 field whose value fits 64 bits (token amounts, timestamps).
    case uint256(UInt64)

    var solidityType: String {
        switch self {
        case .string: return "string"
        case .address: return "address"
        case .bytes32: return "bytes32"
        case .uint64: return "uint64"
        case .uint256: return "uint256"
        }
    }
}

struct HLTypedField: Equatable, Sendable {
    let name: String
    let value: HLTypedValue
}

struct HLTypedDomain: Equatable, Sendable {
    let name: String
    let version: String
    let chainId: UInt64
    let verifyingContract: Data

    static let exchange = HLTypedDomain(name: "Exchange", version: "1", chainId: 1337, verifyingContract: Data(count: 20))

    static func userSigned(signatureChainId: UInt64) -> HLTypedDomain {
        HLTypedDomain(name: "HyperliquidSignTransaction", version: "1", chainId: signatureChainId, verifyingContract: Data(count: 20))
    }
}

/// A flat EIP-712 message: one primary struct of primitive fields.
struct HLTypedData: Equatable, Sendable {
    let domain: HLTypedDomain
    let primaryType: String
    let fields: [HLTypedField]

    var digest: Data {
        var preimage = Data([0x19, 0x01])
        preimage.append(domainSeparator)
        preimage.append(structHash)
        return Hash.keccak256(data: preimage)
    }

    var domainSeparator: Data {
        let typeHash = Hash.keccak256(data: Data("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8))
        var encoded = typeHash
        encoded.append(Hash.keccak256(data: Data(domain.name.utf8)))
        encoded.append(Hash.keccak256(data: Data(domain.version.utf8)))
        encoded.append(HLTypedData.word(domain.chainId))
        encoded.append(HLTypedData.leftPad(domain.verifyingContract))
        return Hash.keccak256(data: encoded)
    }

    var structHash: Data {
        let signature = primaryType + "(" + fields.map { "\($0.value.solidityType) \($0.name)" }.joined(separator: ",") + ")"
        var encoded = Hash.keccak256(data: Data(signature.utf8))
        for field in fields {
            switch field.value {
            case .string(let text): encoded.append(Hash.keccak256(data: Data(text.utf8)))
            case .address(let bytes): encoded.append(HLTypedData.leftPad(bytes))
            case .bytes32(let bytes): encoded.append(bytes)
            case .uint64(let number), .uint256(let number): encoded.append(HLTypedData.word(number))
            }
        }
        return Hash.keccak256(data: encoded)
    }

    /// `eth_signTypedData_v4` payload, the format `CustomMessagePayload` signs.
    var signTypedDataV4JSON: String {
        let fieldTypes = fields.map { "{\"name\":\"\($0.name)\",\"type\":\"\($0.value.solidityType)\"}" }.joined(separator: ",")
        let message = fields.map { field -> String in
            let value: String
            switch field.value {
            case .string(let text): value = HLValue.string(text).jsonString
            case .address(let bytes): value = "\"0x\(bytes.hexString)\""
            case .bytes32(let bytes): value = "\"0x\(bytes.hexString)\""
            case .uint64(let number), .uint256(let number): value = String(number)
            }
            return "\"\(field.name)\":\(value)"
        }.joined(separator: ",")
        let domainTypes = "[{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"version\",\"type\":\"string\"},"
            + "{\"name\":\"chainId\",\"type\":\"uint256\"},{\"name\":\"verifyingContract\",\"type\":\"address\"}]"
        let domainJSON = "{\"name\":\(HLValue.string(domain.name).jsonString),\"version\":\(HLValue.string(domain.version).jsonString),"
            + "\"chainId\":\(domain.chainId),\"verifyingContract\":\"0x\(domain.verifyingContract.hexString)\"}"
        return "{\"types\":{\"EIP712Domain\":\(domainTypes),\(HLValue.string(primaryType).jsonString):[\(fieldTypes)]},"
            + "\"primaryType\":\(HLValue.string(primaryType).jsonString),\"domain\":\(domainJSON),\"message\":{\(message)}}"
    }

    private static func word(_ number: UInt64) -> Data {
        var out = Data(count: 24)
        HLMsgPack.appendBigEndian(number, into: &out)
        return out
    }

    private static func leftPad(_ bytes: Data) -> Data {
        Data(count: max(0, 32 - bytes.count)) + bytes
    }
}

enum HLSigningError: Error, Equatable {
    case invalidAddress(String)
    case invalidSignatureChainId(String)
}

enum HLActionHasher {
    /// `keccak(msgpack(action) ‖ nonce BE8 ‖ 0x00 | 0x01‖vault [‖ 0x00 ‖ expiresAfter BE8])`,
    /// byte-for-byte with the Python SDK's `action_hash` and the Vultisig SDK's `computeHlDigest`.
    static func connectionId(action: HLValue, nonce: UInt64, vaultAddress: String?, expiresAfter: UInt64? = nil) throws -> Data {
        var data = try HLMsgPack.encode(action)
        HLMsgPack.appendBigEndian(nonce, into: &data)
        if let vaultAddress {
            data.append(0x01)
            data.append(try HLAddress.bytes(vaultAddress))
        } else {
            data.append(0x00)
        }
        if let expiresAfter {
            data.append(0x00)
            HLMsgPack.appendBigEndian(expiresAfter, into: &data)
        }
        return Hash.keccak256(data: data)
    }

    static func l1TypedData(
        action: HLValue,
        nonce: UInt64,
        isMainnet: Bool,
        vaultAddress: String? = nil,
        expiresAfter: UInt64? = nil
    ) throws -> HLTypedData {
        let connectionId = try connectionId(action: action, nonce: nonce, vaultAddress: vaultAddress, expiresAfter: expiresAfter)
        return HLTypedData(
            domain: .exchange,
            primaryType: "Agent",
            fields: [
                HLTypedField(name: "source", value: .string(isMainnet ? "a" : "b")),
                HLTypedField(name: "connectionId", value: .bytes32(connectionId))
            ]
        )
    }
}

enum HLAddress {
    static func bytes(_ address: String) throws -> Data {
        let hex = address.hasPrefix("0x") || address.hasPrefix("0X") ? String(address.dropFirst(2)) : address
        guard hex.count == 40, hex.allSatisfy(\.isHexDigit), let data = Data(hexString: hex) else {
            throw HLSigningError.invalidAddress(address)
        }
        return data
    }
}
