//
//  SendCryptoVerifyViewModelTests.swift
//  VultisigAppTests
//
//  Covers `SendCryptoVerifyViewModel`'s state surface (init, form-validity
//  gating, sign-button-disabled gating, `validateBalanceWithFee`,
//  `validateSecurityScanner`) and its async pipeline (`loadGasInfoForSending`,
//  `validateForm`, `scan`).
//
//  Async-method coverage uses `MockSendInteractor` injected via the VM's
//  initializer, including UTXO/Cardano planning now that those side effects
//  live behind the interactor boundary.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendCryptoVerifyViewModelTests: XCTestCase {

    // MARK: - Init

    func testInitWithTransactionSetsTransactionField() throws {
        let tx = try makeTransaction()
        let vm = SendCryptoVerifyViewModel(transaction: tx)
        XCTAssertEqual(vm.transaction.coin, tx.coin)
        XCTAssertEqual(vm.transaction.toAddress, tx.toAddress)
        XCTAssertEqual(vm.transaction.amount, tx.amount)
    }

    func testInitDefaultsForVMState() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        XCTAssertFalse(vm.isCalculatingFee)
        XCTAssertFalse(vm.isAddressCorrect)
        XCTAssertFalse(vm.isAmountCorrect)
        XCTAssertFalse(vm.showAlert)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.errorMessage, "")
        XCTAssertFalse(vm.hasBalanceError)
        XCTAssertEqual(vm.fastVaultPassword, "")
        XCTAssertFalse(vm.showSecurityScannerSheet)
    }

    // MARK: - isValidForm gating

    func testIsValidFormTrueWhenBothChecksAreOn() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertTrue(vm.isValidForm)
    }

    func testIsValidFormFalseWhenAddressUnchecked() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = false
        vm.isAmountCorrect = true
        XCTAssertFalse(vm.isValidForm)
    }

    func testIsValidFormFalseWhenAmountUnchecked() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = false
        XCTAssertFalse(vm.isValidForm)
    }

    // MARK: - signButtonDisabled gating

    func testSignButtonDisabledWhenInvalidForm() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = false
        vm.isAmountCorrect = false
        XCTAssertTrue(vm.signButtonDisabled)
    }

    func testSignButtonDisabledWhenLoading() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        vm.isLoading = true
        XCTAssertTrue(vm.signButtonDisabled)
    }

    func testSignButtonDisabledWhenHasBalanceError() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        vm.hasBalanceError = true
        XCTAssertTrue(vm.signButtonDisabled)
    }

    func testSignButtonEnabledOnHappyPath() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertFalse(vm.signButtonDisabled)
    }

    // MARK: - validateBalanceWithFee

    func testValidateBalanceWithFeeNoErrorWhenAmountPlusFeeFitsNative() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000") // 1 ETH
        let tx = try makeTransaction(coin: eth, amount: "0.5", fee: BigInt(stringLiteral: "10000000000000000"))
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertFalse(vm.hasBalanceError)
        XCTAssertFalse(vm.showAlert)
        XCTAssertEqual(vm.errorMessage, "")
    }

    func testValidateBalanceWithFeeSetsErrorWhenNativeBalanceExceeded() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "100000000000000000") // 0.1 ETH
        let tx = try makeTransaction(coin: eth, amount: "0.5", fee: BigInt(stringLiteral: "10000000000000000"))
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError)
        XCTAssertTrue(vm.showAlert)
        XCTAssertFalse(vm.isAmountCorrect)
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
    }

    func testValidateBalanceWithFeeSetsErrorForSendMaxWhenFeeExceedsBalance() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "5000000000000000") // 0.005 ETH
        var tx = try makeTransaction(coin: eth, amount: "0", fee: BigInt(stringLiteral: "10000000000000000"))
        tx = SendTransaction(
            coin: tx.coin, vault: tx.vault, fromAddress: tx.fromAddress,
            toAddress: tx.toAddress, toAddressLabel: nil,
            amount: tx.amount, amountInFiat: "", memo: "",
            gas: tx.gas, fee: tx.fee, feeMode: .default,
            estimatedGasLimit: nil, customGasLimit: nil, customByteFee: nil,
            sendMaxAmount: true,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: eth
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError)
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
    }

    // MARK: - validateBalanceWithFee — Terra Classic bank denom vs CW20/IBC

    func testValidateBalanceUSTCBankDenomSubtractsFeeFromTokenBalance() throws {
        // USTC is a Terra Classic BANK denom (uusd): it pays gas + burn tax in
        // its OWN denom, so `amount + fee` must fit the token balance. Here the
        // balance covers `amount` but not `amount + fee`, so it must error.
        let ustc = makeCoin(.terraClassic, ticker: "USTC", decimals: 6, isNative: false,
                            rawBalance: "200000000", contractAddress: "uusd")
        let tx = try makeTransaction(coin: ustc, amount: "150", fee: BigInt(60_000_000))
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError,
                      "USTC bank-denom must validate amount + fee against the token balance")
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
    }

    func testValidateBalanceCW20TerraClassicTokenIsNotTaxValidated() throws {
        // A CW20 (terra1…) Terra Classic token pays its fee in native LUNC, NOT
        // in its own denom. The over-broad pre-fix condition wrongly folded the
        // uluna-denominated fee into the token-denom balance check. With a token
        // balance that exactly covers `amount` (but NOT amount + fee) and ample
        // native LUNC for gas, the generic branch must pass.
        let cw20 = makeCoin(.terraClassic, ticker: "ASTRO", decimals: 6, isNative: false,
                            rawBalance: "150000000",
                            contractAddress: "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26")
        let lunc = makeCoin(.terraClassic, ticker: "LUNC", decimals: 6, isNative: true,
                            rawBalance: "1000000000")
        let vault = try TestStore.makeVault()
        vault.coins = [lunc, cw20]
        let tx = SendTransaction(
            coin: cw20, vault: vault, fromAddress: cw20.address,
            toAddress: "terra13lwh075aclv70w784nkjwdefmxx8p3s2f7n5m2", toAddressLabel: nil,
            amount: "150", amountInFiat: "", memo: "",
            gas: .zero, fee: BigInt(60_000_000), feeMode: .default,
            estimatedGasLimit: nil, customGasLimit: nil, customByteFee: nil,
            sendMaxAmount: false, isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: lunc
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertFalse(vm.hasBalanceError,
                       "CW20 Terra Classic token must NOT have its uluna fee subtracted from the token balance")
        XCTAssertEqual(vm.errorMessage, "")
    }

    func testValidateBalanceCW20TerraClassicTokenStillChecksNativeGas() throws {
        // The CW20 branch must still surface insufficient native LUNC for gas —
        // proving it falls through to the generic non-native gas check, not the
        // bank-denom branch.
        let cw20 = makeCoin(.terraClassic, ticker: "ASTRO", decimals: 6, isNative: false,
                            rawBalance: "150000000",
                            contractAddress: "terra1nsuqsk6kh58ulczatwev87ttq2z6r3pusulg9r24mfj2fvtzd4uq3exn26")
        let lunc = makeCoin(.terraClassic, ticker: "LUNC", decimals: 6, isNative: true,
                            rawBalance: "1000") // not enough LUNC for the gas fee
        let vault = try TestStore.makeVault()
        vault.coins = [lunc, cw20]
        let tx = SendTransaction(
            coin: cw20, vault: vault, fromAddress: cw20.address,
            toAddress: "terra13lwh075aclv70w784nkjwdefmxx8p3s2f7n5m2", toAddressLabel: nil,
            amount: "100", amountInFiat: "", memo: "",
            gas: .zero, fee: BigInt(60_000_000), feeMode: .default,
            estimatedGasLimit: nil, customGasLimit: nil, customByteFee: nil,
            sendMaxAmount: false, isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: lunc
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError,
                      "CW20 send must report insufficient native LUNC for gas")
    }

    // MARK: - validateSecurityScanner

    func testValidateSecurityScannerReturnsTrueWhenStateIdle() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        vm.securityScannerState = .idle
        XCTAssertTrue(vm.validateSecurityScanner())
        XCTAssertFalse(vm.showSecurityScannerSheet)
    }

    // MARK: - feeMode pin (regression for #4347 bug fix)

    func testTransactionFeeModePropagatesThroughInit() throws {
        // Confirms the immutable struct carries `feeMode` from construction —
        // pre-#4347 the field existed but Verify refresh hardcoded
        // `feeMode: .default` instead of reading `tx.feeMode`.
        let tx = try makeTransaction(feeMode: .fast)
        let vm = SendCryptoVerifyViewModel(transaction: tx)
        XCTAssertEqual(vm.transaction.feeMode, .fast)
    }

    // MARK: - .with() refresh preserves customGasLimit (regression pin)

    func testRefreshViaWithPreservesCustomGasLimit() throws {
        // The Verify VM updates `transaction` via `with(...)` on refresh. This
        // pin guards the customGasLimit preservation contract — a regression
        // here would re-introduce the bug where user-pinned EVM gas got
        // dropped on the 60s refresh.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let vault = try TestStore.makeVault()
        let originalTx = SendTransaction(
            coin: eth, vault: vault, fromAddress: eth.address,
            toAddress: "0xabc", toAddressLabel: nil,
            amount: "0.5", amountInFiat: "", memo: "",
            gas: BigInt(stringLiteral: "20000000000"),
            fee: BigInt(stringLiteral: "420000000000000"),
            feeMode: .fast,
            estimatedGasLimit: BigInt(21_000),
            customGasLimit: BigInt(50_000),
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: eth
        )
        let vm = SendCryptoVerifyViewModel(transaction: originalTx)

        // Simulate what loadGasInfoForSending does internally on refresh.
        vm.transaction = vm.transaction.with(
            gas: BigInt(stringLiteral: "30000000000"),
            fee: BigInt(stringLiteral: "630000000000000")
        )

        XCTAssertEqual(vm.transaction.customGasLimit, BigInt(50_000), "customGasLimit must survive Verify refresh")
        XCTAssertEqual(vm.transaction.gas, BigInt(stringLiteral: "30000000000"))
        XCTAssertEqual(vm.transaction.gasLimit, BigInt(50_000))
    }

    // MARK: - loadGasInfoForSending (interactor-driven)

    func testLoadGasInfoForwardsFeeModeToInteractorForEVM() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "630000000000000"),
                                    gas: BigInt(stringLiteral: "30000000000"))
        }
        let tx = try makeTransaction(feeMode: .fast)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.calculateEVMFeeCalls.count, 1)
        XCTAssertEqual(interactor.calculateEVMFeeCalls.first?.feeMode, .fast,
                       "tx.feeMode must be threaded to interactor.calculateEVMFee — regression pin for #4347")
        XCTAssertEqual(interactor.calculateEVMFeeCalls.first?.gasLimit, tx.gasLimit,
                       "Verify refresh must price the same gas limit that payload construction will sign.")
        XCTAssertEqual(vm.transaction.gas, BigInt(stringLiteral: "30000000000"))
        XCTAssertEqual(vm.transaction.fee, BigInt(stringLiteral: "630000000000000"))
        XCTAssertFalse(vm.isCalculatingFee)
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadGasInfoUsesFetchChainSpecificForNonEVM() async throws {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Cosmos(accountNumber: 0, sequence: 0,
                    gas: UInt64(7_500),
                    transactionType: 0,
                    ibcDenomTrace: nil)
        }
        let atom = makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6,
                            isNative: true, rawBalance: "10000000")
        let tx = try makeTransaction(coin: atom)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 1)
        XCTAssertTrue(interactor.calculateEVMFeeCalls.isEmpty,
                      "non-EVM chains must not hit the EVM fee path")
        // For Cosmos, calculateNonEVMFee returns chainSpecific.fee — which on a
        // Cosmos shape is the `gas` value (BlockChainSpecific.Cosmos has no
        // separate fee field beyond the gas).
        XCTAssertEqual(vm.transaction.fee, BigInt(7_500))
        XCTAssertEqual(vm.transaction.gas, BigInt(7_500))
    }

    func testLoadGasInfoForwardsCustomGasLimitToEVMFeeCalculation() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "1500000000000000"),
                                    gas: BigInt(stringLiteral: "30000000000"))
        }
        let tx = try makeTransaction(customGasLimit: BigInt(50_000))
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.calculateEVMFeeCalls.first?.gasLimit, BigInt(50_000))
        XCTAssertEqual(vm.transaction.customGasLimit, BigInt(50_000))
    }

    func testLoadGasInfoUsesInteractorPlanFeeForUTXO() async throws {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .UTXO(byteFee: BigInt(50), sendMaxAmount: false)
        }
        interactor.calculatePlanFeeStub = { _, _ in BigInt(1_234) }
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8,
                           isNative: true, rawBalance: "100000000")
        let tx = try makeTransaction(coin: btc, amount: "0.1")
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.calculatePlanFeeCalls.count, 1)
        XCTAssertEqual(vm.transaction.fee, BigInt(1_234))
        XCTAssertEqual(vm.transaction.gas, BigInt(1_234))
    }

    func testLoadGasInfoSetsErrorOnInteractorThrow() async throws {
        struct StubError: Error { }
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in throw StubError() }
        let tx = try makeTransaction()
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertTrue(vm.showAlert)
        XCTAssertFalse(vm.errorMessage.isEmpty)
        XCTAssertFalse(vm.isCalculatingFee, "isCalculatingFee must clear on the error path")
        XCTAssertFalse(vm.isLoading, "isLoading must clear on the error path")
    }

    func testLoadGasInfoUpdatesNativeAndSourceBalancesForERC20() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "100000000000000"),
                                    gas: BigInt(stringLiteral: "20000000000"))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18,
                           isNative: true, rawBalance: "1000000000000000000")
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6,
                            isNative: false, rawBalance: "5000000")
        let vault = try TestStore.makeVault()
        vault.coins = [eth, usdc]
        let tx = SendTransaction(
            coin: usdc, vault: vault, fromAddress: usdc.address,
            toAddress: "0x0000000000000000000000000000000000000001", toAddressLabel: nil,
            amount: "1", amountInFiat: "", memo: "",
            gas: .zero, fee: .zero, feeMode: .default,
            estimatedGasLimit: nil, customGasLimit: nil, customByteFee: nil,
            sendMaxAmount: false, isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: eth
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(interactor.updateBalanceCalls.count, 2,
                       "Both the source coin AND its native gas-payer must refresh balance")
        XCTAssertTrue(interactor.updateBalanceCalls.contains(where: { $0.ticker == "USDC" }))
        XCTAssertTrue(interactor.updateBalanceCalls.contains(where: { $0.ticker == "ETH" }))
    }

    func testLoadGasInfoSendMaxAmountRecalculatesAmountFromBalanceMinusFee() async throws {
        let interactor = MockSendInteractor()
        // Pretend the chain came back with a higher fee than the user expected
        // — sendMax must re-derive `amount` so `balance == amount + fee`.
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "100000000000000000"),  // 0.1 ETH
                                    gas: BigInt(stringLiteral: "5000000000000000000"))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18,
                           isNative: true, rawBalance: "1000000000000000000")  // 1 ETH
        let vault = try TestStore.makeVault()
        vault.coins = [eth]
        let tx = SendTransaction(
            coin: eth, vault: vault, fromAddress: eth.address,
            toAddress: "0x0000000000000000000000000000000000000001", toAddressLabel: nil,
            amount: "1", amountInFiat: "", memo: "",
            gas: .zero, fee: .zero, feeMode: .default,
            estimatedGasLimit: nil, customGasLimit: nil, customByteFee: nil,
            sendMaxAmount: true,  // <-- the path under test
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: eth
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        // 1 ETH - 0.1 ETH = 0.9 ETH
        XCTAssertEqual(vm.transaction.amount, "0.9")
        XCTAssertTrue(vm.transaction.sendMaxAmount, "sendMaxAmount flag must survive refresh")
    }

    func testLoadGasInfoPreservesCustomGasLimitOnRefresh() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "630000000000000"),
                                    gas: BigInt(stringLiteral: "30000000000"))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18,
                           isNative: true, rawBalance: "1000000000000000000")
        let vault = try TestStore.makeVault()
        let tx = SendTransaction(
            coin: eth, vault: vault, fromAddress: eth.address,
            toAddress: "0x0000000000000000000000000000000000000001", toAddressLabel: nil,
            amount: "0.1", amountInFiat: "", memo: "",
            gas: .zero, fee: .zero, feeMode: .default,
            estimatedGasLimit: BigInt(21_000),
            customGasLimit: BigInt(50_000),
            customByteFee: nil,
            sendMaxAmount: false, isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:], wasmContractPayload: nil,
            feeCoin: eth
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.customGasLimit, BigInt(50_000),
                       "customGasLimit must survive Verify refresh — regression pin")
        XCTAssertEqual(vm.transaction.gasLimit, BigInt(50_000))
    }

    // MARK: - validateForm

    func testValidateFormThrowsWhenChecksMissing() async throws {
        let interactor = MockSendInteractor()
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction(), interactor: interactor)
        vm.isAddressCorrect = false
        vm.isAmountCorrect = false

        do {
            _ = try await vm.validateForm()
            XCTFail("validateForm must throw when isValidForm is false")
        } catch let error as HelperError {
            if case .runtimeError(let message) = error {
                XCTAssertEqual(message, "mustAgreeTermsError")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertTrue(interactor.fetchChainSpecificCalls.isEmpty,
                      "validateForm must not hit the interactor when the form gating fails")
        XCTAssertTrue(interactor.buildKeysignPayloadCalls.isEmpty)
    }

    func testValidateFormHappyPathReturnsKeysignPayload() async throws {
        let interactor = MockSendInteractor()
        let cosmosSpec: BlockChainSpecific = .Cosmos(
            accountNumber: 42, sequence: 7, gas: UInt64(7_500),
            transactionType: 0, ibcDenomTrace: nil
        )
        interactor.fetchChainSpecificStub = { _ in cosmosSpec }
        let atom = makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6,
                            isNative: true, rawBalance: "10000000")
        let tx = try makeTransaction(coin: atom)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 1)
        XCTAssertEqual(interactor.buildKeysignPayloadCalls.count, 1)
        XCTAssertEqual(payload.coin.ticker, "ATOM")
        XCTAssertEqual(payload.toAddress, tx.toAddress)
        XCTAssertEqual(payload.toAmount, tx.amountInRaw)
    }

    func testValidateFormForwardsEmptyMemoAsNil() async throws {
        let interactor = MockSendInteractor()
        let atom = makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6,
                            isNative: true, rawBalance: "10000000")
        let tx = try makeTransaction(coin: atom)  // memo: ""
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        _ = try await vm.validateForm()

        XCTAssertEqual(interactor.buildKeysignPayloadCalls.first?.memo, nil,
                       "Empty memo must be normalized to nil at the boundary")
        // And the convenience overload of fetchChainSpecific(tx:) must do the same.
        XCTAssertEqual(interactor.fetchChainSpecificCalls.first?.memo, nil)
    }

    func testValidateFormDelegatesUTXOValidationToInteractor() async throws {
        let interactor = MockSendInteractor()
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8,
                           isNative: true, rawBalance: "100000000")
        let tx = try makeTransaction(coin: btc, amount: "0.1")
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        _ = try await vm.validateForm()

        XCTAssertEqual(interactor.validateUtxosIfNeededCalls.count, 1)
        XCTAssertEqual(interactor.validateUtxosIfNeededCalls.first?.ticker, "BTC")
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0", contractAddress: String? = nil) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        if let contractAddress {
            coin.contractAddress = contractAddress
        }
        return coin
    }

    private func makeTransaction(
        coin: Coin? = nil,
        amount: String = "0.1",
        fee: BigInt = BigInt(stringLiteral: "1000000000000000"),
        feeMode: FeeMode = .default,
        customGasLimit: BigInt? = nil
    ) throws -> SendTransaction {
        let vault = try TestStore.makeVault()
        let coinToUse = coin ?? makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                                         rawBalance: "1000000000000000000")
        return SendTransaction(
            coin: coinToUse,
            vault: vault,
            fromAddress: coinToUse.address,
            toAddress: "0x0000000000000000000000000000000000000001",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "",
            gas: BigInt.zero,
            fee: fee,
            feeMode: feeMode,
            estimatedGasLimit: nil,
            customGasLimit: customGasLimit,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coinToUse
        )
    }
}
