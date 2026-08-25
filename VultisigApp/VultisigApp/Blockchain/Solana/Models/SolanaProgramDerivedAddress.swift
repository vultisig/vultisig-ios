//
//  SolanaProgramDerivedAddress.swift
//  VultisigApp
//

import BigInt
import Foundation
import WalletCore

/// Solana's `findProgramAddress`, locally.
///
/// A program-derived address is a function of its seeds and its program, so an
/// account that claims to be one can be RECOMPUTED rather than believed. That is
/// the only way to say whose account it is without asking the network — which
/// matters on the verify screen, where the decode runs offline and every account
/// identity that lives in an address lookup table is already out of reach.
///
/// `SolanaAssociatedTokenAccount` answers the same question for token accounts
/// through WalletCore's dedicated helper. This is the general form, for the
/// program accounts that have no such helper.
enum SolanaProgramDerivedAddress {

    /// Appended to the seeds before hashing, so a PDA can never collide with the
    /// hash of an ordinary account derivation.
    private static let marker = Data("ProgramDerivedAddress".utf8)

    /// The canonical program-derived address for `seeds` under `programId`, or
    /// `nil` when none of the 256 bumps yields one.
    ///
    /// The canonical address is the one at the HIGHEST bump whose hash falls off
    /// the ed25519 curve — an on-curve hash is an ordinary public key that
    /// somebody could hold the private key for, so it is skipped rather than
    /// returned. Searching downward from 255 is what makes the answer unique.
    static func find(seeds: [Data], programId: String) -> String? {
        guard let program = Base58.decodeNoCheck(string: programId), program.count == 32 else { return nil }
        // Solana allows 16 seeds in total and the bump occupies the last slot,
        // so a caller may supply at most 15.
        guard seeds.allSatisfy({ $0.count <= 32 }), seeds.count < 16 else { return nil }

        // 255 down to 1, matching the runtime. Bump 0 is not a value
        // `findProgramAddress` ever returns, so accepting it here would derive
        // an address the chain does not agree is one.
        let prefix = seeds.reduce(Data(), +)
        for bump in stride(from: UInt8(255), through: 1, by: -1) {
            var input = prefix
            input.append(bump)
            input.append(program)
            input.append(marker)

            let candidate = Hash.sha256(data: input)
            guard candidate.count == 32, !isOnEd25519Curve(candidate) else { continue }
            return Base58.encodeNoCheck(data: candidate)
        }
        return nil
    }

    // MARK: - Curve membership

    private static let fieldModulus = BigInt(2).power(255) - 19

    /// Whether a base58 Solana address is an ordinary ed25519 public key.
    static func isOnEd25519Curve(_ address: String) -> Bool {
        guard let bytes = Base58.decodeNoCheck(string: address) else { return false }
        return isOnEd25519Curve(bytes)
    }

    /// Whether these 32 bytes decompress to a point on the ed25519 curve — i.e.
    /// whether they are a possible public key rather than a program address.
    ///
    /// Standard point decompression: the bytes are a little-endian `y` with the
    /// sign of `x` in the top bit, and the curve gives `x² = (y² − 1)/(dy² + 1)`.
    /// If that has no square root, nobody holds a key for this address.
    static func isOnEd25519Curve(_ bytes: Data) -> Bool {
        guard bytes.count == 32 else { return false }

        let p = fieldModulus

        // Built a byte at a time rather than through a `Data` initializer, so
        // the byte order is stated here instead of inherited from an integer
        // library's convention: ed25519 encodes `y` little-endian with the sign
        // of `x` in the top bit.
        var value = BigInt(0)
        for byte in bytes.reversed() {
            value = (value << 8) | BigInt(byte)
        }
        let signBit = BigInt(1) << 255
        let hasSignBit = value >= signBit
        if hasSignBit { value -= signBit }
        guard value < p else { return false }

        // The curve gives `x² = (y² − 1)/(dy² + 1)`. Whether an `x` EXISTS is all
        // that decides curve membership, and that is Euler's criterion — the
        // right-hand side is a square exactly when it raises to `(p−1)/2` as 0
        // or 1. Computing the square root itself would answer the same question
        // through three more modular steps and a sign case, each of which is a
        // place to be subtly wrong; this way there is one modular exponentiation
        // and nothing to get backwards.
        //
        // Every intermediate is reduced through `mod`, NOT `%`. Swift's
        // remainder truncates toward zero, so `(y² − 1) % p` stays negative for
        // `y < 1` and every product built on it inherits the sign — and a
        // negative residue compared against a reduced one silently disagrees,
        // which here would mean calling a real public key a program address.
        let d = mod((p - 121_665) * modularInverse(BigInt(121_666), p), p)
        let ySquared = mod(value * value, p)
        let u = mod(ySquared - 1, p)
        let v = mod(d * ySquared + 1, p)
        guard !v.isZero else { return false }

        let squared = mod(u * modularInverse(v, p), p)
        let criterion = squared.power((p - 1) / 2, modulus: p)
        guard criterion.isZero || criterion == 1 else { return false }

        // The one remaining impossible encoding: x = 0 carrying a negative sign.
        if squared.isZero, hasSignBit { return false }
        return true
    }

    /// The least non-negative residue. See `isOnEd25519Curve` for why `%` alone
    /// is not it.
    private static func mod(_ value: BigInt, _ modulus: BigInt) -> BigInt {
        let remainder = value % modulus
        return remainder.sign == .minus ? remainder + modulus : remainder
    }

    /// `value⁻¹ mod modulus` for a prime modulus, by Fermat's little theorem.
    private static func modularInverse(_ value: BigInt, _ modulus: BigInt) -> BigInt {
        value.power(modulus - 2, modulus: modulus)
    }
}
