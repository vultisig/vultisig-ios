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

    // MARK: - isApproveRequired / approve checkbox gating

    /// A normal send has no pre-built payload ⇒ no bundled approve ⇒ the approve
    /// checkbox never appears and `isValidForm` stays the two-checkbox gate.
    func testIsApproveRequiredFalseForNormalSend() throws {
        let vm = SendCryptoVerifyViewModel(transaction: try makeTransaction())
        XCTAssertFalse(vm.isApproveRequired)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertTrue(vm.isValidForm, "without a bundled approve, two checks must still be enough")
    }

    /// Circle withdraw supplies a pre-built payload whose `approvePayload` is nil
    /// (a withdraw never bundles an approve) ⇒ no approve checkbox, gating unchanged.
    func testIsApproveRequiredFalseWhenPrebuiltPayloadHasNoApprove() throws {
        let vm = SendCryptoVerifyViewModel(
            transaction: try makeTransaction(),
            prebuiltKeysignPayload: makePrebuiltPayload(approvePayload: nil)
        )
        XCTAssertFalse(vm.isApproveRequired)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertTrue(vm.isValidForm, "a Circle-withdraw payload (no approve) must not require the third check")
    }

    /// A first-time allowance-gated deposit bundles a USDC approve ⇒ `isApproveRequired` is
    /// true ⇒ `isValidForm` additionally requires `isApproveCorrect`.
    func testIsApproveRequiredTrueWhenPrebuiltPayloadBundlesApprove() throws {
        let approve = ERC20ApprovePayload(amount: BigInt(100_000_000), spender: "0xVault")
        let vm = SendCryptoVerifyViewModel(
            transaction: try makeTransaction(),
            prebuiltKeysignPayload: makePrebuiltPayload(approvePayload: approve)
        )
        XCTAssertTrue(vm.isApproveRequired)

        vm.isAddressCorrect = true
        vm.isAmountCorrect = true
        XCTAssertFalse(vm.isValidForm, "the bundled approve must gate signing on the third checkbox")

        vm.isApproveCorrect = true
        XCTAssertTrue(vm.isValidForm, "all three checks satisfied ⇒ form valid")
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

    /// Past `Int64` — about 9.223 on an 18-decimal asset — reading the balance
    /// through the shared decimal parser rounds it UP, so `amount + fee` is
    /// weighed against funds the vault does not hold. The send clears Verify
    /// and is rejected at broadcast, after the signing ceremony has already run
    /// and been spent.
    func testValidateBalanceWithFeeReadsABalanceBeyondInt64Exactly() throws {
        // 99.999999999999999999 ETH — the lossy read rounds it to a flat 100.
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "99999999999999999999")
        XCTAssertEqual(eth.balanceRaw, BigInt(stringLiteral: "99999999999999999999"))
        let tx = try makeTransaction(coin: eth, amount: "100", fee: .zero)
        XCTAssertEqual(
            tx.amountInRaw, BigInt(stringLiteral: "100000000000000000000"),
            "the send is one wei more than the vault holds"
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError)
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

    /// The exactness has to survive the FEE term too: it is `amount + fee`, not
    /// the amount alone, that this guard weighs against the balance. A balance
    /// read even one wei high lets a send through that the chain rejects at
    /// broadcast, after the ceremony has run and been spent.
    ///
    /// 9999999999999999999 wei is one wei under 10 ETH, and it is the fee that
    /// takes the send past it: 9.9 ETH would fit on its own.
    func testValidateBalanceWithFeeCountsTheFeeAgainstAnExactBalancePastInt64() throws {
        let oneWeiUnderTenEth = "9999999999999999999"
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: oneWeiUnderTenEth)
        XCTAssertEqual(
            eth.balanceRaw, BigInt(stringLiteral: oneWeiUnderTenEth),
            "precondition: the guard has to be reading every wei of the balance"
        )

        // 9.9 ETH + 0.1 ETH fee = 10 ETH exactly, one wei more than the balance.
        let tx = try makeTransaction(coin: eth, amount: "9.9",
                                     fee: BigInt(stringLiteral: "100000000000000000"))
        // Pin the total rather than trusting it: the amount parse is locale
        // sensitive, and a "9.9" that scaled differently would still raise the
        // error below — for the wrong reason.
        XCTAssertEqual(
            tx.amountInRaw + tx.fee,
            eth.balanceRaw + 1,
            "the send has to land exactly one wei past the balance for this to test anything"
        )
        XCTAssertLessThanOrEqual(
            tx.amountInRaw, eth.balanceRaw,
            "the amount alone must fit, or the fee is not what this is measuring"
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError, "a send one wei past the real balance must not clear Verify")
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

    /// Circle USDC withdraw regression: the display `transaction` carries the USDC
    /// token whose `rawBalance` is the vault EOA (~0), NOT the MSCA balance the amount
    /// was actually validated against upstream. With a pre-built payload present the
    /// standard balance check must be skipped — otherwise a normal withdraw trips
    /// `walletBalanceExceededError`, sets `hasBalanceError`, and disables signing.
    func testValidateBalanceWithFeeSkippedWhenPrebuiltPayloadPresent() throws {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "0") // vault EOA USDC is ~0; real balance lives on the MSCA
        let tx = try makeTransaction(coin: usdc, amount: "5") // 5 USDC > 0 EOA balance
        let nativeEth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                                 rawBalance: "1000000000000000000")
        let prebuilt = KeysignPayload(
            coin: nativeEth,
            toAddress: "0x2222222222222222222222222222222222222222",
            toAmount: BigInt(0),
            chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(1), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(21_000)),
            utxos: [],
            memo: "0xb61d27f6",
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx, prebuiltKeysignPayload: prebuilt)

        vm.validateBalanceWithFee()

        XCTAssertFalse(vm.hasBalanceError, "pre-built payload flow must not trip the EOA balance check")
        XCTAssertFalse(vm.showAlert)
        XCTAssertEqual(vm.errorMessage, "")
    }

    /// Without a pre-built payload, the same insufficient-balance USDC tx must still
    /// flag the error — the skip is strictly opt-in to the pre-built-payload flow.
    func testValidateBalanceWithFeeStillRunsWithoutPrebuiltPayload() throws {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "0")
        let tx = try makeTransaction(coin: usdc, amount: "5")
        let vm = SendCryptoVerifyViewModel(transaction: tx)

        vm.validateBalanceWithFee()

        XCTAssertTrue(vm.hasBalanceError, "regular sends keep the balance check")
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
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
                    ibcDenomTrace: nil, gasLimit: nil)
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

    // MARK: - loadGasInfoForSending — XRP destination-activation guard (load-time)

    func testLoadGasInfoBlocksUnfundedXrpDestinationOnLoad() async throws {
        // 0.1 XRP (100,000 drops) to an unfunded (actNotFound) destination is
        // below the 1 XRP base reserve, so on-chain the Payment fails with
        // tecNO_DST_INSUF_XRP after the fee is burned. The load pass must
        // surface that — error shown, Sign disabled — not defer it to the Sign
        // tap.
        let client = VerifyScriptedHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"error":"actNotFound","error_code":19,"error_message":"Account not found.","status":"error","validated":false}}
        """.utf8))
        client.serverStateResult = .success(Data("""
        {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":1000000,"reserve_inc":200000}}}}
        """.utf8))
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6, isNative: true, rawBalance: "100000000")
        let tx = try makeTransaction(coin: xrp, amount: "0.1")
        let rippleService = RippleService(resolver: NoOverrideResolver(), httpClient: client, sleep: { _ in })
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: MockSendInteractor(), rippleService: rippleService)

        await vm.loadGasInfoForSending()

        XCTAssertTrue(vm.hasBalanceError, "an unfunded sub-reserve XRP destination must be flagged on load")
        XCTAssertTrue(vm.showAlert)
        XCTAssertFalse(vm.errorMessage.isEmpty, "the destination-activation copy must reach the alert")
        XCTAssertTrue(vm.signButtonDisabled, "Sign must be disabled while the destination is invalid")
    }

    func testLoadGasInfoAllowsFundedXrpDestinationOnLoad() async throws {
        // A funded destination (has account_data) accepts any amount — the
        // load-time guard must not block it.
        let client = VerifyScriptedHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"account_data":{"Account":"rFunded","Balance":"20000000","OwnerCount":0,"Sequence":7},"status":"success","validated":true}}
        """.utf8))
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6, isNative: true, rawBalance: "100000000")
        let tx = try makeTransaction(coin: xrp, amount: "0.1")
        let rippleService = RippleService(resolver: NoOverrideResolver(), httpClient: client, sleep: { _ in })
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: MockSendInteractor(), rippleService: rippleService)

        await vm.loadGasInfoForSending()

        XCTAssertFalse(vm.hasBalanceError, "a funded XRP destination must not be blocked on load")
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
            transactionType: 0, ibcDenomTrace: nil, gasLimit: nil
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

    // MARK: - validateForm — native EVM MAX re-fit against the signed fee

    /// The amount on screen came from one fee reading; the payload is built from
    /// a second, independent one. Whatever fee the payload ends up carrying, the
    /// value has to fit under it or the node rejects the send after the ceremony
    /// already ran. Numbers taken from the reported Arbitrum failure.
    func testValidateFormRefitsNativeEvmMaxToTheSignedChainSpecific() async throws {
        let interactor = MockSendInteractor()
        let gasLimit = BigInt(120_000)
        let signedMaxFeePerGas = BigInt(12_024_000) // base fee ticked up between the two fetches
        interactor.fetchChainSpecificStub = { _ in
            .Ethereum(maxFeePerGasWei: signedMaxFeePerGas, priorityFeeWei: .zero, nonce: 3, gasLimit: gasLimit)
        }

        let balanceRaw = BigInt(stringLiteral: "90995688510130159")
        let arb = makeCoin(.arbitrum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)
        let quotedFee = gasLimit * BigInt(12_000_000)
        let tx = try makeTransaction(
            coin: arb,
            amount: SendCryptoLogic.amountString(coin: arb, raw: balanceRaw - quotedFee),
            sendMaxAmount: true
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        let signedFee = gasLimit * signedMaxFeePerGas
        XCTAssertEqual(payload.toAmount, balanceRaw - signedFee)
        XCTAssertEqual(payload.toAmount + signedFee, balanceRaw,
                       "value + gasLimit * maxFeePerGas must land exactly on the balance")
        XCTAssertLessThan(payload.toAmount, tx.amountInRaw, "the clamp must reduce, since the fee grew")
        // The transaction carries the amount as a decimal string, which the
        // Done screen and the history entry read; assert the string is the
        // rendering of the signed value. (Re-parsing it is Double-bounded —
        // see EvmMaxSendClampTests — which is exactly why the clamp itself
        // works in raw units and never round-trips through the string.)
        XCTAssertEqual(vm.transaction.amount, SendCryptoLogic.amountString(coin: arb, raw: payload.toAmount),
                       "the transaction handed on to signing must quote the value that was signed")
    }

    /// A fee that FELL between the two readings leaves room for more than the
    /// screen displayed — signing that would send more than the user approved.
    func testValidateFormNeverRaisesTheMaxWhenTheSignedFeeFell() async throws {
        let interactor = MockSendInteractor()
        let gasLimit = BigInt(120_000)
        interactor.fetchChainSpecificStub = { _ in
            .Ethereum(maxFeePerGasWei: BigInt(6_000_000), priorityFeeWei: .zero, nonce: 1, gasLimit: gasLimit)
        }

        let balanceRaw = BigInt(stringLiteral: "1000000000000000000")
        let arb = makeCoin(.arbitrum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)
        let quotedFee = gasLimit * BigInt(12_000_000)
        let displayed = balanceRaw - quotedFee
        let tx = try makeTransaction(
            coin: arb,
            amount: SendCryptoLogic.amountString(coin: arb, raw: displayed),
            sendMaxAmount: true
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        XCTAssertEqual(payload.toAmount, tx.amountInRaw)
        XCTAssertGreaterThan(balanceRaw - gasLimit * BigInt(6_000_000), payload.toAmount,
                             "the cheaper signed fee left room the clamp must not take")
        XCTAssertEqual(vm.transaction.amount, tx.amount, "an unchanged amount must not republish the transaction")
    }

    func testValidateFormReservesTheOpStackFeesOnTopOfGas() async throws {
        let interactor = MockSendInteractor()
        let gasLimit = BigInt(40_000)
        let maxFeePerGas = BigInt(1_200_020)
        let l1Reserve = BigInt(4_293_564_911)
        interactor.fetchChainSpecificStub = { _ in
            .Ethereum(maxFeePerGasWei: maxFeePerGas, priorityFeeWei: BigInt(20), nonce: 0, gasLimit: gasLimit)
        }
        interactor.opStackFeeReserveStub = { _, _, _ in l1Reserve }

        let balanceRaw = BigInt(stringLiteral: "12437685400489921")
        let opEth = makeCoin(.optimism, ticker: "ETH", decimals: 18, isNative: true,
                             rawBalance: balanceRaw.description)
        let tx = try makeTransaction(
            coin: opEth,
            amount: SendCryptoLogic.amountString(coin: opEth, raw: balanceRaw - gasLimit * maxFeePerGas),
            sendMaxAmount: true
        )
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        XCTAssertEqual(payload.toAmount, balanceRaw - gasLimit * maxFeePerGas - l1Reserve)
        XCTAssertEqual(interactor.opStackFeeReserveCalls.count, 1)
        XCTAssertEqual(interactor.opStackFeeReserveCalls.first?.coin.chain, .optimism)
        XCTAssertEqual(interactor.opStackFeeReserveCalls.first?.gasLimit, gasLimit,
                       "the operator fee is priced off the gas limit the payload actually carries")
    }

    func testValidateFormThrowsWhenTheSignedFeeLeavesNothingToSend() async throws {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            // A fee that swallows the whole balance.
            .Ethereum(maxFeePerGasWei: BigInt(stringLiteral: "1000000000000"), priorityFeeWei: .zero,
                      nonce: 0, gasLimit: BigInt(120_000))
        }
        let arb = makeCoin(.arbitrum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "1000000000")
        let tx = try makeTransaction(coin: arb, amount: "0.0000000005", sendMaxAmount: true)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        do {
            _ = try await vm.validateForm()
            XCTFail("a send the balance cannot fund must not reach the ceremony")
        } catch let error as HelperError {
            guard case .runtimeError(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "walletBalanceExceededError")
        }

        XCTAssertTrue(interactor.buildKeysignPayloadCalls.isEmpty, "nothing must be built from an unaffordable amount")
    }

    func testValidateFormLeavesATypedEvmAmountUntouched() async throws {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Ethereum(maxFeePerGasWei: BigInt(50_000_000_000), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(23_000))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        let tx = try makeTransaction(coin: eth, amount: "0.1") // sendMaxAmount: false
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        XCTAssertEqual(payload.toAmount, tx.amountInRaw, "a typed amount is the user's number and must never be rewritten")
        XCTAssertTrue(interactor.opStackFeeReserveCalls.isEmpty)
    }

    func testValidateFormLeavesATokenMaxUntouched() async throws {
        // An ERC-20 max moves the whole token balance; gas comes out of the
        // native sibling, so nothing about the fee can shrink the amount.
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Ethereum(maxFeePerGasWei: BigInt(50_000_000_000), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(120_000))
        }
        interactor.opStackFeeReserveStub = { _, _, _ in BigInt(4_293_564_911) }
        let usdc = makeCoin(.optimism, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "200000000")
        let tx = try makeTransaction(coin: usdc, amount: "200", sendMaxAmount: true)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        XCTAssertEqual(payload.toAmount, tx.amountInRaw)
        XCTAssertTrue(interactor.opStackFeeReserveCalls.isEmpty, "a token send has no L1 headroom to leave in its own amount")
    }

    func testValidateFormLeavesANonEvmMaxUntouched() async throws {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Cosmos(accountNumber: 1, sequence: 1, gas: UInt64(200_000),
                    transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
        }
        let atom = makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6, isNative: true, rawBalance: "10000000")
        let tx = try makeTransaction(coin: atom, amount: "9.8", sendMaxAmount: true)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        XCTAssertEqual(payload.toAmount, tx.amountInRaw, "only EVM re-derives its MAX from the payload's own fee")
    }

    // MARK: - loadGasInfoForSending — L1 headroom in the displayed max

    func testLoadGasInfoLeavesOpStackL1HeadroomInTheDisplayedMax() async throws {
        let interactor = MockSendInteractor()
        let quotedFee = BigInt(stringLiteral: "48000800000")
        let l1Reserve = BigInt(4_293_564_911)
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: quotedFee, gas: BigInt(1_200_020), gasLimit: BigInt(40_000))
        }
        interactor.opStackFeeReserveStub = { _, _, _ in l1Reserve }

        let balanceRaw = BigInt(stringLiteral: "12437685400489921")
        let opEth = makeCoin(.optimism, ticker: "ETH", decimals: 18, isNative: true,
                             rawBalance: balanceRaw.description)
        let tx = try makeTransaction(coin: opEth, amount: "0.01", sendMaxAmount: true)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount,
                       SendCryptoLogic.amountString(coin: opEth, raw: balanceRaw - quotedFee - l1Reserve),
                       "the amount on screen must already carry the L1 headroom it will be signed with")
    }

    func testLoadGasInfoKeepsBalanceMinusFeeWhereThereIsNoL1DataFee() async throws {
        // Mirror hazard: the L1 reserve must not shave anything off an L1 max.
        let interactor = MockSendInteractor()
        let quotedFee = BigInt(stringLiteral: "1150000000000000")
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: quotedFee, gas: BigInt(50_000_000_000), gasLimit: BigInt(23_000))
        }

        let balanceRaw = BigInt(stringLiteral: "1000000000000000000")
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)
        let tx = try makeTransaction(coin: eth, amount: "0.9", sendMaxAmount: true)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount,
                       SendCryptoLogic.amountString(coin: eth, raw: balanceRaw - quotedFee))
    }

    /// The reserves sit on top of the fee, so a balance can clear
    /// `validateBalanceWithFee`'s fee-only check and still have nothing left to
    /// send. Without this the stale amount stayed on screen with Sign enabled
    /// and the send only failed when the payload build refused it.
    func testLoadGasInfoFlagsABalanceErrorWhenNothingSurvivesTheFee() async throws {
        let interactor = MockSendInteractor()
        let balanceRaw = BigInt(stringLiteral: "48000800000")
        interactor.calculateEVMFeeStub = { _ in
            // Fee alone fits under the balance; the L1 reserve is what tips it.
            SendInteractorFeeResult(fee: balanceRaw - 1_000, gas: BigInt(1_200_020), gasLimit: BigInt(40_000))
        }
        interactor.opStackFeeReserveStub = { _, _, _ in BigInt(4_293_564_911) }

        let opEth = makeCoin(.optimism, ticker: "ETH", decimals: 18, isNative: true,
                             rawBalance: balanceRaw.description)
        let tx = try makeTransaction(coin: opEth, amount: "0.000000048", sendMaxAmount: true)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertTrue(vm.hasBalanceError, "a max send with nothing left after the fee must be flagged on load")
        XCTAssertTrue(vm.showAlert)
        XCTAssertFalse(vm.isAmountCorrect)
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
        XCTAssertTrue(vm.signButtonDisabled)
    }

    // MARK: - validateForm — pre-built keysign payload pass-through

    /// Circle USDC withdraw signs a native-ETH MSCA `execute(USDC, 0, transfer(vault, amount))`
    /// call whose calldata lives in `memo`, while the `transaction` carries the USDC token
    /// purely so the verify summary shows the real amount + recipient. When a pre-built
    /// payload is supplied, `validateForm()` must return it verbatim and must NOT re-derive
    /// from the USDC `transaction` — re-deriving would route the USDC ERC-20 coin through the
    /// transfer path and sign `transfer(MSCA, 0)`, the #4484 no-op.
    func testValidateFormReturnsPrebuiltPayloadVerbatimWithoutRederiving() async throws {
        let interactor = MockSendInteractor()

        // The signed payload: native ETH, MSCA target, value 0, execute() calldata in memo.
        let mscaAddress = "0x2222222222222222222222222222222222222222"
        let executeMemo = "0xb61d27f6deadbeef"
        let nativeEth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                                 rawBalance: "1000000000000000000")
        let prebuilt = KeysignPayload(
            coin: nativeEth,
            toAddress: mscaAddress,
            toAmount: BigInt(0),
            chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(1), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(21_000)),
            utxos: [],
            memo: executeMemo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )

        // The display `transaction` carries the USDC token — the no-op trap if re-derived.
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "1000000")
        let tx = try makeTransaction(coin: usdc, amount: "1")
        let vm = SendCryptoVerifyViewModel(
            transaction: tx,
            interactor: interactor,
            prebuiltKeysignPayload: prebuilt
        )
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        let payload = try await vm.validateForm()

        // Returned verbatim — the #4489 native-ETH execute() payload, unchanged.
        XCTAssertEqual(payload, prebuilt)
        XCTAssertTrue(payload.coin.isNativeToken, "signed coin must stay native ETH, not USDC")
        XCTAssertEqual(payload.coin.ticker, "ETH")
        XCTAssertEqual(payload.toAddress, mscaAddress)
        XCTAssertEqual(payload.toAmount, BigInt(0))
        XCTAssertEqual(payload.memo, executeMemo, "execute() calldata must survive in memo")

        // No re-derivation: the USDC transaction must never reach the payload builder.
        XCTAssertTrue(interactor.buildKeysignPayloadCalls.isEmpty,
                      "pre-built payload must bypass buildKeysignPayload — no USDC transfer(MSCA, 0)")
        XCTAssertTrue(interactor.fetchChainSpecificCalls.isEmpty)
        XCTAssertTrue(interactor.validateUtxosIfNeededCalls.isEmpty)
    }

    /// The confirmation checkboxes still gate signing even with a pre-built payload — the
    /// withdraw must not bypass the verify confirmation it was re-routed through to restore.
    func testValidateFormWithPrebuiltPayloadStillEnforcesCheckboxes() async throws {
        let interactor = MockSendInteractor()
        let nativeEth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                                 rawBalance: "1000000000000000000")
        let prebuilt = try await interactor.buildKeysignPayload(
            coin: nativeEth,
            toAddress: "0x2222222222222222222222222222222222222222",
            amount: BigInt(0),
            memo: "0xb61d27f6",
            chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(1), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(21_000)),
            wasmExecuteContractPayload: nil,
            vault: try TestStore.makeVault()
        )
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: "1000000")
        let vm = SendCryptoVerifyViewModel(
            transaction: try makeTransaction(coin: usdc, amount: "1"),
            interactor: interactor,
            prebuiltKeysignPayload: prebuilt
        )
        vm.isAddressCorrect = false
        vm.isAmountCorrect = false

        do {
            _ = try await vm.validateForm()
            XCTFail("validateForm must throw when the confirmation checkboxes are unchecked")
        } catch let error as HelperError {
            guard case .runtimeError(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "mustAgreeTermsError")
        }
    }

    // MARK: - hasFeeOnlyShortfall / feeShortfallAdjustedAmountRaw

    /// The whole feature turns on this distinction. `amount ≤ balance` and
    /// `amount + fee > balance` is a send the fee broke — recoverable by
    /// clamping. Anything else is not.
    func testFeeOnlyShortfallIsTheGapBetweenTheAmountAndTheAmountPlusFee() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000") // 1 ETH
        let fee = BigInt(stringLiteral: "10000000000000000") // 0.01 ETH

        // The whole balance, which the fee then overruns.
        XCTAssertTrue(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: try makeTransaction(coin: eth, amount: "1", fee: fee)
        ))
        // Comfortably affordable — nothing to rescue.
        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: try makeTransaction(coin: eth, amount: "0.5", fee: fee)
        ))
        // Exactly affordable: `amount + fee == balance` is not a shortfall.
        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: try makeTransaction(coin: eth, amount: "0.99", fee: fee)
        ))
    }

    /// The line the issue draws, and the one that keeps this from quietly
    /// replacing the user's send with a different one: if the amount ALONE is
    /// more than the wallet holds, the fee is not what went wrong.
    func testFeeOnlyShortfallExcludesAnAmountThatExceedsTheBalanceByItself() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        let tx = try makeTransaction(coin: eth, amount: "2",
                                     fee: BigInt(stringLiteral: "10000000000000000"))

        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(tx: tx))
        XCTAssertNil(SendCryptoVerifyLogic.feeShortfallAdjustedAmountRaw(tx: tx, extraReserve: .zero))
    }

    func testFeeOnlyShortfallExcludesTokenAndMaxSends() throws {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "1000000", contractAddress: "0xA0b8")
        XCTAssertFalse(
            SendCryptoVerifyLogic.hasFeeOnlyShortfall(
                tx: try makeTransaction(coin: usdc, amount: "1", fee: BigInt(500_000))
            ),
            "a token pays gas from the native sibling — its own balance is not what the fee overruns"
        )

        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        XCTAssertFalse(
            SendCryptoVerifyLogic.hasFeeOnlyShortfall(
                tx: try makeTransaction(coin: eth, amount: "1",
                                        fee: BigInt(stringLiteral: "10000000000000000"),
                                        sendMaxAmount: true)
            ),
            "a MAX amount is already re-derived from the fee upstream"
        )
    }

    /// A stake / bond / TrustSet / function-call amount is not "how much to
    /// move", so reducing it would change the operation rather than fund it.
    func testFeeOnlyShortfallExcludesOperationsWhoseAmountIsNotATransferValue() throws {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        let fee = BigInt(stringLiteral: "10000000000000000")
        let plain = try makeTransaction(coin: eth, amount: "1", fee: fee)
        XCTAssertTrue(SendCryptoVerifyLogic.hasFeeOnlyShortfall(tx: plain),
                      "precondition: the same numbers ARE a shortfall for a plain send")

        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: plain.copy(isStakingOperation: true)
        ))
        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: plain.copy(transactionType: .rippleTrustSet)
        ))
        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: plain.copy(memoFunctionDictionary: ["function": "bond"])
        ))
        // On EVM the memo IS the transaction's calldata, so the amount is a
        // contract call's `msg.value`, not a transfer — reducing it would
        // underfund the call the user is making. Elsewhere a memo is what tells
        // a protocol how to read the deposit. Either way it is not ours to trim.
        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: plain.copy(memo: "0xa9059cbb")
        ))
        XCTAssertFalse(SendCryptoVerifyLogic.hasFeeOnlyShortfall(
            tx: plain.copy(wasmContractPayload: .set(
                WasmExecuteContractPayload(
                    senderAddress: "sender",
                    contractAddress: "contract",
                    executeMsg: "{}",
                    coins: []
                )
            ))
        ))
    }

    /// A balance the fee swallows whole has nothing to clamp to. Returning a
    /// zero or negative "adjusted" amount would turn a blocked send into a
    /// zero-value one; the balance error is the right answer.
    func testFeeShortfallAdjustmentRefusesToClampToZeroOrBelow() throws {
        let balanceRaw = BigInt(stringLiteral: "1000000000000000000")
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)

        // Fee exactly equals the balance ⇒ candidate is 0.
        let exactlyZero = try makeTransaction(coin: eth, amount: "0.5", fee: balanceRaw)
        XCTAssertTrue(SendCryptoVerifyLogic.hasFeeOnlyShortfall(tx: exactlyZero))
        XCTAssertNil(SendCryptoVerifyLogic.feeShortfallAdjustedAmountRaw(tx: exactlyZero, extraReserve: .zero))

        // Fee over the balance ⇒ candidate is negative.
        let negative = try makeTransaction(coin: eth, amount: "0.5", fee: balanceRaw + 1)
        XCTAssertNil(SendCryptoVerifyLogic.feeShortfallAdjustedAmountRaw(tx: negative, extraReserve: .zero))

        // And an `extraReserve` big enough to swallow the remainder does too.
        let squeezed = try makeTransaction(coin: eth, amount: "1",
                                           fee: BigInt(stringLiteral: "10000000000000000"))
        XCTAssertNil(SendCryptoVerifyLogic.feeShortfallAdjustedAmountRaw(
            tx: squeezed,
            extraReserve: balanceRaw
        ))
    }

    /// The clamp is the MAX path's, not a second copy of the arithmetic — so it
    /// reads the balance exactly, and subtracts the reserves the chain bills on
    /// top of the quoted fee.
    func testFeeShortfallAdjustmentReservesWhatTheChainBillsOnTopOfTheFee() throws {
        let balanceRaw = BigInt(stringLiteral: "1000000000000000000")
        let opEth = makeCoin(.optimism, ticker: "ETH", decimals: 18, isNative: true,
                             rawBalance: balanceRaw.description)
        let fee = BigInt(stringLiteral: "10000000000000000")
        let reserve = BigInt(4_293_564_911)
        let tx = try makeTransaction(coin: opEth, amount: "1", fee: fee)

        XCTAssertEqual(
            SendCryptoVerifyLogic.feeShortfallAdjustedAmountRaw(tx: tx, extraReserve: reserve),
            balanceRaw - fee - reserve,
            "op-geth checks value + gas + l1Cost + operatorCost, so the clamp has to leave room for all of it"
        )
    }

    /// The existential deposit is reserved on top of the fee, so a clamped DOT
    /// send lands at `balance − fee − ED` and clears `canBeReaped` — where a
    /// naive `balance − fee` would leave the sender at zero and be refused
    /// on-chain by `transfer_keep_alive` after the ceremony.
    func testFeeShortfallAdjustmentReservesTheExistentialDepositOnDot() throws {
        let balanceRaw = BigInt(10_000_000_000) // 1 DOT, 10 decimals
        let dot = makeCoin(.polkadot, ticker: "DOT", decimals: 10, isNative: true,
                           rawBalance: balanceRaw.description)
        let fee = BigInt(150_000_000)
        let tx = try makeTransaction(coin: dot, amount: "1", fee: fee)

        let adjusted = SendCryptoVerifyLogic.feeShortfallAdjustedAmountRaw(tx: tx, extraReserve: .zero)
        XCTAssertEqual(adjusted, balanceRaw - fee - PolkadotHelper.defaultExistentialDeposit)
        XCTAssertLessThan(adjusted ?? .zero, balanceRaw - fee, "the ED must be reserved, not spent")

        let clamped = SendCryptoLogic.amountString(coin: dot, raw: adjusted ?? .zero)
        XCTAssertFalse(SendCryptoLogic.canBeReaped(coin: dot, amount: clamped, gas: fee),
                       "the clamped value must survive the guard it will be re-checked against")
    }

    // MARK: - loadGasInfoForSending — auto-adjust instead of the balance dead-end

    /// The dead end this replaces: a send the balance covers, that the
    /// re-fetched fee then pushes over. Instead of an error the user can only
    /// answer by retyping a number they cannot compute, Verify clamps the amount
    /// to what the balance funds and shows it.
    func testLoadGasInfoAdjustsTheAmountWhenOnlyTheFeeOvershootsTheBalance() async throws {
        let interactor = MockSendInteractor()
        let balanceRaw = BigInt(stringLiteral: "1000000000000000000") // 1 ETH
        let fee = BigInt(stringLiteral: "12345000000000000")
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: fee, gas: BigInt(30_000_000_000), gasLimit: BigInt(21_000))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)
        // The user typed the whole balance — the Details screen lets this
        // through, because on EVM it checks the amount against the gas PRICE.
        let tx = try makeTransaction(coin: eth, amount: "1", fee: .zero)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount,
                       SendCryptoLogic.amountString(coin: eth, raw: balanceRaw - fee),
                       "the amount on screen must be what the balance can fund")
        XCTAssertTrue(vm.transaction.amountWasAutoAdjusted)
        XCTAssertFalse(vm.hasBalanceError, "the whole point is that this no longer dead-ends")
        XCTAssertFalse(vm.showAlert)
        XCTAssertEqual(vm.errorMessage, "")
        // Rendering raw units to a decimal string and parsing them back is not
        // lossless (`toDecimal` is Double-bounded past ~17 significant digits),
        // and what gets signed is the string's value — so the property that has
        // to hold is about the re-parse, not the BigInt the clamp produced.
        // Re-running the balance check after the adjust is what enforces it.
        XCTAssertLessThanOrEqual(vm.transaction.amountInRaw + fee, balanceRaw,
                                 "the value the displayed string parses back to has to be affordable")
    }

    /// Only the fee-caused shortfall is rescued. Asking to send more than the
    /// wallet holds still stops, because clamping there would swap the user's
    /// send for one they never asked for.
    func testLoadGasInfoKeepsTheErrorWhenTheAmountAloneExceedsTheBalance() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "12345000000000000"),
                                    gas: BigInt(30_000_000_000), gasLimit: BigInt(21_000))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        let tx = try makeTransaction(coin: eth, amount: "2", fee: .zero)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount, "2", "an unaffordable amount must not be rewritten")
        XCTAssertFalse(vm.transaction.amountWasAutoAdjusted)
        XCTAssertTrue(vm.hasBalanceError)
        XCTAssertEqual(vm.errorMessage, "walletBalanceExceededError")
        XCTAssertTrue(vm.signButtonDisabled)
    }

    /// A balance that cannot fund its own fee has nothing to clamp to. It must
    /// keep the error rather than become a zero-value send.
    func testLoadGasInfoKeepsTheErrorWhenTheFeeSwallowsTheWholeBalance() async throws {
        let interactor = MockSendInteractor()
        let balanceRaw = BigInt(stringLiteral: "1000000000000000000")
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: balanceRaw, gas: BigInt(30_000_000_000), gasLimit: BigInt(21_000))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)
        let tx = try makeTransaction(coin: eth, amount: "0.5", fee: .zero)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount, "0.5")
        XCTAssertFalse(vm.transaction.amountWasAutoAdjusted)
        XCTAssertTrue(vm.hasBalanceError)
        XCTAssertTrue(vm.signButtonDisabled)
    }

    /// The clamped value has to re-enter the guards that run after the balance
    /// check, not skip them. Cardano's protocol floor is the sharpest case: 1.6
    /// ADA clears it, and the 1.3 ADA the clamp produces does not — the node
    /// would silently drop that output.
    func testLoadGasInfoSurfacesTheMinimumSendFloorAgainstTheClampedAmount() async throws {
        let interactor = MockSendInteractor()
        interactor.fetchChainSpecificStub = { _ in
            .Cardano(byteFee: BigInt(300_000), sendMaxAmount: false, ttl: 0)
        }
        interactor.calculatePlanFeeStub = { _, _ in BigInt(300_000) } // 0.3 ADA
        let ada = makeCoin(.cardano, ticker: "ADA", decimals: 6, isNative: true,
                           rawBalance: "1600000") // 1.6 ADA
        let tx = try makeTransaction(coin: ada, amount: "1.6", fee: .zero)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount, SendCryptoLogic.amountString(coin: ada, raw: BigInt(1_300_000)),
                       "precondition: the clamp ran and landed below the 1.4 ADA floor")
        XCTAssertTrue(vm.hasBalanceError, "the min-send floor must be re-checked against the clamped value")
        XCTAssertNotEqual(vm.errorMessage, "walletBalanceExceededError",
                          "the failure is the protocol floor, not the balance")
        XCTAssertTrue(vm.signButtonDisabled)
    }

    /// The screen asks the user to tick "the amount is correct". A retry that
    /// re-prices an already-confirmed screen — or a first load racing the
    /// checkbox — must not carry that tick over onto a number the app changed
    /// underneath it: it authorized the old amount.
    func testLoadGasInfoClearsTheAmountConfirmationWhenItRewritesTheAmount() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "12345000000000000"),
                                    gas: BigInt(30_000_000_000), gasLimit: BigInt(21_000))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        let tx = try makeTransaction(coin: eth, amount: "1", fee: .zero)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true
        vm.isAmountCorrect = true

        await vm.loadGasInfoForSending()

        XCTAssertTrue(vm.transaction.amountWasAutoAdjusted, "precondition: the amount was rewritten")
        XCTAssertFalse(vm.isAmountCorrect, "a standing confirmation must not survive the rewrite")
        XCTAssertTrue(vm.signButtonDisabled, "so Sign has to wait for the user to re-confirm")
    }

    /// A send that is only over the balance because of its memo-bearing intent
    /// keeps the error: the amount there is a contract call's value or a
    /// protocol deposit, not a transfer the app may trim.
    func testLoadGasInfoDoesNotAdjustAMemoBearingSend() async throws {
        let interactor = MockSendInteractor()
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "12345000000000000"),
                                    gas: BigInt(30_000_000_000), gasLimit: BigInt(21_000))
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: "1000000000000000000")
        let tx = try makeTransaction(coin: eth, amount: "1", fee: .zero).copy(memo: "0xa9059cbb")
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)

        await vm.loadGasInfoForSending()

        XCTAssertEqual(vm.transaction.amount, "1", "a contract call's value is not ours to reduce")
        XCTAssertFalse(vm.transaction.amountWasAutoAdjusted)
        XCTAssertTrue(vm.hasBalanceError)
    }

    // MARK: - loadGasInfoForSending — an adjusted amount is the amount that gets signed

    /// The hard requirement behind auto-adjusting silently: whatever the screen
    /// shows — crypto AND fiat — is what the keysign payload carries. Pinned end
    /// to end, from the load that rewrites the amount through to the built
    /// payload.
    func testAnAdjustedAmountIsExactlyWhatGetsSigned() async throws {
        let interactor = MockSendInteractor()
        let balanceRaw = BigInt(stringLiteral: "1000000000000000000")
        let fee = BigInt(stringLiteral: "12345000000000000")
        let gasLimit = BigInt(21_000)
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: fee, gas: BigInt(30_000_000_000), gasLimit: gasLimit)
        }
        // The payload's own fee reading agrees with the quote, so nothing is
        // re-fitted here and the displayed value is signed verbatim.
        interactor.fetchChainSpecificStub = { _ in
            .Ethereum(maxFeePerGasWei: fee / gasLimit, priorityFeeWei: .zero, nonce: 0, gasLimit: gasLimit)
        }
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)
        setPrice(2_500, for: eth)

        let tx = try makeTransaction(coin: eth, amount: "1", fee: .zero)
        let typedFiat = vmFiat(coin: eth, amount: "1")
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true

        await vm.loadGasInfoForSending()

        // The user reads the adjusted figures and ticks "the amount is correct".
        vm.isAmountCorrect = true

        // What the screen shows.
        let shownAmount = vm.transaction.amount
        let shownFiat = vm.amountFiat
        XCTAssertNotEqual(shownAmount, "1", "precondition: the amount really was adjusted")
        XCTAssertNotEqual(shownFiat, typedFiat, "the fiat must move with the amount, not stay on the typed one")
        XCTAssertEqual(shownFiat, vmFiat(coin: eth, amount: shownAmount))
        XCTAssertEqual(vm.transaction.amountInFiat,
                       SendCryptoLogic.coinAmountToFiat(amount: shownAmount, coin: eth),
                       "the Done screen reads the stored fiat — it has to follow too")

        // What gets signed.
        let payload = try await vm.validateForm()

        XCTAssertEqual(payload.toAmount, SendCryptoLogic.amountInRaw(coin: eth, amount: shownAmount),
                       "the signed value must be the value of the string on screen")
        XCTAssertEqual(vm.transaction.amount, shownAmount, "and the screen must not have moved under it")
        XCTAssertEqual(vm.amountFiat, shownFiat)
        XCTAssertLessThanOrEqual(payload.toAmount + fee, balanceRaw,
                                 "the signed send has to be affordable — that is the whole point")
    }

    /// An adjusted amount sits at `balance − fee` exactly like a MAX, so it
    /// inherits the MAX path's exposure to a fee that moves between the Verify
    /// quote and the payload build — and must inherit its re-fit too, including
    /// republishing the screen so the user still sees what is signed.
    func testAnAdjustedAmountIsRefittedWhenTheSignedFeeGrew() async throws {
        let interactor = MockSendInteractor()
        let balanceRaw = BigInt(stringLiteral: "1000000000000000000")
        let quotedFee = BigInt(stringLiteral: "12345000000000000")
        let gasLimit = BigInt(21_000)
        let signedMaxFeePerGas = BigInt(stringLiteral: "1000000000000") // fee market moved up
        interactor.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: quotedFee, gas: BigInt(30_000_000_000), gasLimit: gasLimit)
        }
        interactor.fetchChainSpecificStub = { _ in
            .Ethereum(maxFeePerGasWei: signedMaxFeePerGas, priorityFeeWei: .zero, nonce: 0, gasLimit: gasLimit)
        }
        let arb = makeCoin(.arbitrum, ticker: "ETH", decimals: 18, isNative: true,
                           rawBalance: balanceRaw.description)
        let tx = try makeTransaction(coin: arb, amount: "1", fee: .zero)
        let vm = SendCryptoVerifyViewModel(transaction: tx, interactor: interactor)
        vm.isAddressCorrect = true

        await vm.loadGasInfoForSending()
        vm.isAmountCorrect = true
        XCTAssertEqual(vm.transaction.amount,
                       SendCryptoLogic.amountString(coin: arb, raw: balanceRaw - quotedFee),
                       "precondition: the screen was adjusted against the quoted fee")
        let quotedAmount = vm.transaction.amountInRaw

        let payload = try await vm.validateForm()

        let signedFee = gasLimit * signedMaxFeePerGas
        XCTAssertEqual(payload.toAmount, balanceRaw - signedFee)
        XCTAssertLessThan(payload.toAmount, quotedAmount, "the fee grew, so the signed value must shrink")
        XCTAssertEqual(vm.transaction.amount, SendCryptoLogic.amountString(coin: arb, raw: payload.toAmount),
                       "the screen must be republished at the value that was signed")
    }

    // MARK: - needsEVMBalanceRefit

    /// An amount Verify clamped down to what the balance could fund settles at
    /// `balance − fee`, exactly like a MAX — so it carries the same exposure to
    /// a fee that moves before the payload is built, and needs the same re-fit.
    func testBalanceRefitCoversAnAmountTheAppAdjusted() throws {
        let tx = try makeTransaction(amountWasAutoAdjusted: true)
        XCTAssertFalse(tx.sendMaxAmount, "the point of this case is that it is NOT a max send")
        XCTAssertTrue(SendCryptoVerifyLogic.needsEVMBalanceRefit(tx: tx))
    }

    func testBalanceRefitStillCoversANativeEvmMax() throws {
        let tx = try makeTransaction(sendMaxAmount: true)
        XCTAssertTrue(SendCryptoVerifyLogic.needsEVMBalanceRefit(tx: tx))
    }

    /// The invariant this predicate protects: a number the user typed and the
    /// app never touched is never rewritten, however close to the balance it is.
    func testBalanceRefitSkipsATypedAmountTheAppNeverTouched() throws {
        let tx = try makeTransaction()
        XCTAssertFalse(SendCryptoVerifyLogic.needsEVMBalanceRefit(tx: tx))
    }

    /// A token send moves the token balance and pays gas from the native
    /// sibling, so a native fee that moved cannot underfund it.
    func testBalanceRefitSkipsATokenSend() throws {
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false,
                            rawBalance: "1000000", contractAddress: "0xA0b8")
        let tx = try makeTransaction(coin: usdc, amountWasAutoAdjusted: true)
        XCTAssertFalse(SendCryptoVerifyLogic.needsEVMBalanceRefit(tx: tx))
    }

    /// The payload-time re-fit is deliberately EVM-only. Other chains do
    /// re-resolve their fee at build time, but they fail closed on it — a UTXO
    /// plan that no longer covers amount + fee throws before the ceremony —
    /// where an EVM node accepts the signature and refuses the broadcast after
    /// it. Widening the re-fit is a separate decision, not a side effect of this
    /// predicate.
    func testBalanceRefitSkipsANonEvmChain() throws {
        let dot = makeCoin(.polkadot, ticker: "DOT", decimals: 10, isNative: true,
                           rawBalance: "100000000000")
        let tx = try makeTransaction(coin: dot, amountWasAutoAdjusted: true)
        XCTAssertFalse(SendCryptoVerifyLogic.needsEVMBalanceRefit(tx: tx))
    }

    /// `copy` is a field-by-field builder whose own doc warns that every new
    /// field is one someone must remember to add. Losing this one silently
    /// drops the re-fit on the transaction that most needs it.
    func testCopyCarriesTheAutoAdjustedMarker() throws {
        let adjusted = try makeTransaction(amountWasAutoAdjusted: true)
        XCTAssertTrue(adjusted.copy(amount: "0.2").amountWasAutoAdjusted)

        let typed = try makeTransaction()
        XCTAssertFalse(typed.copy(amount: "0.2").amountWasAutoAdjusted)
        XCTAssertTrue(typed.copy(amountWasAutoAdjusted: true).amountWasAutoAdjusted)
    }

    // MARK: - Helpers

    /// Seeds a live rate so fiat assertions mean something. Without one every
    /// fiat figure is the empty string and a "the fiat followed the amount"
    /// assertion passes for the wrong reason.
    private func setPrice(_ value: Double, for coin: Coin) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        do {
            try RateProvider.shared.save(rates: [
                Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
            ])
        } catch {
            XCTFail("Failed to seed rate for \(coin.ticker): \(error)")
        }
        XCTAssertEqual(coin.price, value, accuracy: 0.0001, "rate for \(coin.ticker) did not take effect")
    }

    /// The fiat figure the Verify header renders, for a given amount string.
    private func vmFiat(coin: Coin, amount: String) -> String {
        CryptoAmountFormatter.amountInFiat(
            coin: coin,
            amount: SendCryptoLogic.amountDecimal(coin: coin, amount: amount)
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0", contractAddress: String? = nil) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        if let contractAddress {
            coin.contractAddress = contractAddress
        }
        return coin
    }

    /// A minimal native-ETH pre-built payload, optionally carrying a bundled
    /// ERC-20 approve (the bundled first-deposit case) or none (Circle withdraw).
    private func makePrebuiltPayload(approvePayload: ERC20ApprovePayload?) -> KeysignPayload {
        let nativeEth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true,
                                 rawBalance: "1000000000000000000")
        return KeysignPayload(
            coin: nativeEth,
            toAddress: "0x2222222222222222222222222222222222222222",
            toAmount: BigInt(0),
            chainSpecific: .Ethereum(maxFeePerGasWei: BigInt(1), priorityFeeWei: BigInt(1), nonce: 0, gasLimit: BigInt(21_000)),
            utxos: [],
            memo: "0x6e553f65",
            swapPayload: nil,
            approvePayload: approvePayload,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func makeTransaction(
        coin: Coin? = nil,
        amount: String = "0.1",
        fee: BigInt = BigInt(stringLiteral: "1000000000000000"),
        feeMode: FeeMode = .default,
        customGasLimit: BigInt? = nil,
        sendMaxAmount: Bool = false,
        amountWasAutoAdjusted: Bool = false
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
            sendMaxAmount: sendMaxAmount,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coinToUse,
            amountWasAutoAdjusted: amountWasAutoAdjusted
        )
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

// `async` is required by `HTTPClientProtocol`; the stub answers synchronously.
// swiftlint:disable async_without_await

/// Scripted HTTP client keyed on the `RippleAPI` endpoint, so the Verify-load
/// destination lookup can be driven without the network.
private final class VerifyScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    var accountInfoResult: Result<Data, Error> = .failure(URLError(.badServerResponse))
    var serverStateResult: Result<Data, Error> = .failure(URLError(.badServerResponse))

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let api = target as? RippleAPI else {
            throw URLError(.unsupportedURL)
        }
        switch api.endpoint {
        case .accountInfo:
            return try respond(accountInfoResult)
        case .serverState:
            return try respond(serverStateResult)
        case .submit, .tx, .accountLines:
            throw URLError(.unsupportedURL)
        }
    }

    private func respond(_ result: Result<Data, Error>) throws -> HTTPResponse<Data> {
        let data = try result.get()
        guard let url = URL(string: "https://xrplcluster.com"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badURL)
        }
        return HTTPResponse(data: data, response: response)
    }
}

// swiftlint:enable async_without_await
