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
        let toAddress = "0x1111111111111111111111111111111111111111"
        let seed = SendDetailsSeed(
            coin: eth,
            vault: vault,
            hasPreselectedCoin: true,
            fromAddress: eth.address,
            toAddress: toAddress,
            toAddressLabel: "vitalik.eth",
            lastResolvedAddress: toAddress,
            amount: "0.25",
            amountInFiat: "500",
            memo: "hello",
            gas: BigInt(30_000_000_000),
            fee: BigInt(1_500_000_000_000_000),
            feeMode: .fast,
            estimatedGasLimit: nil,
            customGasLimit: BigInt(50_000),
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil
        )
        let vm = SendFormFixture.make(coin: eth, vault: vault)
        vm.hydrate(from: seed)

        XCTAssertEqual(vm.toAddress, toAddress)
        XCTAssertEqual(vm.toAddressLabel, "vitalik.eth")
        XCTAssertEqual(vm.lastResolvedAddress, toAddress)
        XCTAssertEqual(vm.amount, "0.25")
        XCTAssertEqual(vm.amountInFiat, "500")
        XCTAssertEqual(vm.memo, "hello")
        XCTAssertEqual(vm.feeMode, .fast)
        XCTAssertEqual(vm.gas, BigInt(30_000_000_000))
        XCTAssertEqual(vm.fee, BigInt(1_500_000_000_000_000))
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
    // `vault.isFastVault` reads the cache populated by
    // `FastVaultEligibilityRefresher`. Returns `false` until the cache is
    // populated — an extra paired-sign round trip in that narrow window is
    // preferable to routing a non-eligible vault into FastVault based on the
    // structural `hasServerSigner` alone.

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

    func testVaultIsFastVaultIsFalseUntilCacheHydrates() {
        // No cache yet (checkedAt == nil). Even with a `server-` signer
        // present, the read returns false — the refresher hasn't confirmed
        // eligibility yet.
        let vault = SendFormFixture.makeVault()
        vault.signers = ["iPhone-test", "server-abc"]
        let vm = SendFormFixture.make(vault: vault)
        XCTAssertFalse(vm.vault.isFastVault)
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

    // MARK: - Invalid-recipient inline error (#4861)
    //
    // The recipient field must be a first-class, chain-general, user-facing
    // gate: a definitive resolution failure shows a clear inline error and
    // keeps Next disabled *with that visible reason*, and a valid replacement
    // clears it. `showAddressAlert` gates the inline message under the field;
    // `errorMessage` carries the localization key the field renders.

    // A real ETH transaction id (0x + 64 hex) — the exact "txid pasted into the
    // recipient field" case from the issue. It is not a 40-hex address, so it
    // can never be a valid recipient.
    private let ethTransactionId =
        "0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b"

    func testMarkInvalidRecipientSurfacesInlineErrorForEthTxid() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = ethTransactionId

        vm.markInvalidRecipient()

        XCTAssertTrue(vm.showAddressAlert, "A definitive invalid recipient must show the inline error.")
        XCTAssertEqual(vm.errorMessage, "invalidRecipientAddressError")
        XCTAssertFalse((vm.errorMessage ?? "").isEmpty, "The inline error must carry a non-empty message.")
    }

    func testMarkInvalidRecipientIgnoresEmptyAddress() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = ""

        vm.markInvalidRecipient()

        XCTAssertFalse(vm.showAddressAlert, "An empty field is not an invalid recipient — no error under a blank input.")
    }

    func testValidateFormFlagsInvalidEthRecipientTxid() async {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH(rawBalance: "1000000000000000000"))
        vm.toAddress = ethTransactionId
        vm.amount = "0.1"

        let isValid = await vm.validateForm()

        XCTAssertFalse(isValid, "A txid recipient must never pass form validation.")
        XCTAssertTrue(vm.showAddressAlert)
        XCTAssertFalse((vm.errorMessage ?? "").isEmpty)
    }

    func testValidateFormFlagsInvalidCosmosRecipient() async {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeATOM())
        vm.toAddress = "cosmos1invalidrecipientvalue"
        vm.amount = "0.1"

        let isValid = await vm.validateForm()

        XCTAssertFalse(isValid)
        XCTAssertTrue(vm.showAddressAlert)
        XCTAssertFalse((vm.errorMessage ?? "").isEmpty)
    }

    func testValidateFormFlagsInvalidUtxoRecipient() async {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeBTC())
        vm.toAddress = "notabitcoinaddress"
        vm.amount = "0.001"

        let isValid = await vm.validateForm()

        XCTAssertFalse(isValid)
        XCTAssertTrue(vm.showAddressAlert)
        XCTAssertFalse((vm.errorMessage ?? "").isEmpty)
    }

    func testValidateFormFlagsInvalidSolanaRecipient() async {
        let sol = SendFormFixture.makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true, rawBalance: "1000000000")
        let vm = SendFormFixture.make(coin: sol)
        vm.toAddress = "not-a-solana-address"
        vm.amount = "0.1"

        let isValid = await vm.validateForm()

        XCTAssertFalse(isValid)
        XCTAssertTrue(vm.showAddressAlert)
        XCTAssertFalse((vm.errorMessage ?? "").isEmpty)
    }

    func testValidateFormFlagsInvalidXrpRecipient() async {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeXRP())
        vm.toAddress = "notarippleaddress"
        vm.amount = "1"

        let isValid = await vm.validateForm()

        XCTAssertFalse(isValid)
        XCTAssertTrue(vm.showAddressAlert)
        XCTAssertFalse((vm.errorMessage ?? "").isEmpty)
    }

    func testValidRecipientReplacementClearsInlineError() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = ethTransactionId
        vm.markInvalidRecipient()
        XCTAssertTrue(vm.showAddressAlert)

        // User replaces the txid with a valid ETH address — the sync format
        // check that fires on every edit must clear the inline error.
        vm.toAddress = "0x1111111111111111111111111111111111111111"

        XCTAssertTrue(vm.isValidAddressFormat(), "A plain valid ETH address must pass the format check.")
        XCTAssertFalse(vm.showAddressAlert, "A valid replacement recipient clears the inline error.")
        XCTAssertNil(vm.errorMessage)
    }

    func testValidRecipientReplacementEnablesForm() async {
        // Passthrough resolver: `AddressService.resolveInput` rejects otherwise-
        // valid addresses in unit tests, so inject an identity resolver to
        // exercise the happy path end-to-end.
        let eth = SendFormFixture.makeETH(rawBalance: "1000000000000000000")
        let vm = SendFormFixture.make(coin: eth, addressResolver: { input, _ in input })
        vm.markInvalidRecipient()          // simulate a prior invalid-recipient state
        vm.toAddress = "0x1111111111111111111111111111111111111111"
        vm.amount = "0.1"
        vm.gas = BigInt(21_000)
        vm.fee = BigInt(21_000)

        let isValid = await vm.validateForm()

        XCTAssertTrue(isValid, "A valid recipient must enable the flow.")
        XCTAssertFalse(vm.showAddressAlert, "The inline error must not survive a valid submission.")
    }

    // MARK: - Regression: name-service recipients must not error prematurely

    func testEnsNameResolvesWithoutInlineError() async {
        let resolved = "0x1111111111111111111111111111111111111111"
        let eth = SendFormFixture.makeETH(rawBalance: "1000000000000000000")
        let vm = SendFormFixture.make(coin: eth, addressResolver: { _, _ in resolved })
        vm.toAddress = "vitalik.eth"
        vm.amount = "0.1"
        vm.gas = BigInt(21_000)
        vm.fee = BigInt(21_000)

        let isValid = await vm.validateForm()

        XCTAssertTrue(isValid, "A resolvable ENS name is a valid recipient.")
        XCTAssertFalse(vm.showAddressAlert, "ENS names must never flash the invalid-recipient error.")
    }

    func testMarkInvalidRecipientIfUnresolvableFlagsEthTxid() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = ethTransactionId

        vm.markInvalidRecipientIfUnresolvable()

        XCTAssertTrue(vm.showAddressAlert, "A paste that can never resolve must flag immediately.")
    }

    func testMarkInvalidRecipientIfUnresolvableSkipsEnsName() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = "vitalik.eth"

        vm.markInvalidRecipientIfUnresolvable()

        XCTAssertFalse(vm.showAddressAlert, "ENS names are left to async resolution, not flagged on paste.")
    }

    func testMarkInvalidRecipientIfUnresolvableSkipsValidAddress() {
        let vm = SendFormFixture.make(coin: SendFormFixture.makeETH())
        vm.toAddress = "0x1111111111111111111111111111111111111111"

        vm.markInvalidRecipientIfUnresolvable()

        XCTAssertFalse(vm.showAddressAlert, "A valid same-chain address must not be flagged on paste.")
    }
}
