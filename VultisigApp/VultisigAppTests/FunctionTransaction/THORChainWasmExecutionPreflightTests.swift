//
//  THORChainWasmExecutionPreflightTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class THORChainWasmExecutionPreflightTests: XCTestCase {
    func testHaltedNetworkBlocksRujiStake() async {
        let provider = SequencedWasmAvailabilityProvider(states: [.halted])
        let preflight = THORChainWasmExecutionPreflight(availabilityProvider: provider)

        do {
            try await preflight.validate(makeRujiStakeBuilder())
            XCTFail("A halted THORChain WASM runtime must block RUJI staking.")
        } catch let error as THORChainWasmExecutionPreflightError {
            XCTAssertEqual(error, .halted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnavailableOrMissingStateFailsClosed() async {
        for state in [THORChainWasmExecutionAvailability.unavailable, nil] {
            let provider = SequencedWasmAvailabilityProvider(states: [state])
            let preflight = THORChainWasmExecutionPreflight(availabilityProvider: provider)

            do {
                try await preflight.validate(makeRujiStakeBuilder())
                XCTFail("An unverifiable WASM policy must block RUJI staking.")
            } catch let error as THORChainWasmExecutionPreflightError {
                XCTAssertEqual(error, .unavailable)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPreflightReadsFreshStateOnEveryAttempt() async {
        let provider = SequencedWasmAvailabilityProvider(states: [.available, .halted])
        let preflight = THORChainWasmExecutionPreflight(availabilityProvider: provider)
        let builder = makeRujiStakeBuilder()

        try? await preflight.validate(builder)
        try? await preflight.validate(builder)

        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    func testNativeThorchainTransactionSkipsWasmRequest() async throws {
        let provider = SequencedWasmAvailabilityProvider(states: [.halted])
        let preflight = THORChainWasmExecutionPreflight(availabilityProvider: provider)
        let builder = CustomMemoTransactionBuilder(
            coin: makeCoin(asset: TokensStore.tcy),
            customMemo: "tcy+:thor1address",
            customAmount: 1
        )

        try await preflight.validate(builder)

        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testYVaultPreflightIncludesProxyAndTargetContracts() {
        let mint = MintTransactionBuilder(
            coin: makeCoin(asset: TokensStore.rune),
            amount: "1",
            sendMaxAmount: false
        )
        let redeem = RedeemTransactionBuilder(
            coin: makeCoin(asset: TokensStore.yrune),
            amount: "1",
            sendMaxAmount: false,
            slippage: 0.01
        )
        let expected: Set<String> = [
            YVaultConstants.affiliateContractAddress,
            YVaultConstants.contracts["rune"]!
        ]

        XCTAssertEqual(mint.wasmContractAddressesForPreflight, expected)
        XCTAssertEqual(redeem.wasmContractAddressesForPreflight, expected)
    }

    private func makeRujiStakeBuilder() -> RUJIStakeTransactionBuilder {
        RUJIStakeTransactionBuilder(
            coin: makeCoin(asset: TokensStore.ruji),
            amount: "1",
            sendMaxAmount: false
        )
    }

    private func makeCoin(asset: CoinMeta) -> Coin {
        Coin(
            asset: asset,
            address: "thor1fixtureaddress000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }
}

// swiftlint:disable async_without_await
private actor SequencedWasmAvailabilityProvider: THORChainWasmExecutionAvailabilityProviding {
    private var states: [THORChainWasmExecutionAvailability?]
    private(set) var requestCount = 0

    init(states: [THORChainWasmExecutionAvailability?]) {
        self.states = states
    }

    func fetchWasmExecutionAvailabilities(
        for contractAddresses: Set<String>
    ) async -> [String: THORChainWasmExecutionAvailability] {
        requestCount += 1
        let state = states.isEmpty ? nil : states.removeFirst()
        guard let state else { return [:] }
        return contractAddresses.reduce(into: [:]) { result, address in
            result[address] = state
        }
    }
}
// swiftlint:enable async_without_await
