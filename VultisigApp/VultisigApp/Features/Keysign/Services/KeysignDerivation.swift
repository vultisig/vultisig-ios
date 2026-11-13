//
//  KeysignDerivation.swift
//  VultisigApp
//
//  One place for every keysign derivation-path decision. With no override
//  each call site gets exactly the expression it computed before (pinned by
//  tests), so existing flows are byte-for-byte unchanged. With an override
//  (`CustomMessagePayload.derivePath`, e.g. the perps trading account) the
//  resolver is fail-closed: it never falls back to the default path, because
//  a signature at the wrong path is a valid signature from a different
//  address. Override signatures are checked by public-key recovery after the
//  ceremony.
//

import Foundation
import Tss
import WalletCore

/// A non-default path the keysign will sign under.
struct KeysignDerivation: Equatable {
    /// Apostrophe form; FastVault `derive_path` and GG20 `derivePath`.
    let derivePath: String
    /// What goes into `DKLSKeysign(chainPath:)`.
    let dklsChainPath: String
    /// Compressed child public key the signatures must recover to.
    let expectedPublicKeyHex: String
}

enum KeysignDerivationError: LocalizedError, Equatable {
    case unsupportedVaultType
    case unsupportedKeyType
    case unsupportedChain
    case pathNotAllowed(String)
    case derivationFailed
    case signerMismatch
    case ceremonyNotSupported

    var errorDescription: String? {
        switch self {
        case .unsupportedVaultType: return "keysignDerivationUnsupportedVault".localized
        case .unsupportedKeyType, .unsupportedChain, .pathNotAllowed, .derivationFailed, .ceremonyNotSupported:
            return "keysignDerivationRefused".localized
        case .signerMismatch: return "keysignDerivationSignerMismatch".localized
        }
    }
}

enum KeysignDerivationResolver {
    /// Perps trading account #0. Reserved range /1000-/1999; only #0 is allowed in v1.
    static let tradingAccountPath = "m/44'/60'/0'/0/1000"
    static let allowedOverrides: Set<String> = [tradingAccountPath]

    // MARK: Override

    /// nil when the payload asks for no override. Throws, never falls back,
    /// when an override is requested but not allowed for this vault or message.
    static func override(
        libType: LibType?,
        rootPublicKeyECDSA: String,
        hexChainCode: String,
        keysignType: KeyType,
        hasKeysignPayload: Bool,
        customMessagePayload: CustomMessagePayload?
    ) throws -> KeysignDerivation? {
        guard let path = customMessagePayload?.derivePath, let customMessagePayload else { return nil }
        guard libType == .DKLS else { throw KeysignDerivationError.unsupportedVaultType }
        guard keysignType == .ECDSA else { throw KeysignDerivationError.unsupportedKeyType }
        guard !hasKeysignPayload,
              (try? customMessagePayload.resolveSigningChain())?.chainType == .EVM else {
            throw KeysignDerivationError.unsupportedChain
        }
        guard isWellFormed(path), allowedOverrides.contains(path) else { throw KeysignDerivationError.pathNotAllowed(path) }
        let child = PublicKeyHelper.getDerivedPubKey(hexPubKey: rootPublicKeyECDSA, hexChainCode: hexChainCode, derivePath: path)
        // The helper returns "" on failure; that is never success.
        guard !child.isEmpty else { throw KeysignDerivationError.derivationFailed }
        return KeysignDerivation(derivePath: path, dklsChainPath: path, expectedPublicKeyHex: child.lowercased())
    }

    @MainActor
    static func override(vault: Vault, keysignType: KeyType, keysignPayload: KeysignPayload?,
                         customMessagePayload: CustomMessagePayload?) throws -> KeysignDerivation? {
        try override(libType: vault.libType, rootPublicKeyECDSA: vault.pubKeyECDSA, hexChainCode: vault.hexChainCode,
                     keysignType: keysignType, hasKeysignPayload: keysignPayload != nil, customMessagePayload: customMessagePayload)
    }

    /// Off until `derive_path` travels in the keysign message. Today a joiner
    /// never learns the override, so it cannot check the path itself or run
    /// the recovery guard, and DKLS publishes signatures before the
    /// initiator's guard runs. Until then every ceremony that asks for an
    /// override is refused before any relay or VultiServer traffic.
    static let isCeremonyOverrideEnabled = false

    /// What the keysign call sites use: `override`, plus the ceremony gate.
    @MainActor
    static func ceremonyOverride(vault: Vault, keysignType: KeyType, keysignPayload: KeysignPayload?,
                                 customMessagePayload: CustomMessagePayload?) throws -> KeysignDerivation? {
        let derivation = try override(vault: vault, keysignType: keysignType, keysignPayload: keysignPayload,
                                      customMessagePayload: customMessagePayload)
        try gateCeremony(derivation)
        return derivation
    }

    static func gateCeremony(_ derivation: KeysignDerivation?, enabled: Bool = isCeremonyOverrideEnabled) throws {
        if derivation != nil, !enabled { throw KeysignDerivationError.ceremonyNotSupported }
    }

    /// `^m(/[0-9]{1,10}'?){1,6}$`, every index below 2^31.
    static func isWellFormed(_ path: String) -> Bool {
        guard path.range(of: #"^m(/[0-9]{1,10}'?){1,6}$"#, options: .regularExpression) != nil else { return false }
        return path.split(separator: "/").dropFirst().allSatisfy { component in
            UInt64(component.replacingOccurrences(of: "'", with: "")).map { $0 < 0x8000_0000 } ?? false
        }
    }

    // MARK: Call sites (default branches are the pre-existing expressions)

    /// `KeysignViewModel.startKeysignDKLS`.
    static func dklsChainPath(keysignPayload: KeysignPayload?, customMessagePayload: CustomMessagePayload?,
                              isImport: Bool, override: KeysignDerivation?) throws -> String {
        if let override { return override.dklsChainPath }
        var chainPath: String
        if let keysignPayload {
            chainPath = keysignPayload.coin.coinType.derivationPath()
        } else if let customMessagePayload {
            chainPath = try customMessagePayload.resolveSigningChain().coinType.derivationPath()
        } else {
            throw HelperError.runtimeError("keysign payload is nil")
        }
        if isImport { chainPath = "" }
        return chainPath
    }

    /// `KeysignViewModel.startKeysignGG20`. Unreachable with an override
    /// (GG20 is refused), kept for one source of truth.
    static func gg20DerivePath(keysignPayload: KeysignPayload?, override: KeysignDerivation?) -> String {
        if let override { return override.derivePath }
        if let keysignPayload { return keysignPayload.coin.coinType.derivationPath() }
        return TokensStore.Token.ethereum.coinType.derivationPath()
    }

    /// `FastVaultKeysignBootstrap` and `KeysignDiscoveryViewModel` (VultiServer
    /// signs from the setup message; this value feeds its post-sign verify log).
    static func fastVaultDerivePath(coin: Coin, override: KeysignDerivation?) -> String {
        override?.derivePath ?? coin.coinType.derivationPath()
    }

    // MARK: Post-sign check

    /// Every signature must recover to the override's child key; a mismatch
    /// fails the keysign. Runs wherever the override is known, which today is
    /// the initiator only (see `isCeremonyOverrideEnabled`).
    static func verify(signatures: [String: TssKeysignResponse], expectedPublicKeyHex: String) throws {
        for (message, response) in signatures {
            guard case .success(let rsv) = response.getSignatureWithRecoveryID(),
                  let digest = Data(hexString: message),
                  let recovered = PublicKey.recover(signature: rsv, message: digest),
                  recovered.compressed.data.hexString == expectedPublicKeyHex.lowercased() else {
                throw KeysignDerivationError.signerMismatch
            }
        }
    }
}
