//
//  DefiBondInteractorSnapshotTests.swift
//  VultisigAppTests
//
//  `fetchBondPositions(vault:)` is `nonisolated async`, so it may not read
//  `Vault`/`Coin` — both SwiftData `@Model` classes — directly. Each Bond
//  interactor hoists that read into a `@MainActor` `bondCoinSnapshot(in:)`
//  prologue returning a `Sendable` value type.
//
//  What these tests can and cannot prove is worth stating, because it is easy
//  to write one here that passes either way:
//    - Covered here: WHICH coin each interactor selects, and every field the
//      snapshot carries.
//    - NOT covered here, and covered by the compiler instead: that the read
//      happens on the main actor. `@MainActor` on the prologue plus the
//      required `await` at the call site is what enforces that; a test running
//      on the main actor cannot tell the two apart.
//
//  Two details drive how the assertions below are written:
//    - `CoinMeta`'s `==` is custom and compares only chain, lowercased ticker
//      and lowercased contract address — NOT decimals, logo, priceProviderId or
//      isNativeToken. Comparing whole `CoinMeta` values would therefore assert
//      much less than it appears to, so each field is asserted individually.
//    - The `nil` cases carry the weight of pinning each selector's predicate,
//      because they are order-independent. A positive test over a vault holding
//      several candidates depends on `coins.first`, and SwiftData makes no
//      promise about relationship ordering; a vault holding only a decoy must
//      yield `nil` no matter what order anything is in.
//

@testable import VultisigApp
import XCTest

@MainActor
final class DefiBondInteractorSnapshotTests: XCTestCase {

    // MARK: - THORChain

    func testThorchainBondSnapshotSelectsRuneCoin() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "thor-bond-selects-rune")
        // Decoys first, so `coins.first` would surface one of them if the
        // selector lost either half of its predicate.
        vault.coins.append(makeCoin(chain: .thorChain, ticker: "TOR", address: "thor1native"))
        vault.coins.append(
            makeCoin(chain: .thorChain, ticker: "RUNE", address: "thor1wrapped", isNativeToken: false)
        )
        vault.coins.append(makeCoin(chain: .mayaChain, ticker: "CACAO", address: "maya1cacao"))
        vault.coins.append(
            makeCoin(chain: .thorChain, ticker: "RUNE", address: "thor1rune", decimals: 8)
        )

        let snapshot = try XCTUnwrap(THORChainBondInteractor().bondCoinSnapshot(in: vault))

        XCTAssertEqual(snapshot.address, "thor1rune")
        XCTAssertEqual(snapshot.meta.ticker, "RUNE")
        XCTAssertEqual(snapshot.meta.chain, .thorChain)
        XCTAssertTrue(snapshot.meta.isNativeToken)
        XCTAssertEqual(snapshot.meta.decimals, 8)
        XCTAssertEqual(snapshot.meta.contractAddress, "RUNE-contract")
        XCTAssertEqual(snapshot.meta.priceProviderId, "rune")
        XCTAssertEqual(snapshot.meta.logo, "logo")
    }

    func testThorchainBondSnapshotIsNilWithoutRuneCoin() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        // Holds another chain's native coin, so a selector that dropped the
        // chain check would wrongly succeed here.
        let vault = TestStore.makeVault(pubKey: "thor-bond-no-rune")
        vault.coins.append(makeCoin(chain: .mayaChain, ticker: "CACAO", address: "maya1cacao"))

        XCTAssertNil(THORChainBondInteractor().bondCoinSnapshot(in: vault))
    }

    /// Pins the RUNE-ticker half of the predicate: a selector relaxed to
    /// "THORChain's native coin" would pick this up.
    func testThorchainBondSnapshotIgnoresNativeNonRuneCoin() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "thor-bond-native-non-rune")
        vault.coins.append(makeCoin(chain: .thorChain, ticker: "TOR", address: "thor1native"))

        XCTAssertNil(THORChainBondInteractor().bondCoinSnapshot(in: vault))
    }

    /// Pins the native half of the predicate: a selector relaxed to "a coin
    /// tickered RUNE on THORChain" would pick this up.
    func testThorchainBondSnapshotIgnoresNonNativeRuneToken() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "thor-bond-non-native-rune")
        vault.coins.append(
            makeCoin(chain: .thorChain, ticker: "RUNE", address: "thor1wrapped", isNativeToken: false)
        )

        XCTAssertNil(THORChainBondInteractor().bondCoinSnapshot(in: vault))
    }

    /// The early return the snapshot's `nil` drives. This asserts the returned
    /// value only — it does not prove that no request was issued, which would
    /// need an injectable API service the interactor does not currently expose.
    func testThorchainFetchBondPositionsReturnsEmptyWithoutRuneCoin() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "thor-bond-fetch-guard")

        let result = try await THORChainBondInteractor().fetchBondPositions(vault: vault)

        XCTAssertTrue(result.active.isEmpty)
        XCTAssertTrue(result.available.isEmpty)
    }

    // MARK: - MayaChain

    func testMayachainBondSnapshotSelectsNativeCacaoCoin() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "maya-bond-selects-cacao")
        vault.coins.append(
            makeCoin(chain: .mayaChain, ticker: "MAYA", address: "maya1maya", isNativeToken: false)
        )
        vault.coins.append(makeCoin(chain: .thorChain, ticker: "RUNE", address: "thor1rune"))
        vault.coins.append(
            makeCoin(chain: .mayaChain, ticker: "CACAO", address: "maya1cacao", decimals: 10)
        )

        let snapshot = try XCTUnwrap(MayaChainBondInteractor().bondCoinSnapshot(in: vault))

        XCTAssertEqual(snapshot.address, "maya1cacao")
        XCTAssertEqual(snapshot.meta.ticker, "CACAO")
        XCTAssertEqual(snapshot.meta.chain, .mayaChain)
        XCTAssertTrue(snapshot.meta.isNativeToken)
        XCTAssertEqual(snapshot.meta.decimals, 10)
        XCTAssertEqual(snapshot.meta.contractAddress, "CACAO-contract")
        XCTAssertEqual(snapshot.meta.priceProviderId, "cacao")
        XCTAssertEqual(snapshot.meta.logo, "logo")
    }

    /// One vault pinning both halves of Maya's predicate: relaxing the chain
    /// check selects the RUNE coin, relaxing the native check selects the MAYA
    /// token, and either way the result stops being `nil`.
    func testMayachainBondSnapshotIsNilWithoutMayaNativeCoin() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "maya-bond-no-cacao")
        vault.coins.append(makeCoin(chain: .thorChain, ticker: "RUNE", address: "thor1rune"))
        vault.coins.append(
            makeCoin(chain: .mayaChain, ticker: "MAYA", address: "maya1maya", isNativeToken: false)
        )

        XCTAssertNil(MayaChainBondInteractor().bondCoinSnapshot(in: vault))
    }

    /// As above: returned value only, not an assertion about requests issued.
    func testMayachainFetchBondPositionsReturnsEmptyWithoutCacaoCoin() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let vault = TestStore.makeVault(pubKey: "maya-bond-fetch-guard")

        let result = try await MayaChainBondInteractor().fetchBondPositions(vault: vault)

        XCTAssertTrue(result.active.isEmpty)
        XCTAssertTrue(result.available.isEmpty)
    }

    // MARK: - Helpers

    private func makeCoin(
        chain: Chain,
        ticker: String,
        address: String,
        decimals: Int = 8,
        isNativeToken: Bool = true
    ) -> Coin {
        Coin(
            asset: CoinMeta.make(
                chain: chain,
                ticker: ticker,
                decimals: decimals,
                isNativeToken: isNativeToken
            ),
            address: address,
            hexPublicKey: "pub-\(ticker.lowercased())"
        )
    }
}
