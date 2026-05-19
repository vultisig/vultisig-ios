//
//  BtcAddressType.swift
//  VultisigApp
//
//  Bitcoin address types supported by the QBTC claim flow,
//  and the ZK circuit each one maps to.
//

import Foundation

enum BtcClaimCircuit {
    case ecdsa
    case schnorr
}

enum BtcAddressType {
    case p2pkh
    case p2wpkh
    case p2shP2wpkh
    case p2wsh
    case p2tr

    var circuit: BtcClaimCircuit {
        switch self {
        case .p2pkh, .p2wpkh, .p2shP2wpkh, .p2wsh:
            return .ecdsa
        case .p2tr:
            return .schnorr
        }
    }
}

enum BtcAddressTypeError: LocalizedError {
    case unsupportedAddressFormat(String)
    case testnetNotSupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAddressFormat(let address):
            return "Unsupported Bitcoin address format: \(address)"
        case .testnetNotSupported(let address):
            return "Testnet Bitcoin addresses are not supported for QBTC claim: \(address)"
        }
    }
}

// Detection rules mirror vultisig-sdk/.../detectBtcAddressType.ts.
// | Format               | Type        |
// | `1...`               | P2PKH       |
// | `3...`               | P2SH-P2WPKH |
// | `bc1q...` (42 chars) | P2WPKH      |
// | `bc1q...` (62 chars) | P2WSH       |
// | `bc1p...` (62 chars) | P2TR        |
// Testnet (`tb1...`) is rejected — the chain does not support it today.
extension BtcAddressType {
    static func detect(_ address: String) throws -> BtcAddressType {
        if address.hasPrefix("tb1") {
            throw BtcAddressTypeError.testnetNotSupported(address)
        }

        if address.hasPrefix("1") {
            return .p2pkh
        }

        if address.hasPrefix("3") {
            return .p2shP2wpkh
        }

        if address.hasPrefix("bc1p") {
            guard address.count == 62 else {
                throw BtcAddressTypeError.unsupportedAddressFormat(address)
            }
            return .p2tr
        }

        if address.hasPrefix("bc1q") {
            switch address.count {
            case 42:
                return .p2wpkh
            case 62:
                return .p2wsh
            default:
                throw BtcAddressTypeError.unsupportedAddressFormat(address)
            }
        }

        throw BtcAddressTypeError.unsupportedAddressFormat(address)
    }
}
