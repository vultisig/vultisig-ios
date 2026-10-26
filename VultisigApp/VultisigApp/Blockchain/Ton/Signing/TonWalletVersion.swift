//
//  TonWalletVersion.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import WalletCore

/// The wallet contracts a Vultisig TON account can live in. The same Ed25519 key
/// yields a different address under each, so they are different accounts.
enum TonWalletVersion {
    case v4r2
    case v5r1

    /// W5R1 mainnet wallet id; WalletCore hardcodes it for `walletV5R1`.
    private static let v5r1WalletId: Int32 = 2_147_483_409

    var maxMessagesPerRequest: Int {
        switch self {
        case .v4r2: return 4
        case .v5r1: return 255
        }
    }

    var walletCoreVersion: TheOpenNetworkWalletVersion {
        switch self {
        case .v4r2: return .walletV4R2
        case .v5r1: return .walletV5R1
        }
    }

    /// The keysign payload carries no wallet-version field, so the sender address is the
    /// contract's identity: derive both candidates from the key and match. An address that is
    /// neither is refused rather than assumed V4R2.
    static func resolve(senderAddress: String, publicKeyData: Data) throws -> TonWalletVersion {
        guard let sender = accountHash(friendlyAddress: senderAddress) else {
            throw HelperError.runtimeError("invalid TON sender address: \(senderAddress)")
        }
        guard let publicKey = PublicKey(data: publicKeyData, type: .ed25519) else {
            throw HelperError.runtimeError("invalid TON public key")
        }

        let v4r2 = accountHash(friendlyAddress: AnyAddress(publicKey: publicKey, coin: .ton).description)
        if sender == v4r2 {
            return .v4r2
        }
        if sender == v5r1AccountHash(publicKey: publicKey) {
            return .v5r1
        }
        throw HelperError.runtimeError("TON address \(senderAddress) is not this key's V4R2 or W5 wallet")
    }

    /// Workchain-0 account id of a user-friendly address: the 32 bytes after the tag and workchain bytes.
    private static func accountHash(friendlyAddress: String) -> Data? {
        let base64 = friendlyAddress
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let bytes = Data(base64Encoded: base64), bytes.count == 36, bytes[1] == 0 else {
            return nil
        }
        return bytes.subdata(in: 2..<34)
    }

    /// The account id is the representation hash of the StateInit cell WalletCore builds for the key.
    private static func v5r1AccountHash(publicKey: PublicKey) -> Data? {
        guard let boc = TONWallet.buildV5R1StateInit(publicKey: publicKey, workchain: 0, walletId: v5r1WalletId),
              let bytes = Data(base64Encoded: boc) else {
            return nil
        }
        return BagOfCells.rootHash(bytes)
    }
}

/// Just enough of the TON bag-of-cells format to hash the root of a WalletCore StateInit:
/// ordinary cells only, no index, single root.
private enum BagOfCells {
    static func rootHash(_ boc: Data) -> Data? {
        let b = [UInt8](boc)
        guard b.count > 6, b[0..<4].elementsEqual([0xB5, 0xEE, 0x9C, 0x72]) else { return nil }
        let flags = b[4]
        guard flags & 0x80 == 0 else { return nil } // indexed BoC unsupported; a trailing crc32c is ignored
        let refSize = Int(flags & 0x07)
        let offSize = Int(b[5])
        var pos = 6

        func read(_ size: Int) -> Int? {
            guard size > 0, pos + size <= b.count else { return nil }
            defer { pos += size }
            return b[pos..<pos + size].reduce(0) { $0 << 8 | Int($1) }
        }

        guard let cellCount = read(refSize), let rootCount = read(refSize), rootCount == 1,
              read(refSize) != nil, read(offSize) != nil, // absent, total cells size
              let rootIndex = read(refSize), rootIndex == 0 else { return nil }

        var cells: [(d2: UInt8, data: [UInt8], refs: [Int])] = []
        for _ in 0..<cellCount {
            guard pos + 2 <= b.count else { return nil }
            let d1 = Int(b[pos]), d2 = Int(b[pos + 1])
            pos += 2
            let refCount = d1 & 0x07
            let dataLength = (d2 + 1) / 2
            guard d1 & 0xF8 == 0, pos + dataLength <= b.count else { return nil } // ordinary level-0 only
            let data = Array(b[pos..<pos + dataLength])
            pos += dataLength
            var refs: [Int] = []
            for _ in 0..<refCount {
                guard let ref = read(refSize) else { return nil }
                refs.append(ref)
            }
            cells.append((UInt8(d2), data, refs))
        }

        // Children always sit after their parent, so hash from the last cell back to the root.
        var hashes = [[UInt8]](repeating: [], count: cellCount)
        var depths = [Int](repeating: 0, count: cellCount)
        for index in stride(from: cellCount - 1, through: 0, by: -1) {
            let cell = cells[index]
            var repr: [UInt8] = [UInt8(cell.refs.count), cell.d2]
            repr += cell.data
            var depth = 0
            for ref in cell.refs {
                guard ref > index else { return nil }
                depth = max(depth, depths[ref] + 1)
                repr += [UInt8(depths[ref] >> 8), UInt8(depths[ref] & 0xFF)]
            }
            for ref in cell.refs { repr += hashes[ref] }
            depths[index] = depth
            hashes[index] = Array(SHA256.hash(data: repr))
        }
        return Data(hashes[0])
    }
}
