//
//  ThorchainCustomTokenResolverTests.swift
//  VultisigAppTests
//
//  Covers the pure THORChain custom-token logic: normalizing the user-typed
//  `THOR.{SYMBOL}` pool/display notation onto the lowercase bank denom
//  (`thor.{symbol}`), validating the accepted shapes (and rejecting garbage),
//  and pinning the curated LQDY entry in TokensStore.
//
//  THORChain non-RUNE tokens are Cosmos bank denoms, not pool assets, so the
//  custom-token search must accept the `THOR.X` notation rather than a
//  `thor1…` bech32 address. The network-backed `resolve(...)` path is not
//  unit-tested here (it needs a live LCD); the normalization + validation it
//  depends on are.
//

import XCTest
@testable import VultisigApp

final class ThorchainCustomTokenResolverTests: XCTestCase {

    // MARK: - Normalization

    func test_normalizeDenom_acceptsUppercasePoolNotation() {
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "THOR.LQDY"), "thor.lqdy")
    }

    func test_normalizeDenom_acceptsLowercaseDenom() {
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "thor.lqdy"), "thor.lqdy")
    }

    func test_normalizeDenom_acceptsMixedCase() {
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "Thor.Lqdy"), "thor.lqdy")
    }

    func test_normalizeDenom_acceptsBareSymbol() {
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "LQDY"), "thor.lqdy")
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "kuji"), "thor.kuji")
    }

    func test_normalizeDenom_trimsWhitespace() {
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "  THOR.LQDY  "), "thor.lqdy")
    }

    func test_normalizeDenom_generalizesToOtherSymbols() {
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "THOR.KUJI"), "thor.kuji")
        XCTAssertEqual(ThorchainCustomTokenResolver.normalizeDenom(from: "THOR.FUZN"), "thor.fuzn")
    }

    // MARK: - Rejected input

    func test_normalizeDenom_rejectsEmpty() {
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: ""))
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "   "))
    }

    func test_normalizeDenom_rejectsWrongPrefix() {
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "MAYA.CACAO"))
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "ETH.USDC"))
    }

    func test_normalizeDenom_rejectsEmptySymbolAfterPrefix() {
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "THOR."))
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "thor."))
    }

    func test_normalizeDenom_rejectsBech32Address() {
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"))
    }

    func test_normalizeDenom_rejectsMalformedSymbols() {
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "THOR.LQ DY"))
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "THOR.LQ.DY"))
        XCTAssertNil(ThorchainCustomTokenResolver.normalizeDenom(from: "THOR.LQDY!"))
    }

    // MARK: - Symbol extraction

    func test_symbol_extractsUppercased() {
        XCTAssertEqual(ThorchainCustomTokenResolver.symbol(from: "THOR.LQDY"), "LQDY")
        XCTAssertEqual(ThorchainCustomTokenResolver.symbol(from: "thor.lqdy"), "LQDY")
        XCTAssertEqual(ThorchainCustomTokenResolver.symbol(from: "lqdy"), "LQDY")
    }

    func test_symbol_nilForInvalid() {
        XCTAssertNil(ThorchainCustomTokenResolver.symbol(from: "MAYA.CACAO"))
        XCTAssertNil(ThorchainCustomTokenResolver.symbol(from: ""))
    }

    // MARK: - Validation gate (mirrors CustomTokenScreen.validateAddress)

    func test_isValidInput_acceptsThorNotation() {
        XCTAssertTrue(ThorchainCustomTokenResolver.isValidInput("THOR.LQDY"))
        XCTAssertTrue(ThorchainCustomTokenResolver.isValidInput("thor.lqdy"))
        XCTAssertTrue(ThorchainCustomTokenResolver.isValidInput("LQDY"))
    }

    func test_isValidInput_rejectsGarbageAndAddresses() {
        XCTAssertFalse(ThorchainCustomTokenResolver.isValidInput(""))
        XCTAssertFalse(ThorchainCustomTokenResolver.isValidInput("THOR."))
        XCTAssertFalse(ThorchainCustomTokenResolver.isValidInput("0x1234"))
        XCTAssertFalse(ThorchainCustomTokenResolver.isValidInput("thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"))
    }

    // MARK: - Curated LQDY entry (part a)

    func test_tokensStore_containsCuratedLQDY() {
        let lqdy = TokensStore.findTokenMeta(chain: .thorChain, contractAddress: "thor.lqdy")
        XCTAssertNotNil(lqdy)
        XCTAssertEqual(lqdy?.ticker, "LQDY")
        XCTAssertEqual(lqdy?.decimals, 8)
        XCTAssertEqual(lqdy?.logo, "lqdy")
        XCTAssertEqual(lqdy?.isNativeToken, false)
    }

    func test_curatedLQDY_isOfferedInTokenSelection() {
        let offered = TokensStore.TokenSelectionAssets.contains {
            $0.chain == .thorChain && $0.contractAddress == "thor.lqdy"
        }
        XCTAssertTrue(offered, "LQDY should be offered in Manage Tokens for pre-hold discoverability")
    }
}
