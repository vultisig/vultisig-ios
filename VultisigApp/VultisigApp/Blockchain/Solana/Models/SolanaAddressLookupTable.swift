//
//  SolanaAddressLookupTable.swift
//  VultisigApp
//

import Foundation
import WalletCore

enum SolanaAddressLookupTableError: Error, LocalizedError, Equatable {
    case accountNotFound(String)
    case wrongOwner(table: String, owner: String)
    case unsupportedEncoding(table: String)
    case malformedAccountData(table: String)
    case uninitialized(table: String)

    var errorDescription: String? {
        switch self {
        case .accountNotFound(let table):
            return "Address lookup table \(table) does not exist on chain"
        case .wrongOwner(let table, let owner):
            return "Account \(table) is owned by \(owner), not the Address Lookup Table program"
        case .unsupportedEncoding(let table):
            return "Address lookup table \(table) was returned in an unexpected encoding"
        case .malformedAccountData(let table):
            return "Address lookup table \(table) has malformed account data"
        case .uninitialized(let table):
            return "Address lookup table \(table) is not initialized"
        }
    }
}

/// Supplies the contents of Address Lookup Tables. Injected so a validator can be
/// exercised against pinned table contents instead of the network.
protocol SolanaAddressLookupTableFetching {
    /// - Returns: table address to that table's full address list. Every
    ///   requested address must be present in the result.
    func fetchAddressLookupTables(addresses: [String]) async throws -> [String: [String]]
}

/// Decoder for an on-chain Address Lookup Table account.
///
/// A v0 transaction addresses lookup-table-loaded accounts by *position*, so an
/// index on its own says nothing about which account is being touched. Anything
/// that reasons about what a transaction actually does — which is the whole point
/// of validating one before signing it — has to resolve those positions against
/// the table's real contents, which means reading the account.
///
/// The account is read as raw `base64` rather than `jsonParsed`. `jsonParsed`
/// would hand the decode to whichever RPC node answered, and the addresses it
/// returns are what the app then compares its safety checks against; decoding the
/// bytes here keeps that step deterministic and testable.
enum SolanaAddressLookupTable {

    /// Owner every lookup-table account must have.
    static let programId = "AddressLookupTab1e1111111111111111111111111"

    /// `LookupTableMeta` occupies a fixed 56-byte prefix — the 4-byte bincode
    /// enum discriminant, `deactivation_slot` (u64), `last_extended_slot` (u64),
    /// `last_extended_slot_start_index` (u8), an `Option<Pubkey>` authority
    /// (1 + 32) and 2 bytes of padding. The address list starts immediately after.
    static let metadataSize = 56

    /// `ProgramState::LookupTable`. `0` is `Uninitialized`, which carries no
    /// addresses at all.
    static let lookupTableDiscriminant: UInt32 = 1

    /// Decodes the address list from a `getAccountInfo` result.
    ///
    /// - Parameters:
    ///   - table: the table's own address, used only for error messages.
    ///   - owner: the account's owner as reported by the RPC.
    ///   - data: the `data` array, `[payload, encoding]`.
    static func addresses(table: String, owner: String, data: [String]) throws -> [String] {
        guard owner == programId else {
            throw SolanaAddressLookupTableError.wrongOwner(table: table, owner: owner)
        }
        guard data.count >= 2, data[1] == "base64", let payload = Data(base64Encoded: data[0]) else {
            throw SolanaAddressLookupTableError.unsupportedEncoding(table: table)
        }
        return try addresses(table: table, accountData: [UInt8](payload))
    }

    static func addresses(table: String, accountData: [UInt8]) throws -> [String] {
        guard accountData.count >= metadataSize else {
            throw SolanaAddressLookupTableError.malformedAccountData(table: table)
        }

        let discriminant = accountData[0..<4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard discriminant == lookupTableDiscriminant else {
            throw SolanaAddressLookupTableError.uninitialized(table: table)
        }

        let body = accountData.count - metadataSize
        // A trailing partial key would mean the table was decoded at the wrong
        // offset, and every address after that point would be wrong by some
        // number of bytes rather than obviously invalid.
        guard body % 32 == 0 else {
            throw SolanaAddressLookupTableError.malformedAccountData(table: table)
        }

        return stride(from: metadataSize, to: accountData.count, by: 32).map { offset in
            Base58.encodeNoCheck(data: Data(accountData[offset..<(offset + 32)]))
        }
    }
}
