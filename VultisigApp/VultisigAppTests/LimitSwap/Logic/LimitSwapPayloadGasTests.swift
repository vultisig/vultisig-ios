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

    // MARK: - global-pause gate for the RUNE MsgDeposit branch

    private func inbound(chain: String, globalPaused: Bool?) -> InboundAddress {
        InboundAddress(
            chain: chain,
            address: "addr-\(chain)",
            router: nil,
            halted: false,
            global_trading_paused: globalPaused,
            chain_trading_paused: false,
            chain_lp_actions_paused: false,
            gas_rate: "0",
            gas_rate_units: "u",
            dust_threshold: nil,
            outbound_fee: nil,
            outbound_tx_size: nil
        )
    }

    func testGloballyPausedWhenAnyRowIsPaused() {
        // THORChain sets global_trading_paused on every row when it halts trading
        // network-wide; a RUNE MsgDeposit must fail closed against it.
        let inbounds = [
            inbound(chain: "BTC", globalPaused: false),
            inbound(chain: "ETH", globalPaused: true)
        ]
        XCTAssertTrue(isThorchainGloballyPaused(inbounds: inbounds))
    }

    func testNotGloballyPausedWhenAllRowsOpen() {
        let inbounds = [
            inbound(chain: "BTC", globalPaused: false),
            inbound(chain: "ETH", globalPaused: false)
        ]
        XCTAssertFalse(isThorchainGloballyPaused(inbounds: inbounds))
    }

    func testNotGloballyPausedWhenFlagMissing() {
        // A missing flag reads as "not paused" — same convention as SwapHaltGate.
        XCTAssertFalse(isThorchainGloballyPaused(inbounds: [inbound(chain: "BTC", globalPaused: nil)]))
    }

    func testRuneDepositBlockedWhenGloballyPaused() {
        let inbounds = [inbound(chain: "BTC", globalPaused: false), inbound(chain: "ETH", globalPaused: true)]
        XCTAssertTrue(shouldBlockRuneDeposit(inbounds: inbounds))
    }

    func testRuneDepositBlockedWhenInboundListEmpty() {
        // Fail closed: an empty (but non-throwing) inbound response means the
        // pause state is unverifiable — never sign a deposit against it.
        XCTAssertTrue(shouldBlockRuneDeposit(inbounds: []))
    }

    func testRuneDepositAllowedWhenAllRowsOpenAndNonEmpty() {
        let inbounds = [inbound(chain: "BTC", globalPaused: false), inbound(chain: "ETH", globalPaused: false)]
        XCTAssertFalse(shouldBlockRuneDeposit(inbounds: inbounds))
    }

    // MARK: - inbound chain-symbol routing (shared with the market halt gate)

    func testGetInboundChainNameCoversLimitRoutableSources() {
        // The assembler now resolves the inbound chain symbol via the shared
        // ThorchainService.getInboundChainName instead of a duplicate switch.
        // Verify it returns the expected THORChain symbol for every non-THOR
        // limit-routable native source (parity with the removed local table).
        let expected: [Chain: String] = [
            .bitcoin: "BTC", .ethereum: "ETH", .litecoin: "LTC",
            .dogecoin: "DOGE", .bitcoinCash: "BCH", .avalanche: "AVAX",
            .bscChain: "BSC", .gaiaChain: "GAIA"
        ]
        for (chain, symbol) in expected {
            XCTAssertTrue(isThorchainRoutable(chain: chain), "\(chain) must be routable")
            XCTAssertEqual(ThorchainService.getInboundChainName(for: chain), symbol)
        }
    }

    // MARK: - ERC20 deposit swap payload (limitThorchainSwapPayload)

    private func usdcSource() -> Coin {
        Coin(
            asset: CoinMeta.make(chain: .ethereum, ticker: "USDC", decimals: 6, isNativeToken: false),
            address: "0xsender0000000000000000000000000000000000",
            hexPublicKey: "pubkey"
        )
    }

    private func btcTarget() -> Coin {
        Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8, isNativeToken: true),
            address: "bc1qtarget",
            hexPublicKey: "pubkey"
        )
    }

    func testErc20DepositRoutesThroughRouterWithVaultAndAmount() {
        // The ERC20 limit deposit is the router's `depositWithExpiry` call:
        // `EVMHelper.getSwapPreSignedInputData` reads routerAddress (tx.to),
        // vaultAddress (asgard, first ABI param) and fromAmount off this payload.
        let source = usdcSource()
        let payload = limitThorchainSwapPayload(
            sourceCoin: source,
            targetCoin: btcTarget(),
            sourceAmount: BigInt(1_000_000),
            vaultAddress: "0xvault0000000000000000000000000000000000",
            routerAddress: "0xrouter000000000000000000000000000000000",
            toAmountDecimal: Decimal(string: "0.037")!,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(payload.routerAddress, "0xrouter000000000000000000000000000000000")
        XCTAssertEqual(payload.vaultAddress, "0xvault0000000000000000000000000000000000")
        XCTAssertEqual(payload.fromAmount, BigInt(1_000_000))
        XCTAssertEqual(payload.fromAddress, source.address)
        XCTAssertEqual(payload.fromCoin.ticker, "USDC")
        XCTAssertEqual(payload.toCoin.ticker, "BTC")
    }

    func testErc20DepositCarriesExpectedOutputForCosignerDisplay() {
        // toAmountDecimal is the guaranteed-minimum output (memo LIM in natural
        // units); it feeds the co-signer's "you receive" row so a 2-device order
        // shows the floor instead of 0. It never influences signing.
        let payload = limitThorchainSwapPayload(
            sourceCoin: usdcSource(),
            targetCoin: btcTarget(),
            sourceAmount: BigInt(1_000_000),
            vaultAddress: "0xvault",
            routerAddress: "0xrouter",
            toAmountDecimal: Decimal(string: "0.037")!,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(payload.toAmountDecimal, Decimal(string: "0.037")!)
    }

    func testErc20DepositExpiryIsFifteenMinutesFromNow() {
        // `depositWithExpiry`'s expiry is the ROUTER's on-chain tx-execution
        // deadline (`require(block.timestamp < expiry)`), NOT the resting order's
        // lifetime — that lives in the `=<` memo's TTL field (up to 3 days,
        // checked per-block by THORChain). Reuse the market path's 15-minute
        // window verbatim: once THORChain observes the deposit (a block or two,
        // far under 15m) the order rests for its full memo TTL regardless.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = limitThorchainSwapPayload(
            sourceCoin: usdcSource(),
            targetCoin: btcTarget(),
            sourceAmount: BigInt(1_000_000),
            vaultAddress: "0xvault",
            routerAddress: "0xrouter",
            toAmountDecimal: 0,
            now: now
        )
        XCTAssertEqual(payload.expirationTime, UInt64(now.addingTimeInterval(60 * 15).timeIntervalSince1970))
        XCTAssertEqual(payload.expirationTime, 1_700_000_900)
    }

    func testErc20DepositIsAffiliateMatchesMarketPath() {
        let payload = limitThorchainSwapPayload(
            sourceCoin: usdcSource(),
            targetCoin: btcTarget(),
            sourceAmount: BigInt(1_000_000),
            vaultAddress: "0xvault",
            routerAddress: "0xrouter",
            toAmountDecimal: 0,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(payload.isAffiliate, SwapCryptoLogic.isAffiliate)
    }
}
