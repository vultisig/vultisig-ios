//
//  TronContractPayloadGuard.swift
//  VultisigApp
//

import BigInt
import Foundation
import WalletCore

/// Binds a dApp TRON contract payload to the payload's top-level fields before
/// it is signed.
///
/// Verify shows `coin`, `toAddress` and `toAmount`, but `TronHelper` signs the
/// typed contract verbatim. Initiator and co-signer both run this on the
/// signing path, so a payload whose display fields disagree with the bytes it
/// signs fails keysign instead of being co-signed. Mirrors the Android guard so
/// every platform refuses the same payloads.
enum TronContractPayloadGuard {

    private static let trc20TransferSelector = Data([0xa9, 0x05, 0x9c, 0xbb])
    private static let abiWordLength = 32
    private static let addressLength = 21
    private static let addressPrefix: UInt8 = 0x41

    static func check(_ keysignPayload: KeysignPayload, contract: TronTransferContractPayload) throws {
        try requireOwner(keysignPayload, contract.ownerAddress)
        guard keysignPayload.coin.isNativeToken else {
            throw failure("a TRX transfer must be signed as native TRX")
        }
        try requireRecipient(keysignPayload, contract.toAddress)
        try requireAmount(keysignPayload, contract.amount)
    }

    /// The initiator displays a TRC-10 transfer by ticker only, so `assetName`
    /// cannot be bound to the displayed coin; refuse rather than co-sign it.
    static func rejectTrc10Transfer() throws {
        throw failure("TRC-10 transfers are not supported")
    }

    static func check(_ keysignPayload: KeysignPayload, contract: TronTriggerSmartContractPayload) throws {
        try requireOwner(keysignPayload, contract.ownerAddress)
        let callValue = try optionalAmount(contract.callValue, field: "call value")
        let callTokenValue = try optionalAmount(contract.callTokenValue, field: "TRC-10 call value")
        guard callTokenValue == 0 else {
            throw failure("a contract call must not attach TRC-10 tokens")
        }

        let calldata = try contractData(from: contract.data)
        guard let transfer = decodeTrc20Transfer(calldata) else {
            guard !calldata.starts(with: trc20TransferSelector) else {
                throw failure("TRC-20 transfer calldata is not canonical")
            }
            guard callValue == 0 || keysignPayload.coin.isNativeToken else {
                throw failure("a contract call attaching TRX must be shown as TRX")
            }
            try requireRecipient(keysignPayload, contract.contractAddress)
            guard callValue == keysignPayload.toAmount else {
                throw failure("the contract call value does not match the displayed amount")
            }
            return
        }

        guard callValue == 0 else {
            throw failure("a TRC-20 transfer must not attach TRX")
        }
        guard !keysignPayload.coin.isNativeToken,
              let tokenBytes = addressBytes(keysignPayload.coin.contractAddress),
              tokenBytes == addressBytes(contract.contractAddress) else {
            throw failure("the TRC-20 contract does not match the displayed token")
        }
        guard let displayedRecipient = addressBytes(keysignPayload.toAddress),
              displayedRecipient == transfer.recipient else {
            throw failure("the TRC-20 transfer recipient does not match the displayed recipient")
        }
        guard transfer.amount == keysignPayload.toAmount else {
            throw failure("the TRC-20 transfer amount does not match the displayed amount")
        }
    }

    /// The exact bytes `TronHelper` places in `TriggerSmartContract.data`;
    /// the guard decodes the same bytes the signer signs. `0x`-prefixed data and
    /// bare hex must be well-formed: a malformed encoding is rejected rather than
    /// signed as empty calldata.
    static func contractData(from data: String?) throws -> Data {
        guard let data, !data.isEmpty else { return Data() }
        if data.hasPrefix("0x") {
            return try hexBytes(String(data.dropFirst(2)))
        }
        if data.allSatisfy({ $0.isHexDigit }) {
            return try hexBytes(data)
        }
        return Data(data.utf8)
    }

    /// The signed calldata as `0x` hex, for Verify to decode like EVM calldata;
    /// nil when the call carries none or cannot be read (signing is refused then).
    static func calldataHex(from data: String?) -> String? {
        guard let bytes = try? contractData(from: data) else { return nil }
        return bytes.isEmpty ? nil : "0x" + bytes.hexString
    }

    private static func hexBytes(_ hex: String) throws -> Data {
        guard hex.count.isMultiple(of: 2), hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw failure("the contract call data is not valid hex")
        }
        guard !hex.isEmpty else { return Data() }
        guard let bytes = Data(hexString: hex) else {
            throw failure("the contract call data is not valid hex")
        }
        return bytes
    }

    // MARK: - Checks

    private static func requireOwner(_ keysignPayload: KeysignPayload, _ owner: String) throws {
        guard let ownerBytes = addressBytes(owner),
              ownerBytes == addressBytes(keysignPayload.coin.address) else {
            throw failure("the contract owner is not the vault address")
        }
    }

    private static func requireRecipient(_ keysignPayload: KeysignPayload, _ recipient: String) throws {
        guard let signed = addressBytes(recipient),
              signed == addressBytes(keysignPayload.toAddress) else {
            throw failure("the contract recipient does not match the displayed recipient")
        }
    }

    private static func requireAmount(_ keysignPayload: KeysignPayload, _ amount: String) throws {
        guard let signed = parseAmount(amount), signed == keysignPayload.toAmount else {
            throw failure("the contract amount does not match the displayed amount")
        }
    }

    // MARK: - Decoding

    private struct Trc20Transfer {
        let recipient: Data
        let amount: BigInt
    }

    /// Only the canonical 68-byte encoding counts as a transfer: trailing bytes
    /// or a non-zero address pad would be signed without being bound to Verify.
    private static func decodeTrc20Transfer(_ data: Data) -> Trc20Transfer? {
        let bytes = Data(data)
        guard bytes.count == 4 + 2 * abiWordLength,
              bytes.prefix(4) == trc20TransferSelector else {
            return nil
        }
        let recipientWord = bytes.subdata(in: 4..<(4 + abiWordLength))
        guard recipientWord.prefix(abiWordLength - 20).allSatisfy({ $0 == 0 }) else { return nil }
        let amountWord = bytes.subdata(in: (4 + abiWordLength)..<(4 + 2 * abiWordLength))
        return Trc20Transfer(
            recipient: Data([addressPrefix]) + recipientWord.suffix(20),
            amount: BigInt(BigUInt(amountWord))
        )
    }

    /// 21-byte `0x41`-prefixed form of a Base58Check or hex TRON address.
    private static func addressBytes(_ address: String) -> Data? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        let bytes: Data?
        if hex.count == addressLength * 2, hex.allSatisfy({ $0.isHexDigit }) {
            bytes = Data(hexString: hex)
        } else {
            bytes = Base58.decode(string: trimmed)
        }
        guard let bytes, bytes.count == addressLength, bytes.first == addressPrefix else { return nil }
        return bytes
    }

    private static func parseAmount(_ value: String) -> BigInt? {
        guard value.allSatisfy({ $0.isASCII && $0.isNumber }), !value.isEmpty,
              let amount = BigInt(value), amount <= BigInt(Int64.max) else {
            return nil
        }
        return amount
    }

    private static func optionalAmount(_ value: String?, field: String) throws -> BigInt {
        guard let value else { return 0 }
        guard let amount = parseAmount(value) else {
            throw failure("the contract \(field) is not a valid amount")
        }
        return amount
    }

    private static func failure(_ reason: String) -> HelperError {
        HelperError.runtimeError("TRON contract payload rejected: \(reason)")
    }
}
