//
//  SwapProviderKindTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class SwapProviderKindTests: XCTestCase {

    // MARK: - providerLogo

    func testProviderLogoPerCase() {
        XCTAssertEqual(SwapProviderKind.thorchain.providerLogo, "THORChain")
        XCTAssertEqual(SwapProviderKind.maya.providerLogo, "Maya protocol")
        XCTAssertEqual(SwapProviderKind.oneInch.providerLogo, "1Inch")
        XCTAssertEqual(SwapProviderKind.kyberSwap.providerLogo, "kyberswap")
        XCTAssertEqual(SwapProviderKind.lifi.providerLogo, "LI.FI")
        XCTAssertEqual(SwapProviderKind.swapkit.providerLogo, "swapkit")
        XCTAssertEqual(SwapProviderKind.jupiter.providerLogo, "jupiter")
    }

    // MARK: - displayName

    func testDisplayNamePerCase() {
        XCTAssertEqual(SwapProviderKind.thorchain.displayName, "THORChain")
        XCTAssertEqual(SwapProviderKind.maya.displayName, "Maya protocol")
        XCTAssertEqual(SwapProviderKind.oneInch.displayName, "1Inch")
        XCTAssertEqual(SwapProviderKind.kyberSwap.displayName, "KyberSwap")
        XCTAssertEqual(SwapProviderKind.lifi.displayName, "LI.FI")
        XCTAssertEqual(SwapProviderKind.swapkit.displayName, "SwapKit")
        XCTAssertEqual(SwapProviderKind.jupiter.displayName, "Jupiter")
    }

    // MARK: - init(persistedName:)

    func testInitResolvesThorchainFamily() {
        for name in ["THORChain", "THORChain-Chainnet", "THORChain-Stagenet", "thorchain"] {
            XCTAssertEqual(SwapProviderKind(persistedName: name), .thorchain, "for \(name)")
        }
    }

    func testInitResolvesMayaBothCasings() {
        for name in ["Maya protocol", "Maya Protocol"] {
            XCTAssertEqual(SwapProviderKind(persistedName: name), .maya, "for \(name)")
        }
    }

    func testInitResolvesOneInch() {
        XCTAssertEqual(SwapProviderKind(persistedName: "1Inch"), .oneInch)
    }

    func testInitResolvesKyberSwap() {
        XCTAssertEqual(SwapProviderKind(persistedName: "KyberSwap"), .kyberSwap)
    }

    func testInitResolvesLifi() {
        XCTAssertEqual(SwapProviderKind(persistedName: "LI.FI"), .lifi)
    }

    func testInitResolvesSwapKitAndSubProviders() {
        for name in ["SwapKit", "SwapKit (Chainflip)", "SwapKit (NEAR Intents)"] {
            XCTAssertEqual(SwapProviderKind(persistedName: name), .swapkit, "for \(name)")
        }
    }

    /// A SwapKit sub-provider naming its underlying protocol still resolves to
    /// the outer SwapKit brand, not the inner protocol.
    func testInitPrefersOuterSwapKitBrandOverInnerProtocol() {
        XCTAssertEqual(SwapProviderKind(persistedName: "SwapKit (THORChain)"), .swapkit)
    }

    func testInitResolvesJupiter() {
        XCTAssertEqual(SwapProviderKind(persistedName: "Jupiter"), .jupiter)
    }

    func testInitIsCaseInsensitive() {
        XCTAssertEqual(SwapProviderKind(persistedName: "JUPITER"), .jupiter)
        XCTAssertEqual(SwapProviderKind(persistedName: "kyberswap"), .kyberSwap)
    }

    func testInitTrimsWhitespace() {
        XCTAssertEqual(SwapProviderKind(persistedName: "  SwapKit  "), .swapkit)
    }

    func testInitRejectsEmptyOrWhitespace() {
        XCTAssertNil(SwapProviderKind(persistedName: ""))
        XCTAssertNil(SwapProviderKind(persistedName: "   "))
    }

    func testInitRejectsUnknownProvider() {
        XCTAssertNil(SwapProviderKind(persistedName: "SomeUnknownProvider"))
    }

    /// `li.fi` must match with the dot, not the bare `lifi` substring, which
    /// appears inside unrelated words such as "amplifier".
    func testInitDoesNotFalseMatchLifiSubstring() {
        XCTAssertNil(SwapProviderKind(persistedName: "amplifier"))
    }

    /// `thorchain` (full token), not the bare `thor` substring, which appears
    /// inside unrelated words such as "author".
    func testInitDoesNotFalseMatchThorSubstring() {
        XCTAssertNil(SwapProviderKind(persistedName: "Author"))
    }
}
