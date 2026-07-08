//
//  LimitSwapPayloadGasTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

/// `limitDepositChainSpecific` aligns a native-EVM limit deposit's gas limit
/// with the market native-EVM THORChain deposit (120000). It must change ONLY
/// the EVM gas-limit field and be a no-op for non-EVM / token sources.
@MainActor
final class LimitSwapPayloadGasTests: XCTestCase {

    private var storeToken: TestContextToken!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func nativeCoin(chain: Chain, ticker: String, decimals: Int) -> Coin {
        Coin(
            asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true),
            address: "0xsender0000000000000000000000000000000000",
            hexPublicKey: "pubkey"
        )
    }

    private func ethSpecific(gasLimit: BigInt) -> BlockChainSpecific {
        .Ethereum(maxFeePerGasWei: BigInt(30), priorityFeeWei: BigInt(2), nonce: 7, gasLimit: gasLimit)
    }

    private func extractedGasLimit(_ specific: BlockChainSpecific) -> BigInt? {
        guard case let .Ethereum(_, _, _, gasLimit) = specific else { return nil }
        return gasLimit
    }

    func testMarketValueIsOneHundredTwentyThousand() {
        // Pin the exact market native-EVM THORChain deposit gas limit.
        XCTAssertEqual(BigInt(EVMHelper.defaultERC20TransferGasUnit), BigInt(120_000))
    }

    func testNativeEthDepositGetsMarketGasLimit() {
        let coin = nativeCoin(chain: .ethereum, ticker: "ETH", decimals: 18)
        // The current fallback (`normalizeGasLimit(.swap)`) over-gasses at 600000.
        let result = limitDepositChainSpecific(ethSpecific(gasLimit: BigInt(600_000)), sourceCoin: coin)

        XCTAssertEqual(extractedGasLimit(result), BigInt(120_000))
        // Fees / priority / nonce must be untouched.
        guard case let .Ethereum(maxFee, priority, nonce, _) = result else {
            return XCTFail("Expected .Ethereum")
        }
        XCTAssertEqual(maxFee, BigInt(30))
        XCTAssertEqual(priority, BigInt(2))
        XCTAssertEqual(nonce, 7)
    }

    func testNativeAvaxDepositGetsMarketGasLimit() {
        let coin = nativeCoin(chain: .avalanche, ticker: "AVAX", decimals: 18)
        let result = limitDepositChainSpecific(ethSpecific(gasLimit: BigInt(600_000)), sourceCoin: coin)
        XCTAssertEqual(extractedGasLimit(result), BigInt(120_000))
    }

    func testTokenEvmSourceIsUnchanged() {
        let coin = Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false),
            address: "0xsender0000000000000000000000000000000000",
            hexPublicKey: "pubkey"
        )
        let result = limitDepositChainSpecific(ethSpecific(gasLimit: BigInt(600_000)), sourceCoin: coin)
        XCTAssertEqual(extractedGasLimit(result), BigInt(600_000), "Token EVM sources (Phase 2) must be untouched")
    }

    func testNonEvmSourceIsUnchanged() {
        // A BTC (UTXO) source fails the chainType guard — even an EVM-shaped
        // specific must pass through unchanged.
        let coin = nativeCoin(chain: .bitcoin, ticker: "BTC", decimals: 8)
        let result = limitDepositChainSpecific(ethSpecific(gasLimit: BigInt(600_000)), sourceCoin: coin)
        XCTAssertEqual(extractedGasLimit(result), BigInt(600_000))
    }
}
