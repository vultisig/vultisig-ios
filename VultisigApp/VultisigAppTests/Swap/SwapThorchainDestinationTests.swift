//
//  SwapThorchainDestinationTests.swift
//  VultisigAppTests
//
//  Locks the THORChain swap `destination` contract, in particular for secured
//  assets: the mint settles on THORChain, so the destination must be a
//  THORChain (`thor1…`) address (the vault's own). A non-THORChain destination
//  (empty / L1 `0x…`) is what THORNode rejects with "swap destination address
//  is not the same chain as the target asset", so it must fail up front with a
//  clear error instead of a collapsed quote. Non-secured and external-recipient
//  paths stay unchanged.
//

@testable import VultisigApp
import XCTest

@MainActor
final class SwapThorchainDestinationTests: XCTestCase {

    /// A checksum-valid THORChain mainnet address (the vault's own thor address).
    private let validThorAddress = "thor147fr229jewf063mv5w398e5dld00ytu2y8snmh"

    // MARK: - Secured-asset destination

    func testSecuredEthUsdcResolvesToVaultThorchainAddress() throws {
        let coin = makeCoin(
            ticker: "USDC",
            chain: .thorChain,
            contractAddress: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNative: false,
            address: validThorAddress
        )

        let destination = try SwapService.resolveThorchainDestination(toCoin: coin, recipientAddress: nil)
        XCTAssertEqual(destination, validThorAddress)
    }

    func testSecuredBtcResolvesToVaultThorchainAddress() throws {
        // A different secured denom (`securedAssetChain` == BTC) still mints on
        // THORChain, so the destination is the same vault thor address.
        let coin = makeCoin(
            ticker: "BTC",
            chain: .thorChain,
            contractAddress: "btc-btc",
            isNative: false,
            address: validThorAddress
        )

        let destination = try SwapService.resolveThorchainDestination(toCoin: coin, recipientAddress: nil)
        XCTAssertEqual(destination, validThorAddress)
    }

    func testSecuredToCoinWithEmptyAddressThrows() {
        let coin = makeCoin(
            ticker: "USDC",
            chain: .thorChain,
            contractAddress: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNative: false,
            address: ""
        )

        XCTAssertThrowsError(try SwapService.resolveThorchainDestination(toCoin: coin, recipientAddress: nil))
    }

    func testSecuredToCoinWithL1AddressThrows() {
        // An Ethereum `0x…` value is exactly what THORNode rejects; catch it here.
        let coin = makeCoin(
            ticker: "USDC",
            chain: .thorChain,
            contractAddress: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNative: false,
            address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        )

        XCTAssertThrowsError(try SwapService.resolveThorchainDestination(toCoin: coin, recipientAddress: nil))
    }

    // MARK: - Non-secured / recipient regression guards (unchanged behaviour)

    func testNativeRuneReturnsAddressUnchanged() throws {
        // Swap-to RUNE (and the swap-from-secured path, where RUNE is the toCoin)
        // is not a secured asset — destination is the address as-is.
        let coin = makeCoin(
            ticker: "RUNE",
            chain: .thorChain,
            contractAddress: "",
            isNative: true,
            address: validThorAddress
        )

        let destination = try SwapService.resolveThorchainDestination(toCoin: coin, recipientAddress: nil)
        XCTAssertEqual(destination, validThorAddress)
    }

    func testNonThorchainTokenReturnsAddressUnchanged() throws {
        // A regular L1 destination (e.g. ETH-side token) keeps its own `0x…`
        // address; the secured guard never applies off THORChain.
        let ethAddress = "0x1234567890abcdef1234567890abcdef12345678"
        let coin = makeCoin(
            ticker: "USDC",
            chain: .ethereum,
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNative: false,
            address: ethAddress
        )

        let destination = try SwapService.resolveThorchainDestination(toCoin: coin, recipientAddress: nil)
        XCTAssertEqual(destination, ethAddress)
    }

    func testExternalRecipientIsUsedUnchanged() throws {
        // An explicit external recipient wins and is passed through verbatim,
        // even for a secured toCoin — the recipient path is unchanged.
        let coin = makeCoin(
            ticker: "USDC",
            chain: .thorChain,
            contractAddress: "eth-usdc-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            isNative: false,
            address: validThorAddress
        )
        let recipient = "thor1kkmnmgvd85puk8zsvqfxx36cqy9mxqret39t8z"

        let destination = try SwapService.resolveThorchainDestination(toCoin: coin, recipientAddress: recipient)
        XCTAssertEqual(destination, recipient)
    }

    // MARK: - Address validator

    func testIsValidThorchainAddress() {
        XCTAssertTrue(THORChainHelper.isValidThorchainAddress(validThorAddress, chain: .thorChain))
        XCTAssertFalse(THORChainHelper.isValidThorchainAddress("", chain: .thorChain))
        XCTAssertFalse(THORChainHelper.isValidThorchainAddress(
            "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            chain: .thorChain
        ))
    }

    // MARK: - Helpers

    private func makeCoin(
        ticker: String,
        chain: Chain,
        contractAddress: String,
        isNative: Bool,
        address: String
    ) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 8,
            priceProviderId: "",
            contractAddress: contractAddress,
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: address, hexPublicKey: "test")
    }
}
