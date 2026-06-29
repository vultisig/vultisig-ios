//
//  QBTCClaimCoinResolverTests.swift
//  VultisigAppTests
//
//  Mirrors Android's `ResolveQbtcClaimCoinsUseCaseTest` (#4679): an
//  enabled native coin is used as-is, a missing one is derived in-memory
//  from the vault's keys, and only a genuine derivation failure (a
//  non-quantum vault lacking the MLDSA-44 key) throws.
//

@testable import VultisigApp
import XCTest

@MainActor
final class QBTCClaimCoinResolverTests: XCTestCase {

    /// Valid keys that derive a Bitcoin (ECDSA) address via WalletCore.
    private static let pubKeyECDSA = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    private static let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"
    /// A non-empty hex string standing in for the ML-DSA-44 public key —
    /// QBTC address derivation hashes the raw bytes, so any valid hex works.
    private static let publicKeyMLDSA44 = String(repeating: "ab", count: 1312)

    private let resolver = QBTCClaimCoinResolver()

    private func coin(chain: Chain, address: String, hexPublicKey: String = "00") -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: chain.ticker,
            logo: chain.logo,
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: address, hexPublicKey: hexPublicKey)
    }

    /// Already-enabled accounts are returned as-is, without deriving.
    func testReturnsEnabledCoinsAsIs() throws {
        let vault = Vault(name: "v")
        vault.coins = [
            coin(chain: .bitcoin, address: "btcAddr"),
            coin(chain: .qbtc, address: "qbtcAddr")
        ]

        let result = try resolver.resolve(vault: vault)

        XCTAssertEqual(result.btc.address, "btcAddr")
        XCTAssertEqual(result.qbtc.address, "qbtcAddr")
    }

    /// Both accounts are derived in-memory from the native templates and
    /// the vault's own keys when the chains aren't enabled.
    func testDerivesMissingAccounts() throws {
        let vault = Vault(name: "v")
        vault.pubKeyECDSA = Self.pubKeyECDSA
        vault.hexChainCode = Self.hexChainCode
        vault.publicKeyMLDSA44 = Self.publicKeyMLDSA44

        let result = try resolver.resolve(vault: vault)

        XCTAssertEqual(result.btc.chain, .bitcoin)
        XCTAssertTrue(result.btc.isNativeToken)
        XCTAssertFalse(result.btc.address.isEmpty)
        XCTAssertFalse(result.btc.hexPublicKey.isEmpty)

        XCTAssertEqual(result.qbtc.chain, .qbtc)
        XCTAssertTrue(result.qbtc.isNativeToken)
        XCTAssertTrue(result.qbtc.address.hasPrefix("qbtc"))
        XCTAssertFalse(result.qbtc.hexPublicKey.isEmpty)
    }

    /// `resolve(vault:chain:)` derives a single chain (the path
    /// `KeysignDiscoveryViewModel` uses for the QBTC claimer address).
    func testDerivesSingleChain() throws {
        let vault = Vault(name: "v")
        vault.pubKeyECDSA = Self.pubKeyECDSA
        vault.hexChainCode = Self.hexChainCode
        vault.publicKeyMLDSA44 = Self.publicKeyMLDSA44

        let qbtc = try resolver.resolve(vault: vault, chain: .qbtc)

        XCTAssertEqual(qbtc.chain, .qbtc)
        XCTAssertTrue(qbtc.address.hasPrefix("qbtc"))
    }

    /// A non-quantum vault (no MLDSA-44 key) can't derive the QBTC
    /// account — the only genuine failure — and throws `derivationFailed`.
    func testThrowsWhenMLDSAKeyMissing() {
        let vault = Vault(name: "v")
        vault.pubKeyECDSA = Self.pubKeyECDSA
        vault.hexChainCode = Self.hexChainCode
        vault.publicKeyMLDSA44 = nil

        XCTAssertThrowsError(try resolver.resolve(vault: vault)) { error in
            XCTAssertEqual(
                error as? QBTCClaimCoinResolver.Error,
                .derivationFailed(chainName: Chain.qbtc.name)
            )
        }
    }
}
