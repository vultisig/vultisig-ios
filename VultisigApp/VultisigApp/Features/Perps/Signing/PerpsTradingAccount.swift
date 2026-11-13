//
//  PerpsTradingAccount.swift
//  VultisigApp
//
//  A vault's separate Hyperliquid trading account: a second EVM
//  address derived non-hardened from the vault's MPC root ECDSA key and chain
//  code at a reserved path, so it is the MASTER of its own Hyperliquid
//  account (no subaccount, no volume gate) and still MPC-signed. Loss through
//  a leaked agent key is capped at that account's balance.
//
//  Plus the guard every Hyperliquid signature must pass before a post: recover
//  the signer and refuse unless it is the address we meant to sign as. A path
//  fallback anywhere in keysign would otherwise produce a valid signature from
//  the MAIN address, and Hyperliquid would apply it to the main account.
//
//  Nothing here signs. The keysign path override lives in `KeysignDerivationResolver`.
//

import Foundation
import WalletCore

enum PerpsSignerAccount: String, Sendable {
    case main
    case trading

    /// Every Vultisig client strips the apostrophes and derives non-hardened.
    /// The trading path is permanent once funded: never change it.
    var derivationPath: String {
        switch self {
        case .main: return "m/44'/60'/0'/0/0"
        case .trading: return KeysignDerivationResolver.tradingAccountPath
        }
    }
}

/// A Hyperliquid signature that recovered to the expected signer. Only
/// `PerpsSignerGuard.verify` can make one, so a postable request cannot be
/// built from an unchecked signature.
struct VerifiedHLSignature: Equatable, Sendable {
    let signature: HLSignature
    let signer: String

    fileprivate init(signature: HLSignature, signer: String) {
        self.signature = signature
        self.signer = signer
    }
}

struct PerpsDerivedAccount: Equatable, Sendable {
    let account: PerpsSignerAccount
    let publicKey: String
    let address: String

    static func derive(_ account: PerpsSignerAccount, rootPubKeyECDSA: String, hexChainCode: String) -> PerpsDerivedAccount? {
        let derived = PublicKeyHelper.getDerivedPubKey(hexPubKey: rootPubKeyECDSA, hexChainCode: hexChainCode, derivePath: account.derivationPath)
        guard let data = Data(hexString: derived), let key = PublicKey(data: data, type: .secp256k1) else { return nil }
        return PerpsDerivedAccount(account: account, publicKey: derived, address: PerpsSignerGuard.address(of: key))
    }

    @MainActor
    static func derive(_ account: PerpsSignerAccount, vault: Vault) -> PerpsDerivedAccount? {
        derive(account, rootPubKeyECDSA: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode)
    }
}

enum PerpsSignerGuardError: Error, Equatable {
    case unrecoverable
    case signerMismatch(expected: String, recovered: String)
    case notSigned
}

enum PerpsSignerGuard {
    static func address(of key: PublicKey) -> String {
        AnyAddress(publicKey: key.uncompressed, coin: .ethereum).description.lowercased()
    }

    static func recover(digest: Data, signature: HLSignature) -> String? {
        guard let r = Data(hexString: padded(signature.r)), let s = Data(hexString: padded(signature.s)),
              signature.v == 27 || signature.v == 28 else { return nil }
        var raw = r
        raw.append(s)
        raw.append(UInt8(signature.v - 27))
        guard let key = PublicKey.recover(signature: raw, message: digest) else { return nil }
        return address(of: key)
    }

    /// Throws unless `signature` over `digest` was made by `expected`.
    @discardableResult
    static func verify(digest: Data, signature: HLSignature, expected: String) throws -> VerifiedHLSignature {
        guard let recovered = recover(digest: digest, signature: signature) else { throw PerpsSignerGuardError.unrecoverable }
        guard recovered == expected.lowercased() else {
            throw PerpsSignerGuardError.signerMismatch(expected: expected.lowercased(), recovered: recovered)
        }
        return VerifiedHLSignature(signature: signature, signer: recovered)
    }

    /// r/s as 32-byte hex, whatever padding they arrived with.
    private static func padded(_ hex: String) -> String {
        let digits = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return String(repeating: "0", count: max(0, 64 - digits.count)) + digits
    }
}

extension HLExchangeRequest {
    /// Attaches a signature only after it recovers to `expected`.
    func signed(_ signature: HLSignature, expected: String) throws -> HLExchangeRequest {
        var copy = self
        copy.signature = .signed(try PerpsSignerGuard.verify(digest: digest, signature: signature, expected: expected))
        return copy
    }

    /// The check a live client runs before posting. A dry-run body with a
    /// pending vault signature cannot pass it.
    func verifySigner(expected: String) throws {
        guard case .signed(let verified) = signature else { throw PerpsSignerGuardError.notSigned }
        try PerpsSignerGuard.verify(digest: digest, signature: verified.signature, expected: expected)
    }
}
