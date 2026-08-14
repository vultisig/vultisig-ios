//
//  AddLPTransactionViewModelTests.swift
//  VultisigAppTests
//
//  The defect this migration exists to fix: a destination resolved for the
//  asset the pool picker just replaced.
//
//  The form this replaces resolved the inbound address exactly once, on load,
//  and its pool dropdown then reassigned the source asset without re-resolving
//  anything. Two reachable shapes on one EVM chain, both covered below:
//
//  • **native → ERC-20** — the recipient stayed the inbound VAULT while the
//    deposit was built against the ROUTER, so the approval named the vault as
//    its spender and the deposit failed for lack of allowance.
//  • **ERC-20 → native** — the recipient stayed the ROUTER, no shim was
//    synthesized because the new asset needs no approval, and a plain native
//    transfer was signed straight at the router contract.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class AddLPTransactionViewModelTests: XCTestCase {

    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func makeChainViewModel(
        coin: Coin,
        holdings: [Coin],
        pools: [ThorchainPool] = [
            AddLPFixture.pool(AddLPFixture.ethPool),
            AddLPFixture.pool(AddLPFixture.usdcPool)
        ],
        fetch: @escaping ThorchainLPDestinationResolver.InboundAddressFetch = AddLPFixture.healthyFetch,
        locale: Locale = Locale(identifier: "en_US")
    ) -> AddLPTransactionViewModel {
        let vault = FunctionActionFixture.makeVault(coins: holdings)
        return AddLPTransactionViewModel(
            coin: coin,
            pairedCoin: vault.nativeCoin(for: .thorChain),
            protocolChain: .thorChain,
            poolSource: .chosen,
            vault: vault,
            prefillsFullBalance: false,
            resolveInboundAddresses: fetch,
            fetchPools: { pools },
            locale: locale
        )
    }

    /// Drives `loadPools()` to completion. The load is a detached task, so a
    /// test that read `pools` straight after `onLoad()` would read an empty list
    /// and pass for the wrong reason.
    private func awaitPools(_ viewModel: AddLPTransactionViewModel) async throws {
        for _ in 0..<200 where viewModel.poolsState == .loading || viewModel.poolsState == .idle {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotEqual(viewModel.poolsState, .idle, "pool load never started")
        XCTAssertNotEqual(viewModel.poolsState, .loading, "pool load never finished")
    }

    private func pool(_ asset: String, in viewModel: AddLPTransactionViewModel) throws -> THORChainAsset {
        try XCTUnwrap(
            viewModel.pools.first { $0.thorchainAsset == asset },
            "\(asset) is not on offer; pools = \(viewModel.pools.map(\.thorchainAsset))"
        )
    }

    // MARK: - native → ERC-20

    /// ⚠️ Open on ETH, pick the `ETH.USDC` pool. The deposit is now an ERC-20
    /// one, so both the recipient and the spender the approval will name must be
    /// the ROUTER — not the inbound vault the native form resolved.
    func testSwitchingFromNativeToAnERC20PoolResolvesTheRouter() async throws {
        let ether = AddLPFixture.ether()
        let usdc = AddLPFixture.usdc()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, usdc, AddLPFixture.rune()]
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)

        viewModel.select(pool: try pool(AddLPFixture.usdcPool, in: viewModel))
        viewModel.amountField.value = "10"
        let built = await viewModel.prepareTransactionBuilder()
        let builder = try XCTUnwrap(built)

        XCTAssertEqual(viewModel.coin.ticker, "USDC", "the pool decides which asset is deposited")
        XCTAssertEqual(
            builder.toAddress,
            AddLPFixture.ethRouter,
            "an ERC-20 deposit is built against the router, so the router is also the spender approved"
        )
        XCTAssertNotEqual(
            builder.toAddress,
            AddLPFixture.ethVault,
            "the inbound vault is the address the stale native resolution left behind"
        )
        XCTAssertTrue(viewModel.showsApprovalInfo)
        XCTAssertEqual(builder.memo, "+:\(AddLPFixture.usdcPool):\(AddLPFixture.thorAddress)")
    }

    // MARK: - ERC-20 → native

    /// ⚠️ Open on USDC, pick the `ETH.ETH` pool. The deposit is now a plain
    /// native transfer, and its recipient must be the inbound VAULT. Left at the
    /// router the legacy form had resolved, the wallet signed a native transfer
    /// straight to a contract that was never going to credit it.
    func testSwitchingFromAnERC20ToANativePoolResolvesTheInboundVault() async throws {
        let ether = AddLPFixture.ether()
        let usdc = AddLPFixture.usdc()
        let viewModel = makeChainViewModel(
            coin: usdc,
            holdings: [ether, usdc, AddLPFixture.rune()]
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)

        viewModel.select(pool: try pool(AddLPFixture.usdcPool, in: viewModel))
        viewModel.select(pool: try pool(AddLPFixture.ethPool, in: viewModel))
        viewModel.amountField.value = "0.5"
        let built = await viewModel.prepareTransactionBuilder()
        let builder = try XCTUnwrap(built)

        XCTAssertEqual(viewModel.coin.ticker, "ETH")
        XCTAssertEqual(
            builder.toAddress,
            AddLPFixture.ethVault,
            "a native deposit goes to the inbound vault"
        )
        XCTAssertNotEqual(
            builder.toAddress,
            AddLPFixture.ethRouter,
            "signing a native transfer at the router contract is the bug"
        )
        XCTAssertFalse(viewModel.showsApprovalInfo, "a native deposit needs no approval")
    }

    // MARK: - Invalidation

    /// ⚠️ The mechanical guard behind both cases above: choosing a different
    /// pool throws the resolved destination away rather than carrying it over.
    func testSwitchingPoolsInvalidatesAPreviouslyResolvedDestination() async throws {
        let ether = AddLPFixture.ether()
        let usdc = AddLPFixture.usdc()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, usdc, AddLPFixture.rune()]
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)

        viewModel.select(pool: try pool(AddLPFixture.ethPool, in: viewModel))
        viewModel.amountField.value = "0.5"
        _ = await viewModel.prepareTransactionBuilder()
        XCTAssertEqual(
            viewModel.destination,
            .inbound(asset: ether.toCoinMeta(), address: AddLPFixture.ethVault, requiresApproval: false)
        )

        viewModel.select(pool: try pool(AddLPFixture.usdcPool, in: viewModel))

        XCTAssertEqual(viewModel.destination, .unresolved, "a resolved destination must not survive the asset change")
    }

    /// Even if a resolved answer somehow survived, it cannot be spent on
    /// another asset: the destination carries the asset it was resolved for, and
    /// `depositAddress(for:)` refuses anything else. This is the belt to the
    /// invalidation's braces.
    func testAResolvedDestinationRefusesADifferentAsset() {
        let ether = AddLPFixture.ether()
        let usdc = AddLPFixture.usdc()
        let destination = LPDepositDestination.inbound(
            asset: usdc.toCoinMeta(),
            address: AddLPFixture.ethRouter,
            requiresApproval: true
        )

        XCTAssertEqual(destination.depositAddress(for: usdc), AddLPFixture.ethRouter)
        XCTAssertNil(destination.depositAddress(for: ether), "a router resolved for USDC is not ETH's destination")
    }

    /// An empty recipient is a legitimate answer for a protocol-native deposit,
    /// so a caller must not read emptiness as "unresolved". `nil` is the refusal
    /// and `""` is the answer.
    func testAnUnresolvedDestinationIsDistinctFromAnEmptyRecipient() {
        let rune = AddLPFixture.rune()

        XCTAssertNil(LPDepositDestination.unresolved.depositAddress(for: rune))
        XCTAssertEqual(
            LPDepositDestination.protocolNative(asset: rune.toCoinMeta()).depositAddress(for: rune),
            .empty
        )
    }

    // MARK: - Route health

    func testAPausedLPRouteProducesNoTransaction() async throws {
        let ether = AddLPFixture.ether()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.ethPool)],
            fetch: { _ in
                [AddLPFixture.inbound(
                    chain: "ETH",
                    address: AddLPFixture.ethVault,
                    router: AddLPFixture.ethRouter,
                    lpActionsPaused: true
                )]
            }
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "0.5"

        let builder = await viewModel.prepareTransactionBuilder()

        XCTAssertNil(builder, "THORChain rejects an LP add while LP actions are paused; the funds would be stranded")
        XCTAssertEqual(viewModel.destination, .lpActionsPaused(chain: "ETH"))
        XCTAssertNotNil(viewModel.blockingMessage)
    }

    func testAnERC20DepositWithNoRouterProducesNoTransaction() async throws {
        let ether = AddLPFixture.ether()
        let usdc = AddLPFixture.usdc()
        let viewModel = makeChainViewModel(
            coin: usdc,
            holdings: [ether, usdc, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.usdcPool)],
            fetch: { _ in [AddLPFixture.inbound(chain: "ETH", address: AddLPFixture.ethVault, router: nil)] }
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "10"

        let built1 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built1)
        XCTAssertEqual(viewModel.destination, .routerNotAvailable(chain: "ETH"))
    }

    func testAnUnknownInboundChainProducesNoTransaction() async throws {
        let ether = AddLPFixture.ether()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.ethPool)],
            fetch: { _ in [] }
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "0.5"

        let built2 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built2)
        XCTAssertEqual(viewModel.destination, .inboundNotFound(chain: "ETH"))
    }

    /// The recipient is fetched with the cache bypassed on the build path.
    /// THORChain churns its inbound vaults, and a five-minute-old address can
    /// already have been retired by the time the user taps Continue.
    func testTheBuildPathBypassesTheInboundCache() async throws {
        var bypassFlags: [Bool] = []
        let ether = AddLPFixture.ether()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.ethPool)],
            fetch: { bypass in
                bypassFlags.append(bypass)
                return AddLPFixture.healthyInbounds()
            }
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "0.5"

        _ = await viewModel.prepareTransactionBuilder()

        XCTAssertTrue(bypassFlags.contains(true), "the transaction's own read must not be served from the cache")
    }

    // MARK: - Amount

    /// ⚠️ `NumberFormatter` reads `1,5` as fifteen in `en_US` rather than
    /// refusing it. On an LP deposit that is a ten-times send from a paste.
    func testACommaDecimalAmountIsRefusedInADotDecimalLocale() async throws {
        let ether = AddLPFixture.ether()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.ethPool)]
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "1,5"

        let built3 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built3, "1,5 must not be read as 15 ETH")
    }

    /// The mirror image: a `de_DE` user's `1,5` is one and a half, and their
    /// `1.5` is the ambiguous one.
    func testACommaDecimalAmountIsAcceptedInACommaDecimalLocale() async throws {
        let ether = AddLPFixture.ether()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.ethPool)],
            locale: Locale(identifier: "de_DE")
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "1,5"

        let built = await viewModel.prepareTransactionBuilder()
        let builder = try XCTUnwrap(built)
        XCTAssertEqual(builder.buildSendTransaction(vault: .example).amountInRaw, BigInt("1500000000000000000"))
    }

    func testAnAmountOverTheBalanceProducesNoTransaction() async throws {
        let ether = AddLPFixture.ether(rawBalance: "1000000000000000000")
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.ethPool)]
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "2"

        let built4 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built4)
    }

    func testAZeroAmountProducesNoTransaction() async throws {
        let ether = AddLPFixture.ether()
        let viewModel = makeChainViewModel(
            coin: ether,
            holdings: [ether, AddLPFixture.rune()],
            pools: [AddLPFixture.pool(AddLPFixture.ethPool)]
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "0"

        let built5 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built5)
    }

    /// An amount typed against one asset's balance and ticker must not be
    /// carried over to another. `100` USDC and `100` ETH are the same digits and
    /// nothing else.
    func testChangingThePoolClearsTheAmount() async throws {
        let ether = AddLPFixture.ether()
        let usdc = AddLPFixture.usdc()
        let viewModel = makeChainViewModel(coin: ether, holdings: [ether, usdc, AddLPFixture.rune()])
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "0.5"

        viewModel.select(pool: try pool(AddLPFixture.usdcPool, in: viewModel))

        XCTAssertEqual(viewModel.amountField.value, .empty)
    }

    // MARK: - Submission gates

    /// A THORChain pool credits a RUNE account the memo names. Without one,
    /// `+:POOL` alone is an asymmetric asset-only deposit — a different
    /// operation from the one the user asked for.
    func testAVaultWithoutRuneCannotDeposit() async throws {
        let ether = AddLPFixture.ether()
        let vault = FunctionActionFixture.makeVault(coins: [ether])
        let viewModel = AddLPTransactionViewModel(
            coin: ether,
            pairedCoin: nil,
            protocolChain: .thorChain,
            poolSource: .chosen,
            vault: vault,
            prefillsFullBalance: false,
            resolveInboundAddresses: AddLPFixture.healthyFetch,
            fetchPools: { [AddLPFixture.pool(AddLPFixture.ethPool)] },
            locale: Locale(identifier: "en_US")
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "0.5"

        XCTAssertFalse(viewModel.isThorchainEnabled)
        let built6 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built6)
    }

    /// The form opens before a pool is chosen, and nothing can be built until
    /// one is.
    func testNoPoolMeansNoTransaction() async throws {
        let ether = AddLPFixture.ether()
        let usdc = AddLPFixture.usdc()
        let viewModel = makeChainViewModel(coin: ether, holdings: [ether, usdc, AddLPFixture.rune()])
        viewModel.onLoad()
        try await awaitPools(viewModel)
        viewModel.amountField.value = "0.5"

        XCTAssertNil(viewModel.selectedPool, "two pools on offer, so neither is auto-selected")
        let built7 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built7)
    }

    /// A chain offering exactly one depositable pool has nothing to ask.
    func testASinglePoolIsSelectedAutomatically() async throws {
        let bitcoin = AddLPFixture.bitcoin()
        let vault = FunctionActionFixture.makeVault(coins: [bitcoin, AddLPFixture.rune()])
        let viewModel = AddLPTransactionViewModel(
            coin: bitcoin,
            pairedCoin: vault.nativeCoin(for: .thorChain),
            protocolChain: .thorChain,
            poolSource: .chosen,
            vault: vault,
            prefillsFullBalance: false,
            resolveInboundAddresses: AddLPFixture.healthyFetch,
            fetchPools: { [AddLPFixture.pool(AddLPFixture.btcPool)] },
            locale: Locale(identifier: "en_US")
        )
        viewModel.onLoad()
        try await awaitPools(viewModel)

        XCTAssertEqual(viewModel.selectedPool?.thorchainAsset, AddLPFixture.btcPool)
        XCTAssertEqual(viewModel.poolName, AddLPFixture.btcPool)
    }

    // MARK: - The DeFi tab's entry point

    /// Unchanged behaviour for the caller that exists today: a THORChain
    /// position deposits RUNE, pairs the L1 address, and names no recipient
    /// because it rides a `MsgDeposit`.
    func testAPositionDepositsTheProtocolSideByDefault() async throws {
        let rune = AddLPFixture.rune()
        let bitcoin = AddLPFixture.bitcoin()
        let vault = FunctionActionFixture.makeVault(coins: [rune, bitcoin])
        let position = LPPosition(
            coin1: rune.toCoinMeta(),
            coin1Amount: 10,
            coin2: bitcoin.toCoinMeta(),
            coin2Amount: 1,
            poolName: AddLPFixture.btcPool,
            poolUnits: "1",
            apr: 0,
            vault: vault
        )

        let viewModel = AddLPTransactionViewModel.position(
            coin1: rune,
            coin2: bitcoin,
            side: .coin1,
            position: position,
            vault: vault
        )
        viewModel.onLoad()
        viewModel.amountField.value = "1"
        let built = await viewModel.prepareTransactionBuilder()
        let builder = try XCTUnwrap(built)

        XCTAssertEqual(viewModel.coin.ticker, "RUNE")
        XCTAssertFalse(viewModel.showsPoolPicker, "the card the user tapped already decided the pool")
        XCTAssertEqual(builder.memo, "+:\(AddLPFixture.btcPool):\(FunctionActionFixture.btcAddress)")
        XCTAssertEqual(builder.toAddress, .empty, "a RUNE-side deposit rides a MsgDeposit")
        XCTAssertFalse(
            builder.buildSendTransaction(vault: vault).sendMaxAmount,
            "the 100% pre-fill is a convenience, not a send-max — it changes how a UTXO tx is planned"
        )
    }

    /// `sendMaxAmount` follows a percentage the USER tapped, exactly as it did
    /// before the migration.
    func testTappingOneHundredPercentIsASendMax() async throws {
        let rune = AddLPFixture.rune()
        let bitcoin = AddLPFixture.bitcoin()
        let vault = FunctionActionFixture.makeVault(coins: [rune, bitcoin])
        let position = LPPosition(
            coin1: rune.toCoinMeta(),
            coin1Amount: 10,
            coin2: bitcoin.toCoinMeta(),
            coin2Amount: 1,
            poolName: AddLPFixture.btcPool,
            poolUnits: "1",
            apr: 0,
            vault: vault
        )

        let viewModel = AddLPTransactionViewModel.position(
            coin1: rune,
            coin2: bitcoin,
            side: .coin1,
            position: position,
            vault: vault
        )
        viewModel.onLoad()
        viewModel.onPercentage(100)
        viewModel.amountField.value = "1"
        let built = await viewModel.prepareTransactionBuilder()
        let builder = try XCTUnwrap(built)

        XCTAssertTrue(builder.buildSendTransaction(vault: vault).sendMaxAmount)
    }

    /// ⚠️ The generalisation the intent gained: the L1 side of the same
    /// position is now depositable, and it resolves the L1 inbound vault rather
    /// than inheriting the protocol side's empty recipient.
    func testAPositionCanDepositTheL1Side() async throws {
        let rune = AddLPFixture.rune()
        let bitcoin = AddLPFixture.bitcoin()
        let vault = FunctionActionFixture.makeVault(coins: [rune, bitcoin])
        let position = LPPosition(
            coin1: rune.toCoinMeta(),
            coin1Amount: 10,
            coin2: bitcoin.toCoinMeta(),
            coin2Amount: 1,
            poolName: AddLPFixture.btcPool,
            poolUnits: "1",
            apr: 0,
            vault: vault
        )

        let viewModel = AddLPTransactionViewModel(
            coin: bitcoin,
            pairedCoin: rune,
            protocolChain: .thorChain,
            poolSource: .fixed(pool: position.poolName),
            vault: vault,
            prefillsFullBalance: true,
            resolveInboundAddresses: AddLPFixture.healthyFetch,
            fetchPools: { [] },
            locale: Locale(identifier: "en_US")
        )
        viewModel.onLoad()
        viewModel.amountField.value = "0.5"
        let built = await viewModel.prepareTransactionBuilder()
        let builder = try XCTUnwrap(built)

        XCTAssertEqual(builder.toAddress, AddLPFixture.btcVault)
        XCTAssertEqual(builder.memo, "+:\(AddLPFixture.btcPool):\(FunctionActionFixture.thorAddress)")
    }

    /// ⚠️ Fail closed. Only THORChain's inbound vaults are read here, so an
    /// L1-side deposit into a MayaChain pool must refuse rather than send funds
    /// to a vault that has never heard of the memo.
    func testAnL1SideMayachainDepositFailsClosed() async throws {
        let cacao = FunctionActionFixture.makeCoin(
            .mayaChain,
            ticker: "CACAO",
            decimals: 10,
            isNative: true,
            address: FunctionActionFixture.mayaAddress
        )
        let bitcoin = AddLPFixture.bitcoin()
        let vault = FunctionActionFixture.makeVault(coins: [cacao, bitcoin])

        let viewModel = AddLPTransactionViewModel(
            coin: bitcoin,
            pairedCoin: cacao,
            protocolChain: .mayaChain,
            poolSource: .fixed(pool: AddLPFixture.btcPool),
            vault: vault,
            prefillsFullBalance: true,
            resolveInboundAddresses: AddLPFixture.healthyFetch,
            fetchPools: { [] },
            locale: Locale(identifier: "en_US")
        )
        viewModel.onLoad()
        viewModel.amountField.value = "0.5"

        let built8 = await viewModel.prepareTransactionBuilder()
        XCTAssertNil(built8)
        XCTAssertEqual(viewModel.destination, .unsupportedProtocol)
    }

    /// A MayaChain deposit credits the depositing address itself, so the memo
    /// carries no paired address.
    func testAMayachainPositionDepositTakesNoPairedAddress() async throws {
        let cacao = FunctionActionFixture.makeCoin(
            .mayaChain,
            ticker: "CACAO",
            decimals: 10,
            isNative: true,
            rawBalance: "100000000000",
            address: FunctionActionFixture.mayaAddress
        )
        let bitcoin = AddLPFixture.bitcoin()
        let vault = FunctionActionFixture.makeVault(coins: [cacao, bitcoin])

        let viewModel = AddLPTransactionViewModel(
            coin: cacao,
            pairedCoin: bitcoin,
            protocolChain: .mayaChain,
            poolSource: .fixed(pool: AddLPFixture.btcPool),
            vault: vault,
            prefillsFullBalance: true,
            resolveInboundAddresses: AddLPFixture.healthyFetch,
            fetchPools: { [] },
            locale: Locale(identifier: "en_US")
        )
        viewModel.onLoad()
        viewModel.amountField.value = "1"
        let built = await viewModel.prepareTransactionBuilder()
        let builder = try XCTUnwrap(built)

        XCTAssertNil(viewModel.pairedAddress)
        XCTAssertEqual(builder.memo, "+:\(AddLPFixture.btcPool)")
        XCTAssertEqual(builder.toAddress, .empty)
        XCTAssertTrue(viewModel.showAsymmetricDepositInfo)
    }
}
