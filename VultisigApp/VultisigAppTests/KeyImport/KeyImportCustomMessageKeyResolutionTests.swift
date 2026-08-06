//
//  KeyImportCustomMessageKeyResolutionTests.swift
//  VultisigAppTests
//
//  Covers how a custom message picks its signing key on the key-import path
//  (`KeysignViewModel.customMessagePublicKey(for:in:isImport:)`).
//
//  A key-import vault holds one pre-derived share per imported chain and signs
//  with an empty chain path, so the share handed to the ceremony is the signing
//  key outright. The app stamps every custom message it initiates with
//  chain "Ethereum", but key import never forces Ethereum into the chain set —
//  so the resolution has to fall back to a share on the same derivation path
//  before it falls back to the vault's root share.
//

import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class KeyImportCustomMessageKeyResolutionTests: XCTestCase {

    private let bscKey = "bsc-chain-public-key"
    private let ethKey = "eth-chain-public-key"
    private let rootEcdsaKey = "root-ecdsa-public-key"

    // MARK: - The reported bug

    func testBscOnlyImportVaultResolvesBscKeyForEthereumCustomMessage() {
        let vault = makeKeyImportVault(keys: [(.bscChain, bscKey)])

        // Mirrors the production expression: the resolved key, or the root share.
        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: true
        ) ?? vault.pubKeyECDSA

        XCTAssertEqual(resolved, bscKey, "A BSC-only import vault must sign an Ethereum-named custom message with its BSC share")
        XCTAssertNotEqual(resolved, vault.pubKeyECDSA, "The root share at path m must not be used when the vault holds an EVM share")
    }

    func testEveryEvmSiblingResolvesForAnEthereumCustomMessage() {
        for chain in [Chain.bscChain, .base, .arbitrum, .polygon, .optimism, .avalanche, .sei] {
            let vault = makeKeyImportVault(keys: [(chain, "key-\(chain.name)")])

            let resolved = KeysignViewModel.customMessagePublicKey(
                for: .ethereum,
                in: vault.chainPublicKeys,
                isImport: true
            )

            XCTAssertEqual(resolved, "key-\(chain.name)", "\(chain.name) shares Ethereum's derivation path and must resolve")
        }
    }

    /// Guards the premise the fallback rests on: every EVM chain the app offers
    /// derives from Ethereum's path, so a sibling share is the very same key.
    func testEvmSiblingsShareEthereumsDerivationPath() {
        let ethereumPath = Chain.ethereum.coinType.derivationPath()
        XCTAssertEqual(ethereumPath, "m/44'/60'/0'/0/0")

        for chain in Chain.allCases where chain.chainType == .EVM {
            XCTAssertEqual(chain.coinType.derivationPath(), ethereumPath, "\(chain.name) is EVM but does not derive from Ethereum's path")
        }
    }

    // MARK: - Unchanged behaviour

    func testExactChainMatchWinsOverADerivationPathSibling() {
        let vault = makeKeyImportVault(keys: [(.bscChain, bscKey), (.ethereum, ethKey)])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertEqual(resolved, ethKey, "An exact chain entry must take precedence over a path sibling")
    }

    func testNoKeyOnThatDerivationPathFallsBackToTheRootKey() {
        // THORChain derives from m/44'/931'/0'/0/0 — nothing on Ethereum's path.
        let vault = makeKeyImportVault(keys: [(.thorChain, "thor-chain-public-key")])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertNil(resolved, "No share on Ethereum's path must leave the caller's root fallback in charge")
        XCTAssertEqual(resolved ?? vault.pubKeyECDSA, rootEcdsaKey)
    }

    func testEmptyChainPublicKeysFallsBackToTheRootKey() {
        // Legacy JSON backups predate `chainPublicKeys` persistence.
        let vault = makeKeyImportVault(keys: [])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertNil(resolved)
    }

    /// The **exact** match deliberately does not filter on the persisted curve flag, unlike
    /// Android's resolvers. `chain` is the entry's primary identity — it forms the
    /// `@Attribute(.unique)` id and is written from the same import job as the key itself —
    /// so a share filed under a chain *is* that chain's key, whatever the flag says. Were
    /// the flag ever inconsistent, filtering would drop through to the root share at path
    /// `m`: a signature that verifies against nothing, which is the precise failure this
    /// fix exists to remove. Trusting `chain` over the flag keeps the safer failure mode.
    ///
    /// Neither platform's write path can actually produce this state for a chain that
    /// reaches this helper: QBTC is the only chain whose `isEddsa` the two platforms
    /// disagree on, and the `.MLDSA` branch signs with `vault.publicKeyMLDSA44` instead of
    /// this helper's result. The test pins the intent so the check is not "fixed" later.
    func testExactMatchWithInconsistentCurveMetadataStillWins() {
        let vault = makeKeyImportVault(keys: [(.ethereum, ethKey)], isEddsaOverride: true)

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertEqual(resolved, ethKey, "The chain's own share must win over an inconsistent curve flag, never the root key")
        XCTAssertNotEqual(resolved, vault.pubKeyECDSA)
    }

    // MARK: - The fallback must not cross curves

    func testEcdsaTargetDoesNotPickUpAnEddsaShare() {
        let vault = makeKeyImportVault(keys: [(.solana, "solana-chain-public-key")])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertNil(resolved, "An ECDSA target must never resolve to an EdDSA share")
    }

    func testEddsaTargetDoesNotPickUpAnEcdsaShare() {
        let vault = makeKeyImportVault(keys: [(.ethereum, ethKey)])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .solana,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertNil(resolved, "An EdDSA target must never resolve to an ECDSA share")
    }

    func testEddsaTargetStillResolvesItsExactShare() {
        let solanaKey = "solana-chain-public-key"
        let vault = makeKeyImportVault(keys: [(.solana, solanaKey)])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .solana,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertEqual(resolved, solanaKey)
    }

    /// QBTC signs with MLDSA and shares Cosmos' derivation path, and the two platforms
    /// persist its `isEddsa` differently — iOS writes `true` (`!chain.isECDSA`), Android
    /// writes `false` (`TssKeysignType == EDDSA`). A vault restored from an Android backup
    /// therefore carries a QBTC share that the persisted flag alone would hand to a
    /// Cosmos-named message.
    func testAndroidWrittenQbtcShareIsNotUsedForACosmosCustomMessage() {
        let vault = makeKeyImportVault(keys: [(.qbtc, "qbtc-chain-public-key")], isEddsaOverride: false)

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .gaiaChain,
            in: vault.chainPublicKeys,
            isImport: true
        )

        XCTAssertNil(resolved, "An MLDSA share must never be handed to an ECDSA Cosmos message")
    }

    // MARK: - Non-import vaults are untouched

    func testNonImportVaultGetsNoDerivationPathFallback() {
        let vault = makeKeyImportVault(keys: [(.bscChain, bscKey)])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: false
        )

        XCTAssertNil(resolved, "Only key-import vaults sign with a pre-derived per-chain share")
    }

    func testNonImportVaultKeepsItsExactMatch() {
        let vault = makeKeyImportVault(keys: [(.ethereum, ethKey)])

        let resolved = KeysignViewModel.customMessagePublicKey(
            for: .ethereum,
            in: vault.chainPublicKeys,
            isImport: false
        )

        XCTAssertEqual(resolved, ethKey, "The pre-existing exact match must behave exactly as before")
    }

    // MARK: - Helpers

    /// - Parameter isEddsaOverride: forces the persisted flag, to model a vault written by
    ///   another platform. Defaults to the predicate iOS's own import uses.
    private func makeKeyImportVault(keys: [(chain: Chain, publicKeyHex: String)],
                                    isEddsaOverride: Bool? = nil) -> Vault {
        let vault = Vault(name: "KeyImport", libType: .KeyImport)
        vault.pubKeyECDSA = rootEcdsaKey
        vault.pubKeyEdDSA = "root-eddsa-public-key"
        vault.hexChainCode = "00"
        // `isEddsa` is written at import with the same predicate the resolver
        // matches on (`KeygenViewModel.buildChainImportJobs`).
        vault.chainPublicKeys = keys.map { entry in
            ChainPublicKey(
                chain: entry.chain,
                publicKeyHex: entry.publicKeyHex,
                isEddsa: isEddsaOverride ?? !entry.chain.isECDSA
            )
        }
        return vault
    }
}
