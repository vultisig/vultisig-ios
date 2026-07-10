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

    // MARK: - limitDefaultSourceCoin (limit-entry default source, over real coins)

    private func tokenCoin(chain: Chain, ticker: String, decimals: Int) -> Coin {
        Coin(
            asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: false),
            address: "0xtoken00000000000000000000000000000000000",
            hexPublicKey: "pubkey"
        )
    }

    func testLimitDefaultSourcePrefersBTCOverRuneMarketDefault() {
        let rune = nativeCoin(chain: .thorChain, ticker: "RUNE", decimals: 8)
        let eth = nativeCoin(chain: .ethereum, ticker: "ETH", decimals: 18)
        let btc = nativeCoin(chain: .bitcoin, ticker: "BTC", decimals: 8)
        // Market default RUNE→ETH; BTC held and != target → BTC preferred.
        let resolved = limitDefaultSourceCoin(marketDefault: rune, targetCoin: eth, vaultCoins: [rune, eth, btc])
        XCTAssertEqual(resolved.chain, .bitcoin)
        XCTAssertEqual(resolved.ticker, "BTC")
    }

    func testLimitDefaultSourceAvoidsSameChainSelfPair() {
        // Market default ETH→USDC (both Ethereum) must NOT seed a same-chain
        // self-pair — pick a held native source on another chain (BTC).
        let eth = nativeCoin(chain: .ethereum, ticker: "ETH", decimals: 18)
        let usdc = tokenCoin(chain: .ethereum, ticker: "USDC", decimals: 6)
        let btc = nativeCoin(chain: .bitcoin, ticker: "BTC", decimals: 8)
        let resolved = limitDefaultSourceCoin(marketDefault: eth, targetCoin: usdc, vaultCoins: [eth, usdc, btc])
        XCTAssertEqual(resolved.chain, .bitcoin)
    }

    func testLimitDefaultSourceKeepsMarketDefaultWhenOnlyTargetChainHeld() {
        // Degenerate: only Ethereum assets held — a self-pair is unavoidable, so
        // keep the market default rather than inventing an unheld source.
        let eth = nativeCoin(chain: .ethereum, ticker: "ETH", decimals: 18)
        let usdc = tokenCoin(chain: .ethereum, ticker: "USDC", decimals: 6)
        let resolved = limitDefaultSourceCoin(marketDefault: eth, targetCoin: usdc, vaultCoins: [eth, usdc])
        XCTAssertEqual(resolved.chain, .ethereum)
        XCTAssertEqual(resolved.ticker, "ETH")
    }

    func testLimitDefaultSourceFallsBackToMarketDefaultWhenPreferredNotHeld() {
        // Neither BTC nor ETH held; market default (LTC) isn't the target → keep it.
        let ltc = nativeCoin(chain: .litecoin, ticker: "LTC", decimals: 8)
        let btc = nativeCoin(chain: .bitcoin, ticker: "BTC", decimals: 8)
        let resolved = limitDefaultSourceCoin(marketDefault: ltc, targetCoin: btc, vaultCoins: [ltc])
        XCTAssertEqual(resolved.chain, .litecoin)
    }

    // MARK: - network-fee estimate derivation (chainSpecific -> fee)

    func testThorchainFeeForNativeEvmLimitDepositIsGasPlusPriorityTimesLimit() async throws {
        // The limit path estimates the network fee via
        // limitDepositChainSpecific (pins the native-EVM deposit gas limit to
        // 120000) + SwapCryptoLogic.thorchainFee (the same derivation the market
        // swap / Send use). For EVM that is (maxFee + priority) * gasLimit.
        let vault = TestStore.makeVault()
        let eth = nativeCoin(chain: .ethereum, ticker: "ETH", decimals: 18)
        let specific = limitDepositChainSpecific(ethSpecific(gasLimit: BigInt(600_000)), sourceCoin: eth)
        let fee = try await SwapCryptoLogic.thorchainFee(for: specific, fromCoin: eth, fromAmount: 1, vault: vault)
        XCTAssertEqual(fee, (BigInt(30) + BigInt(2)) * BigInt(120_000))
    }

    func testThorchainFeeForThorDepositUsesFixedGas() async throws {
        // Native RUNE settles via MsgDeposit — the fee is the fixed chain-specific
        // gas, and limitDepositChainSpecific is a no-op for non-EVM sources.
        let vault = TestStore.makeVault()
        let rune = nativeCoin(chain: .thorChain, ticker: "RUNE", decimals: 8)
        let specific = BlockChainSpecific.THORChain(
            accountNumber: 0, sequence: 0, fee: 2_000_000, isDeposit: true, transactionType: 0
        )
        let passed = limitDepositChainSpecific(specific, sourceCoin: rune)
        let fee = try await SwapCryptoLogic.thorchainFee(for: passed, fromCoin: rune, fromAmount: 1, vault: vault)
        XCTAssertEqual(fee, BigInt(2_000_000))
    }
}
