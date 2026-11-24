//
//  SubstrateTransferCallReader.swift
//  VultisigApp
//

import BigInt
import Foundation
import WalletCore

/// Reads the recipient and value of a `Balances.transfer_allow_death` / `transfer_keep_alive`
/// out of the call a dApp asked the vault to sign, so Verify shows the signed transfer rather
/// than the initiator's `toAddress` / `toAmount`. A port of the extension's `decodeTransferCall`
/// and Android's `SubstrateTransferCallReader`.
///
/// Returns nil for any other call (staking, subnet calls) or for transfer-shaped bytes it cannot
/// read strictly: Verify then shows no amount and the raw payload in the memo, never a guess.
enum SubstrateTransferCallReader {

    struct Transfer: Equatable {
        let destination: Data
        let amount: BigInt
    }

    /// `pallet_balances` sits at index 5 in both the Polkadot relay and Bittensor runtimes.
    private static let balancesPallet: UInt8 = 5
    /// `transfer_allow_death` and `transfer_keep_alive`: the calls shaped recipient + value.
    private static let transferCalls: Set<UInt8> = [0, 3]
    private static let multiAddressId: UInt8 = 0x00
    private static let accountIdLength = 32
    /// Canonical SCALE gives each value one spelling; the runtime refuses any other.
    private static let twoByteMinimum: BigInt = 64
    private static let fourByteMinimum: BigInt = 16_384
    private static let bigIntegerMinimum: BigInt = 1_073_741_824
    /// Balance is `u128` on both runtimes.
    private static let maxBigIntegerBytes = 16

    static func read(_ method: Data) -> Transfer? {
        var reader = ByteReader(bytes: [UInt8](method))
        guard let pallet = reader.u8(), let call = reader.u8(),
              pallet == balancesPallet, transferCalls.contains(call),
              reader.u8() == multiAddressId,
              let destination = reader.bytes(accountIdLength),
              let amount = reader.compact(),
              reader.isExhausted
        else { return nil }
        return Transfer(destination: Data(destination), amount: amount)
    }

    /// SS58 recipient for display; nil off the two Substrate dApp chains.
    static func recipientAddress(_ destination: Data, chain: Chain) -> String? {
        switch chain {
        case .bittensor: BittensorHelper.ss58Encode(publicKey: destination)
        case .polkadot: PublicKey(data: destination, type: .ed25519).map { AnyAddress(publicKey: $0, coin: .polkadot).description }
        default: nil
        }
    }

    private struct ByteReader {
        let bytes: [UInt8]
        var offset = 0

        var isExhausted: Bool { offset == bytes.count }

        mutating func u8() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func bytes(_ length: Int) -> [UInt8]? {
            guard offset + length <= bytes.count else { return nil }
            defer { offset += length }
            return Array(bytes[offset..<offset + length])
        }

        mutating func compact() -> BigInt? {
            guard let first = u8() else { return nil }
            switch first & 0b11 {
            case 0b00:
                return BigInt(first >> 2)
            case 0b01:
                return littleEndian(first: first, extra: 1).flatMap { canonical($0 >> 2, minimum: twoByteMinimum) }
            case 0b10:
                return littleEndian(first: first, extra: 3).flatMap { canonical($0 >> 2, minimum: fourByteMinimum) }
            default:
                let length = Int(first >> 2) + 4
                guard length <= maxBigIntegerBytes, let value = bytes(length), value.last != 0 else { return nil }
                return canonical(BigInt(BigUInt(Data(value.reversed()))), minimum: bigIntegerMinimum)
            }
        }

        private mutating func littleEndian(first: UInt8, extra: Int) -> BigInt? {
            guard let rest = bytes(extra) else { return nil }
            return BigInt(BigUInt(Data(([first] + rest).reversed())))
        }

        private func canonical(_ value: BigInt, minimum: BigInt) -> BigInt? {
            value >= minimum ? value : nil
        }
    }
}
