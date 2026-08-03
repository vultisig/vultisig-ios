//
//  SendInteractor.swift
//  VultisigApp
//
//  Protocol layer between the Send feature's ViewModels and the underlying
//  services (chain-specific data, fast vault, balance, payload factory). Lets
//  the VM tests drive happy/error paths through mocks instead of network
//  singletons. Mirrors `SwapInteractor`.
//
//  Note (send-pilot decision 3): `fetchChainSpecific` and `calculateEVMFee`
//  take `feeMode` explicitly. The legacy `SendCryptoVerifyLogic.calculateEVMFee`
//  hardcoded `.default`, which dropped the user's pinned fee mode on Verify
//  refresh. This protocol forces every caller to thread the field through.
//

import BigInt
import Foundation
import VultisigCommonData

struct SendChainSpecificRequest: Equatable {
    let coin: Coin
    let toAddress: String
    let amount: BigInt
    let memo: String?
    let sendMaxAmount: Bool
    let isDeposit: Bool
    let transactionType: VSTransactionType
    let gasLimit: BigInt?
    /// The user-pinned gas limit from the Send form's gas settings, when set.
    /// Carried separately from `gasLimit` (which collapses custom/estimated/
    /// default) so the chain-specific build can honor an explicit override
    /// instead of overwriting it with a fresh estimate.
    let customGasLimit: BigInt?
    /// The user-pinned sat/vB rate from the Send form's gas settings, when set.
    /// UTXO chains price a transaction as `rate × size`, so this is the one
    /// input that lets the user actually lower (or raise) a UTXO fee — without
    /// it the chain-specific build recomputes the rate from `feeMode` and the
    /// gas sheet's "Network rate" field does nothing.
    let customByteFee: BigInt?
    let feeMode: FeeMode
    let fromAddress: String

    init(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        sendMaxAmount: Bool,
        isDeposit: Bool,
        transactionType: VSTransactionType,
        gasLimit: BigInt?,
        customGasLimit: BigInt? = nil,
        customByteFee: BigInt? = nil,
        feeMode: FeeMode,
        fromAddress: String
    ) {
        self.coin = coin
        self.toAddress = toAddress
        self.amount = amount
        self.memo = memo
        self.sendMaxAmount = sendMaxAmount
        self.isDeposit = isDeposit
        self.transactionType = transactionType
        self.gasLimit = gasLimit
        self.customGasLimit = customGasLimit
        self.customByteFee = customByteFee
        self.feeMode = feeMode
        self.fromAddress = fromAddress
    }

    init(tx: SendTransaction) {
        self.init(
            coin: tx.coin,
            toAddress: tx.toAddress,
            amount: tx.amountInRaw,
            memo: tx.memo.isEmpty ? nil : tx.memo,
            sendMaxAmount: tx.sendMaxAmount,
            isDeposit: tx.isDeposit,
            transactionType: tx.transactionType,
            gasLimit: tx.gasLimit,
            customGasLimit: tx.customGasLimit,
            customByteFee: tx.customByteFee,
            feeMode: tx.feeMode,
            fromAddress: tx.fromAddress
        )
    }
}

struct SendFeeEstimateRequest: Equatable {
    let chainSpecific: SendChainSpecificRequest

    var coin: Coin { chainSpecific.coin }
    var fromAddress: String { chainSpecific.fromAddress }
    var gasLimit: BigInt? { chainSpecific.gasLimit }
    var customGasLimit: BigInt? { chainSpecific.customGasLimit }
    var customByteFee: BigInt? { chainSpecific.customByteFee }
    var feeMode: FeeMode { chainSpecific.feeMode }

    init(chainSpecific: SendChainSpecificRequest) {
        self.chainSpecific = chainSpecific
    }

    init(tx: SendTransaction) {
        self.init(chainSpecific: SendChainSpecificRequest(tx: tx))
    }
}

protocol SendInteractor {
    /// Chain-specific fee / nonce / blockhash data needed to assemble the
    /// keysign payload. `feeMode` controls EVM priority and UTXO byte-fee
    /// tier — never hardcode `.default` at the call site.
    func fetchChainSpecific(_ request: SendChainSpecificRequest) async throws -> BlockChainSpecific

    /// Compute the user-visible EVM network fee (Eip1559 / legacy gas) in the
    /// chain's native units. Caller resolves `feeMode` — passing it explicitly
    /// is the fix for the bug where Verify refresh ignored `tx.feeMode`.
    func calculateEVMFee(_ request: SendFeeEstimateRequest) async throws -> SendInteractorFeeResult

    /// UTXO/Cardano draft planning for fee display. Kept below the interactor
    /// so Verify logic does not reach into BlockchairService caches or payload
    /// factories directly.
    func calculatePlanFee(tx: SendTransaction, chainSpecific: BlockChainSpecific) async throws -> BigInt

    /// Plan a real max send for the UTXO family and report what it would
    /// actually send and cost.
    ///
    /// A UTXO fee is `rate × size`, and the size is only known once inputs are
    /// selected — so the sat/vB rate carried on `BlockChainSpecific` is not a
    /// fee, and `balance − rate` is not a max amount. Build the transaction the
    /// signer will build, with `useMaxAmount` on, and read the planner's own
    /// amount and fee off it. `request.sendMaxAmount` must be `true`.
    ///
    /// UTXO-family only: Cardano derives its fee from the signed size at payload
    /// build time, so its `BlockChainSpecific` fee is already a usable total.
    ///
    /// `refreshUtxos` re-fetches the UTXO set before planning. The Send form
    /// plans against the cached set (Max is tapped repeatedly while editing);
    /// the Verify screen refreshes, matching `calculatePlanFee`, because that
    /// plan is the one about to be signed.
    func calculateMaxSendPlan(
        _ request: SendChainSpecificRequest,
        vault: Vault,
        refreshUtxos: Bool
    ) async throws -> SendMaxPlanResult

    /// Validate UTXO availability before payload construction.
    func validateUtxosIfNeeded(coin: Coin) async throws

    /// Re-plan an already-built payload and report what it will actually send
    /// and pay. `nil` for chains that have no such plan.
    ///
    /// Exists so the signing path can confirm the transaction it is about to
    /// hand to the ceremony still matches the one the user approved — the input
    /// set is refetched between the two, and a `useMaxAmount` plan is defined by
    /// whatever that set contains.
    func plannedOutcome(for payload: KeysignPayload) async throws -> SendMaxPlanResult?

    /// Build the final keysign payload to hand off to signing. UTXO + Cardano
    /// chains plan a draft transfer internally; other chains read directly
    /// off `chainSpecific`.
    func buildKeysignPayload(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        chainSpecific: BlockChainSpecific,
        wasmExecuteContractPayload: WasmExecuteContractPayload?,
        vault: Vault
    ) async throws -> KeysignPayload

    /// Refresh balance for a single coin.
    func updateBalance(for coin: Coin) async
}

/// What a real `useMaxAmount` UTXO transaction plan would send and cost.
struct SendMaxPlanResult: Equatable {
    /// What the recipient actually receives — the selected inputs minus the
    /// fee. More honest than `balance − fee`: it already excludes any output
    /// the spendability filter left out of the selection.
    let amount: BigInt
    /// The fee the planned transaction really pays, for its real size.
    let fee: BigInt
    /// The sat/vB rate the plan was priced at, for the gas-settings display.
    let byteFee: BigInt
}

struct SendInteractorFeeResult: Equatable {
    let fee: BigInt
    let gas: BigInt
    /// The gas limit the EVM fee was computed against — the real `eth_estimateGas`
    /// result (padded/floored) or the user override. `nil` for non-EVM chains.
    /// The Send form stores this as `estimatedGasLimit` so the displayed fee and
    /// the editable gas-settings value reflect the estimate.
    var gasLimit: BigInt? = nil
}

extension SendInteractor {
    /// Convenience overload that reads the 10 primitives off an immutable
    /// `SendTransaction`. Lets Verify-stage callers (which already hold the
    /// struct) skip the field-by-field unpacking.
    func fetchChainSpecific(tx: SendTransaction) async throws -> BlockChainSpecific {
        try await fetchChainSpecific(SendChainSpecificRequest(tx: tx))
    }

    /// Unified gas + fee fetch used by the Send Details form (both refresh
    /// and max-amount paths). EVM goes through `calculateEVMFee` to honor the
    /// dynamic fee mode; UTXO + Cardano read `fee` off the chain-specific
    /// (the byte-fee × planned size); other chains use `gas` as a flat fee.
    ///
    /// Callers that need the "fee that's actually deducted from THIS coin's
    /// balance" (e.g. computing max-amount) post-process the result: gas is
    /// paid in the native sibling for ERC20 / SPL etc., so non-native sources
    /// see `.zero` for the deductible fee even though the real gas/fee here
    /// is non-zero. That distinction stays at the call site — this method
    /// always returns the true on-chain values.
    func fetchGasAndFee(
        _ request: SendFeeEstimateRequest
    ) async throws -> SendInteractorFeeResult {
        let chainSpecific = try await fetchChainSpecific(request.chainSpecific)

        switch request.coin.chainType {
        case .EVM:
            return try await calculateEVMFee(request)
        case .UTXO, .Cardano:
            return SendInteractorFeeResult(fee: chainSpecific.fee, gas: chainSpecific.gas)
        default:
            return SendInteractorFeeResult(fee: chainSpecific.gas, gas: chainSpecific.gas)
        }
    }

    func fetchGasAndFee(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        sendMaxAmount: Bool,
        isDeposit: Bool,
        transactionType: VSTransactionType,
        gasLimit: BigInt?,
        customGasLimit: BigInt? = nil,
        customByteFee: BigInt? = nil,
        feeMode: FeeMode,
        fromAddress: String
    ) async throws -> SendInteractorFeeResult {
        try await fetchGasAndFee(SendFeeEstimateRequest(chainSpecific: SendChainSpecificRequest(
            coin: coin,
            toAddress: toAddress,
            amount: amount,
            memo: memo,
            sendMaxAmount: sendMaxAmount,
            isDeposit: isDeposit,
            transactionType: transactionType,
            gasLimit: gasLimit,
            customGasLimit: customGasLimit,
            customByteFee: customByteFee,
            feeMode: feeMode,
            fromAddress: fromAddress
        )))
    }
}
