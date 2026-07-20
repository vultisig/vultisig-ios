//
//  AddressServiceTests.swift
//  VultisigAppTests
//
//  Covers `AddressService.detectChain`, the resolver behind the paste / QR /
//  address-book "did the user mean another chain?" auto-switch.
//

@testable import VultisigApp
import XCTest

@MainActor
final class AddressServiceTests: XCTestCase {

    // MARK: - Address fixtures

    /// Valid bech32 addresses. Terra and Terra Classic share the `terra` HRP, so
    /// this one address decodes cleanly on both networks — that ambiguity is the
    /// reason `detectChain` must refuse to pick one.
    private let terraAddress = "terra1xj49zyqrwpv5k928jwfpfy2ha668nwdgkwlrg3"
    private let mayaAddress = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"
    private let chainnetThorAddress = "cthor1prxy0sufdqfve6ygkwu9gswe60cle8gyr664qj"
    private let stagenetThorAddress = "sthor1prxy0sufdqfve6ygkwu9gswe60cle8gymn9sus"
    private let qbtcAddress = "qbtc10d07y265gmmuvt4z0w9aw880jnsr700j89jqe8"
    /// Generic Substrate SS58 address (prefix 42), which is what Bittensor uses.
    private let bittensorAddress = "5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY"
    private let evmAddress = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"

    // MARK: - Coin builders

    private func makeLUNA() -> Coin {
        SendFormFixture.makeCoin(.terra, ticker: "LUNA", decimals: 6, isNative: true)
    }

    private func makeLUNC() -> Coin {
        SendFormFixture.makeCoin(.terraClassic, ticker: "LUNC", decimals: 6, isNative: true)
    }

    // MARK: - Terra vs Terra Classic

    func testTerraAddressDoesNotAutoSwitchWhenVaultHoldsBothChains() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNA(), makeLUNC()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    func testTerraAddressDoesNotAutoSwitchWhenVaultHoldsOnlyTerraClassic() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNC()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    func testTerraAddressDoesNotAutoSwitchWhenVaultHoldsOnlyTerra() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNA()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    /// Precondition for everything above: the fixture really is ambiguous, and
    /// validates on both networks. Without this the `XCTAssertNil` assertions
    /// would also pass on an address that simply failed every validator.
    func testTerraFixtureValidatesOnBothTerraChains() {
        XCTAssertTrue(AddressService.validateAddress(address: terraAddress, chain: .terra))
        XCTAssertTrue(AddressService.validateAddress(address: terraAddress, chain: .terraClassic))
    }

    // MARK: - Bech32 special cases

    func testMayaAddressDetectsMayaChain() {
        let cacao = SendFormFixture.makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        let vault = SendFormFixture.makeVault(coins: [cacao])

        let detected = AddressService.detectChain(from: mayaAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertEqual(detected, .mayaChain)
    }

    func testMayaAddressReturnsNilWhenChainMissingFromVault() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])

        let detected = AddressService.detectChain(from: mayaAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    func testChainnetThorAddressDetectsThorChainChainnet() {
        let rune = SendFormFixture.makeCoin(.thorChainChainnet, ticker: "RUNE", decimals: 8, isNative: true)
        let vault = SendFormFixture.makeVault(coins: [rune])

        let detected = AddressService.detectChain(from: chainnetThorAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertEqual(detected, .thorChainChainnet)
    }

    func testStagenetThorAddressDetectsThorChainStagenet() {
        let rune = SendFormFixture.makeCoin(.thorChainStagenet, ticker: "RUNE", decimals: 8, isNative: true)
        let vault = SendFormFixture.makeVault(coins: [rune])

        let detected = AddressService.detectChain(from: stagenetThorAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertEqual(detected, .thorChainStagenet)
    }

    func testQbtcAddressDetectsQbtc() {
        let qbtc = SendFormFixture.makeCoin(.qbtc, ticker: "QBTC", decimals: 8, isNative: true)
        let vault = SendFormFixture.makeVault(coins: [qbtc])

        let detected = AddressService.detectChain(from: qbtcAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertEqual(detected, .qbtc)
    }

    func testQbtcAddressReturnsNilWhenChainMissingFromVault() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])

        let detected = AddressService.detectChain(from: qbtcAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    // MARK: - Bittensor (SS58)

    func testBittensorAddressDetectsBittensor() {
        let tao = SendFormFixture.makeCoin(.bittensor, ticker: "TAO", decimals: 9, isNative: true)
        let vault = SendFormFixture.makeVault(coins: [tao])

        let detected = AddressService.detectChain(from: bittensorAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertEqual(detected, .bittensor)
    }

    func testBittensorAddressReturnsNilWhenChainMissingFromVault() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])

        let detected = AddressService.detectChain(from: bittensorAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    // MARK: - EVM

    func testEvmAddressNeverAutoSwitches() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeETH(), SendFormFixture.makeBTC()])

        let detected = AddressService.detectChain(from: evmAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    // MARK: - Loop path

    func testBitcoinAddressDetectsBitcoin() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])
        let btcAddress = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"

        let detected = AddressService.detectChain(from: btcAddress, vault: vault, currentChain: .litecoin)

        XCTAssertEqual(detected, .bitcoin)
    }

    func testUnknownChainForVaultReturnsNil() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeETH()])
        let btcAddress = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"

        let detected = AddressService.detectChain(from: btcAddress, vault: vault, currentChain: .litecoin)

        XCTAssertNil(detected)
    }
}
