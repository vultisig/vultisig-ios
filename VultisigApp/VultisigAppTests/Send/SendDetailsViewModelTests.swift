//
//  SendDetailsViewModelTests.swift
//  VultisigAppTests
//
//  Form-state lifecycle tests for the new @Observable form VM. Covers init,
//  field updates, derived-state propagation, async refresh paths, custom-gas
//  preservation, zero-amount state reset, and the feeMode bug-fix regression.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendDetailsViewModelTests: XCTestCase {

    // MARK: - Init

    func testInitWithCoinAndVaultSetsBaseline() {
        let vm = SendFormFixture.make()
        XCTAssertEqual(vm.amount, "")
        XCTAssertEqual(vm.toAddress, "")
        XCTAssertEqual(vm.memo, "")
        XCTAssertEqual(vm.feeMode, .default)
        XCTAssertFalse(vm.sendMaxAmount)
        XCTAssertFalse(vm.vault.isFastVault)
        XCTAssertNil(vm.customGasLimit)
        XCTAssertNil(vm.customByteFee)
        XCTAssertTrue(vm.memoFunctionDictionary.isEmpty)
    }

    func testFromAddressMirrorsCoinAddress() {
        let eth = SendFormFixture.makeETH()
        let vm = SendFormFixture.make(coin: eth)
        XCTAssertEqual(vm.fromAddress, eth.address)
    }

    func testFeeCoinResolvesToSelfForNativeSource() {
        let eth = SendFormFixture.makeETH()
        let vm = SendFormFixture.make(coin: eth)
        XCTAssertEqual(vm.feeCoin, eth)
    }

    func testFeeCoinFallsBackToCoinWhenVaultHasNoNative() {
        // Vault has no ETH coin, so the USDC source falls back to itself.
        let vm = SendFormFixture.make(coin: SendFormFixture.makeUSDC())
        XCTAssertEqual(vm.feeCoin, vm.coin)
    }

    // MARK: - Route hydration

    func testHydrateFromSeedPreservesPrefilledSendData() {
        let eth = SendFormFixture.makeETH()
        let vault = SendFormFixture.makeVault(coins: [eth])
        let form = FunctionCallForm()
        form.coin = eth
        form.fromAddress = eth.address
        form.toAddress = "0x1111111111111111111111111111111111111111"
        form.toAddressLabel = "vitalik.eth"
        form.lastResolvedAddress = form.toAddress
        form.amount = "0.25"
        form.amountInFiat = "500"
        form.memo = "hello"
        form.feeMode = .fast
        form.gas = BigInt(30_000_000_000)
        form.fee = BigInt(1_500_000_000_000_000)
        form.customGasLimit = BigInt(50_000)

        let seed = SendDetailsSeed.fromForm(form, vault: vault, hasPreselectedCoin: true)
        let vm = SendFormFixture.make(coin: eth, vault: vault)
        vm.hydrate(from: seed)

        XCTAssertEqual(vm.toAddress, form.toAddress)
        XCTAssertEqual(vm.toAddressLabel, "vitalik.eth")
        XCTAssertEqual(vm.lastResolvedAddress, form.toAddress)
        XCTAssertEqual(vm.amount, "0.25")
        XCTAssertEqual(vm.amountInFiat, "500")
        XCTAssertEqual(vm.memo, "hello")
        XCTAssertEqual(vm.feeMode, .fast)
        XCTAssertEqual(vm.gas, BigInt(30_000_000_000))
        XCTAssertEqual(vm.fee, BigInt(1_500_000_000_000_000))
        XCTAssertEqual(vm.customGasLimit, BigInt(50_000))
    }

    func testDetailsSeedFromFormPreservesPrefilledSendData() {
        let eth = SendFormFixture.makeETH()
        let vault = SendFormFixture.makeVault(coins: [eth])
        let form = FunctionCallForm()
        form.coin = eth
        form.fromAddress = eth.address
        form.toAddress = "0x1111111111111111111111111111111111111111"
        form.toAddressLabel = "vitalik.eth"
        form.lastResolvedAddress = form.toAddress
        form.amount = "0.25"
        form.memo = "hello"
        form.feeMode = .fast
        form.customGasLimit = BigInt(50_000)

        let seed = SendDetailsSeed.fromForm(form, vault: vault, hasPreselectedCoin: true)
        let vm = SendFormFixture.make(coin: eth, vault: vault)
        vm.hydrate(from: seed)

        XCTAssertEqual(seed.coin, eth)
        XCTAssertEqual(seed.vault, vault)
        XCTAssertTrue(seed.hasPreselectedCoin)
        XCTAssertEqual(vm.toAddress, form.toAddress)
        XCTAssertEqual(vm.toAddressLabel, "vitalik.eth")
        XCTAssertEqual(vm.lastResolvedAddress, form.toAddress)
        XCTAssertEqual(vm.amount, "0.25")
        XCTAssertEqual(vm.memo, "hello")
        XCTAssertEqual(vm.feeMode, .fast)
        XCTAssertEqual(vm.customGasLimit, BigInt(50_000))
    }

    // MARK: - Address resolution

    func testValidateToAddressResolvesNamespaceAndStoresLabel() async {
        let resolved = "0x1111111111111111111111111111111111111111"
        let vm = SendFormFixture.make(
            coin: SendFormFixture.makeETH(),
            addressResolver: { input, chain in
                XCTAssertEqual(input, "vitalik.eth")
                XCTAssertEqual(chain, .ethereum)
                return resolved
            }
        )
        vm.toAddress = "vitalik.eth"

        let isValid = await vm.validateToAddress()

        XCTAssertTrue(isValid)
        XCTAssertTrue(vm.isNamespaceResolved)
        XCTAssertEqual(vm.toAddress, resolved)
        XCTAssertEqual(vm.toAddressLabel, "vitalik.eth")
        XCTAssertEqual(vm.lastResolvedAddress, resolved)
    }

    func testValidateFormAllowsResolvedNamespaceAddress() async {
        let resolved = "0x1111111111111111111111111111111111111111"
        let eth = SendFormFixture.makeETH(rawBalance: "1000000000000000000")
        let vm = SendFormFixture.make(
            coin: eth,
            addressResolver: { _, _ in resolved }
        )
        vm.toAddress = "vitalik.eth"
        vm.amount = "0.1"
        vm.gas = BigInt(21_000)
        vm.fee = BigInt(21_000)

        let isValid = await vm.validateForm()

        XCTAssertTrue(isValid)
        XCTAssertEqual(vm.toAddress, resolved)
        XCTAssertEqual(vm.toAddressLabel, "vitalik.eth")
    }

    func testValidateToAddressClearsStaleNamespaceLabelForPlainAddress() async {
        let resolved = "0x2222222222222222222222222222222222222222"
        let vm = SendFormFixture.make(
            coin: SendFormFixture.makeETH(),
            addressResolver: { input, _ in input }
        )
        vm.toAddress = resolved
        vm.toAddressLabel = "old.eth"
        vm.lastResolvedAddress = "0x1111111111111111111111111111111111111111"

        let isValid = await vm.validateToAddress()

        XCTAssertTrue(isValid)
        XCTAssertTrue(vm.isNamespaceResolved)
        XCTAssertEqual(vm.toAddress, resolved)
        XCTAssertNil(vm.toAddressLabel)
        XCTAssertNil(vm.lastResolvedAddress)
    }

    // MARK: - Zero-amount state reset (Phase D lesson)

    func testEmptyAmountClearsDerivedStateOnLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(interactor: interactor)
        // Seed prior state.
        vm.amount = "1.0"
        vm.gas = BigInt(50)
        vm.fee = BigInt(5000)
        vm.estimatedGasLimit = BigInt(21000)

        // Phase D lesson: clearing the amount must clear derived fields.
        vm.amount = ""
        await vm.loadGasInfo()

        XCTAssertEqual(vm.gas, .zero)
        XCTAssertEqual(vm.fee, .zero)
        XCTAssertNil(vm.estimatedGasLimit)
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 0,
                       "loadGasInfo must short-circuit on empty amount — no service calls.")
    }

    func testZeroAmountShortCircuitsLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(interactor: interactor)
        vm.amount = "0"
        await vm.loadGasInfo()
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 0)
        XCTAssertEqual(interactor.calculateEVMFeeCalls.count, 0)
    }

    // MARK: - feeMode bug-fix regression

    func testLoadGasInfoForwardsFeeMode() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.amount = "0.1"
        vm.toAddress = "0xabc"
        vm.feeMode = .fast

        await vm.loadGasInfo()

        XCTAssertEqual(interactor.fetchChainSpecificCalls.last?.feeMode, .fast,
                       "loadGasInfo must thread tx.feeMode through fetchChainSpecific (regression for #4347's feeMode bug fix).")
        XCTAssertEqual(interactor.calculateEVMFeeCalls.last?.feeMode, .fast,
                       "calculateEVMFee must receive the user's pinned feeMode, not .default.")
    }

    func testChangingFeeModeAndRefetchingProducesNewCalls() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.amount = "0.1"
        vm.toAddress = "0xabc"

        vm.feeMode = .default
        await vm.loadGasInfo()
        vm.feeMode = .fast
        await vm.loadGasInfo()

        let modes = interactor.fetchChainSpecificCalls.map { $0.feeMode }
        XCTAssertEqual(modes, [.default, .fast])
    }

    // MARK: - Custom gas preservation

    func testCustomGasLimitPinnedThroughLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(), interactor: interactor)
        vm.amount = "0.1"
        vm.toAddress = "0xabc"
        vm.customGasLimit = BigInt(50_000)

        await vm.loadGasInfo()

        XCTAssertEqual(vm.customGasLimit, BigInt(50_000),
                       "User-pinned custom gas limit must survive a Verify refresh.")
        XCTAssertEqual(interactor.calculateEVMFeeCalls.last?.gasLimit, BigInt(50_000),
                       "Fee calculation must use the user-pinned gas limit, not the default transfer limit.")
    }

    func testERC20DefaultGasLimitUsesTokenTransferLimit() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeUSDC())

        XCTAssertEqual(vm.gasLimit, BigInt(EVMHelper.defaultERC20TransferGasUnit))
    }

    func testCustomByteFeePinnedThroughLoadGasInfo() async {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC(), interactor: interactor)
        vm.amount = "0.01"
        vm.toAddress = "bc1qabc"
        vm.customByteFee = BigInt(80)

        await vm.loadGasInfo()

        XCTAssertEqual(vm.customByteFee, BigInt(80))
        XCTAssertEqual(vm.byteFee, BigInt(80),
                       "byteFee accessor must prefer the user-pinned customByteFee over the chain-fetched gas.")
    }

    // MARK: - sendMaxAmount semantics

    func testSetSendMaxAmountTrueForUTXOSetsFlag() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.sendMaxAmount = true
        XCTAssertTrue(vm.sendMaxAmount)
    }

    // MARK: - Pending transaction state

    func testInitializePendingTransactionStateForCosmosChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeATOM())
        vm.initializePendingTransactionState(for: .gaiaChain)
        XCTAssertTrue(vm.isCheckingPendingTransactions)
    }

    func testInitializePendingTransactionStateClearsForNonCosmosChain() {
        let vm = SendFormFixture.make()
        vm.isCheckingPendingTransactions = true
        vm.hasPendingTransaction = true
        vm.pendingTransactionCountdown = 5
        vm.initializePendingTransactionState(for: .bitcoin)
        XCTAssertFalse(vm.isCheckingPendingTransactions)
        XCTAssertFalse(vm.hasPendingTransaction)
        XCTAssertEqual(vm.pendingTransactionCountdown, 0)
    }

    // MARK: - Reset

    func testResetClearsEveryFormFieldButPreservesVaultAndNewCoin() {
        let originalCoin = SendFormFixture.makeETH()
        let newCoin = SendFormFixture.makeBTC()
        let vm = SendFormFixture.make(coin: originalCoin)
        vm.amount = "1.0"
        vm.toAddress = "0xabc"
        vm.memo = "test"
        vm.gas = BigInt(50)
        vm.fee = BigInt(5000)
        vm.customGasLimit = BigInt(50_000)
        vm.memoFunctionDictionary = ["pool": "BTC.BTC"]

        vm.reset(to: newCoin)

        XCTAssertEqual(vm.coin, newCoin)
        XCTAssertEqual(vm.fromAddress, newCoin.address)
        XCTAssertEqual(vm.amount, "")
        XCTAssertEqual(vm.toAddress, "")
        XCTAssertEqual(vm.memo, "")
        XCTAssertEqual(vm.gas, .zero)
        XCTAssertEqual(vm.fee, .zero)
        XCTAssertNil(vm.customGasLimit)
        XCTAssertTrue(vm.memoFunctionDictionary.isEmpty)
    }

    // MARK: - Fast vault
    // `vault.isFastVault` is the unified read — cache-first with structural
    // fallback. The cache is populated by `FastVaultEligibilityRefresher`
    // (see its tests for the populate path).

    func testVaultIsFastVaultReflectsCachedTrue() {
        let vault = SendFormFixture.makeVault()
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date()
        let vm = SendFormFixture.make(vault: vault)
        XCTAssertTrue(vm.vault.isFastVault)
    }

    func testVaultIsFastVaultReflectsCachedFalse() {
        let vault = SendFormFixture.makeVault()
        vault.fastVaultEligibility = false
        vault.fastVaultEligibilityCheckedAt = Date()
        let vm = SendFormFixture.make(vault: vault)
        XCTAssertFalse(vm.vault.isFastVault)
    }

    func testVaultIsFastVaultFallsBackToStructuralWhenCacheEmpty() {
        // No cache yet (checkedAt == nil). With a `server-` signer in the
        // list, the structural fallback returns true.
        let vault = SendFormFixture.makeVault()
        vault.signers = ["iPhone-test", "server-abc"]
        let vm = SendFormFixture.make(vault: vault)
        XCTAssertTrue(vm.vault.isFastVault)
    }

    // MARK: - Amount sync validation (Phase 2b)

    func testValidateAmountAcceptsValidDecimal() {
        let vm = SendFormFixture.make()
        vm.validateAmount("0.5")
        XCTAssertTrue(vm.isValidForm)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.showAlert)
    }

    func testValidateAmountRejectsNonDecimal() {
        let vm = SendFormFixture.make()
        vm.validateAmount("not-a-number")
        XCTAssertFalse(vm.isValidForm)
        XCTAssertEqual(vm.errorTitle, "error")
        XCTAssertEqual(vm.errorMessage, "decimalAmountError".localized)
        XCTAssertTrue(vm.showAlert)
    }

    func testValidateAmountClearsPriorError() {
        let vm = SendFormFixture.make()
        vm.validateAmount("garbage")
        vm.validateAmount("1.0")
        XCTAssertTrue(vm.isValidForm)
        XCTAssertEqual(vm.errorTitle, "")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - showLoader

    func testShowLoaderMirrorsIsValidatingForm() {
        let vm = SendFormFixture.make()
        XCTAssertFalse(vm.showLoader)
        vm.isValidatingForm = true
        XCTAssertTrue(vm.showLoader)
        vm.isValidatingForm = false
        XCTAssertFalse(vm.showLoader)
    }

    // MARK: - continueButtonDisabled gating

    func testContinueButtonDisabledWhenLoading() {
        let vm = SendFormFixture.make()
        vm.isLoading = true
        XCTAssertTrue(vm.continueButtonDisabled)
    }

    func testContinueButtonDisabledWhenValidating() {
        let vm = SendFormFixture.make()
        vm.isValidatingForm = true
        XCTAssertTrue(vm.continueButtonDisabled)
    }

    func testContinueButtonEnabledWhenIdle() {
        let vm = SendFormFixture.make()
        XCTAssertFalse(vm.continueButtonDisabled)
    }

    // MARK: - Pending transaction state machine

    func testRefreshPendingTransactionStateClearsFlagsForNonCosmosChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.hasPendingTransaction = true
        vm.pendingTransactionCountdown = 42
        vm.isCheckingPendingTransactions = true

        vm.refreshPendingTransactionState()

        XCTAssertFalse(vm.hasPendingTransaction, "Non-Cosmos chains must clear hasPendingTransaction")
        XCTAssertEqual(vm.pendingTransactionCountdown, 0)
        XCTAssertFalse(vm.isCheckingPendingTransactions)
    }

    func testRefreshPendingTransactionStateClearsCountdownForChainWithoutPendingTxs() {
        // gaiaChain supports pending transactions, but the manager has none
        // registered for this address -> hasPending should end false.
        let vm = SendFormFixture.make(coin: SendFormFixture.makeATOM())
        vm.pendingTransactionCountdown = 99
        vm.hasPendingTransaction = true

        vm.refreshPendingTransactionState()

        XCTAssertFalse(vm.hasPendingTransaction, "No pending tx in manager -> flag cleared")
        XCTAssertEqual(vm.pendingTransactionCountdown, 0)
        XCTAssertFalse(vm.isCheckingPendingTransactions)
    }

    func testUpdateCountdownTickNoOpsForNonCosmosChain() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.pendingTransactionCountdown = 7
        vm.hasPendingTransaction = true

        vm.updateCountdownTick()

        // Guard at the top of updateCountdownTick short-circuits, so existing
        // state is preserved untouched.
        XCTAssertEqual(vm.pendingTransactionCountdown, 7)
        XCTAssertTrue(vm.hasPendingTransaction)
    }

    func testUpdateCountdownTickClearsStateWhenNoPendingTxInManager() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeATOM())
        vm.pendingTransactionCountdown = 55
        vm.hasPendingTransaction = true

        vm.updateCountdownTick()

        // The mock pending-tx manager has no entries -> clear state.
        XCTAssertFalse(vm.hasPendingTransaction)
        XCTAssertEqual(vm.pendingTransactionCountdown, 0)
    }

    func testTearDownPendingTransactionStateIsIdempotent() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeATOM())
        vm.tearDownPendingTransactionState()
        vm.tearDownPendingTransactionState()
        // Reaching here without crashing is the assertion.
        XCTAssertTrue(true)
    }
}
