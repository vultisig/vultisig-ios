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

    /// From a chain that cannot hold the address at all, land in the Terra
    /// family rather than sitting still. Which of the two is unknowable from
    /// the address, so vault order breaks the tie.
    func testTerraAddressSwitchesToFirstHeldTerraChain() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNA(), makeLUNC()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .thorChain)

        XCTAssertEqual(detected, .terra)
    }

    /// Same holdings, opposite vault order. Pins that the tie-break is vault
    /// order and NOT `CoinType.allCases` order — WalletCore declares `terra`
    /// before `terraV2`, so an enum-order implementation would answer
    /// `.terraClassic` for this case *and* the one above.
    func testTerraAddressTieBreakFollowsVaultOrderNotCoinTypeOrder() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNC(), makeLUNA()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .thorChain)

        XCTAssertEqual(detected, .terraClassic)
    }

    func testTerraAddressSwitchesToTerraClassicWhenItIsTheOnlyOneHeld() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNC()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .thorChain)

        XCTAssertEqual(detected, .terraClassic)
    }

    func testTerraAddressSwitchesToTerraWhenItIsTheOnlyOneHeld() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNA()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .thorChain)

        XCTAssertEqual(detected, .terra)
    }

    /// Already inside the family: the current-chain check keeps the form put,
    /// so a Terra Classic user pasting a `terra1…` address is never flipped to
    /// Terra V2 — the case where a silent guess would cost real money.
    func testTerraAddressDoesNotSwitchWhenAlreadyOnTerraClassic() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNA(), makeLUNC()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .terraClassic)

        XCTAssertNil(detected)
    }

    func testTerraAddressDoesNotSwitchWhenAlreadyOnTerra() {
        let vault = SendFormFixture.makeVault(coins: [makeLUNA(), makeLUNC()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .terra)

        XCTAssertNil(detected)
    }

    func testTerraAddressReturnsNilWhenNoTerraChainIsHeld() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])

        let detected = AddressService.detectChain(from: terraAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertNil(detected)
    }

    /// Precondition for the family tests: the fixture really is ambiguous and
    /// validates on both networks. Without this, a merely-invalid address
    /// would satisfy the same assertions for the wrong reason.
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

    /// From a non-EVM chain, land in the EVM family rather than leaving the
    /// form on a chain that cannot hold a `0x…` address.
    func testEvmAddressSwitchesToFirstHeldEvmChainFromANonEvmChain() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeETH(), SendFormFixture.makeBTC()])

        let detected = AddressService.detectChain(from: evmAddress, vault: vault, currentChain: .bitcoin)

        XCTAssertEqual(detected, .ethereum)
    }

    /// Still never switches *between* EVM chains: every EVM chain accepts every
    /// `0x…` address, so the current-chain check returns nil before the family
    /// guard is reached. Arbitrum stays Arbitrum even though the vault holds ETH.
    func testEvmAddressDoesNotSwitchWhenAlreadyOnAnEvmChain() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeETH(), SendFormFixture.makeBTC()])

        let detected = AddressService.detectChain(from: evmAddress, vault: vault, currentChain: .arbitrum)

        XCTAssertNil(detected)
    }

    func testEvmAddressReturnsNilWhenNoEvmChainIsHeld() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeBTC()])

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
