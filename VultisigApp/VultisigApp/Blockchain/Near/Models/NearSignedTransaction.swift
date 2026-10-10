//
//  NearSignedTransaction.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import WalletCore

/// WalletCore emits the signed transaction as bare Borsh — no length prefix, no
/// container — so the pieces have to be found by their fixed widths, exactly as
/// nearcore lays them out in `core/primitives/src/transaction.rs`.
enum NearSignedTransaction {

    static let blockHashBytes = 32
    static let ed25519PublicKeyBytes = 32

    private static let ed25519KeyType: UInt8 = 0x00
    private static let ed25519SignatureBytes = 64
    private static let accountIdLengthBytes = 4

    /// The chain's transaction id: `sha256(borsh(TransactionV0))`, base58.
    ///
    /// nearcore sets `SignedTransaction.hash` to `Transaction::get_hash_and_size()`
    /// (`transaction.rs`), and V0 serializes with no variant tag — so the id is
    /// the digest that was *signed*, not the hash of the signed bytes. Hashing
    /// the whole envelope would produce a base58 string that no node recognizes
    /// as this transaction, which is why the split is not optional.
    static func transactionHash(signedTransaction: Data) throws -> String {
        Base58.encodeNoCheck(data: Data(SHA256.hash(data: try body(of: signedTransaction))))
    }

    /// Signer account, read from the body's leading Borsh `AccountId`
    /// (u32-LE length + UTF-8). NEAR's `tx` status lookup is sharded by sender,
    /// so the status call needs this and not just the hash.
    static func signerId(signedTransaction: Data) throws -> String {
        let body = try body(of: signedTransaction)
        guard body.count >= accountIdLengthBytes else {
            throw NearError.malformedSignedTransaction("too short to carry a signer account id")
        }
        let start = body.startIndex
        let length = Int(body[start]) | Int(body[start + 1]) << 8 | Int(body[start + 2]) << 16 | Int(body[start + 3]) << 24
        guard length > 0, accountIdLengthBytes + length <= body.count else {
            throw NearError.malformedSignedTransaction("carries a malformed signer account id")
        }
        let idBytes = body[(start + accountIdLengthBytes)..<(start + accountIdLengthBytes + length)]
        guard let accountId = String(data: Data(idBytes), encoding: .utf8) else {
            throw NearError.malformedSignedTransaction("signer account id is not UTF-8")
        }
        return accountId
    }

    /// The bare `TransactionV0` body: everything before the key-type byte and
    /// the Ed25519 signature. WalletCore signs with Ed25519 only, so the
    /// envelope is 65 bytes and the body is the prefix.
    private static func body(of signedTransaction: Data) throws -> Data {
        let bodyLength = signedTransaction.count - ed25519SignatureBytes - 1
        guard bodyLength > 0 else {
            throw NearError.malformedSignedTransaction("too short to carry a body and an Ed25519 signature")
        }
        let start = signedTransaction.startIndex
        guard signedTransaction[start + bodyLength] == ed25519KeyType else {
            throw NearError.malformedSignedTransaction("does not carry an Ed25519 signature")
        }
        return signedTransaction[start..<(start + bodyLength)]
    }
}
