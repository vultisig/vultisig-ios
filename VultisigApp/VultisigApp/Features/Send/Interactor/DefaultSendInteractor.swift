//
//  DefaultSendInteractor.swift
//  VultisigApp
//
//  Concrete `SendInteractor` wiring. Production builds via `.live` with the
//  existing `.shared` singletons; tests can inject a mock conforming to the
//  protocol.
//

import BigInt
import Foundation
import OSLog
import VultisigCommonData

private let logger = Log.send.interactor

struct DefaultSendInteractor: SendInteractor {
    let blockchain: BlockChainService
    let balance: BalanceService
    let fastVault: FastVaultService
    let keysignFactory: KeysignPayloadFactory
    let utxo: BlockchairService

    static var live: SendInteractor {
        DefaultSendInteractor(
            blockchain: BlockChainService.shared,
            balance: BalanceService.shared,
            fastVault: FastVaultService.shared,
            keysignFactory: KeysignPayloadFactory(),
            utxo: BlockchairService.shared
        )
    }

    func fetchChainSpecific(_ request: SendChainSpecificRequest) async throws -> BlockChainSpecific {
        try await blockchain.fetchSendBlockChainSpecific(
            coin: request.coin,
            toAddress: request.toAddress,
            amount: request.amount,
            memo: request.memo,
            sendMaxAmount: request.sendMaxAmount,
            isDeposit: request.isDeposit,
            transactionType: request.transactionType,
            gasLimit: request.gasLimit,
            customGasLimit: request.customGasLimit,
            customByteFee: request.customByteFee,
            feeMode: request.feeMode,
            fromAddress: request.fromAddress
        )
    }

    func calculateEVMFee(_ request: SendFeeEstimateRequest) async throws -> SendInteractorFeeResult {
        let service = try EthereumFeeService(chain: request.coin.chain)
        let cs = request.chainSpecific

        // Size the limit the displayed fee is computed against the same way the
        // keysign payload is: honor a user override, otherwise estimate against
        // the real recipient and floor at the per-chain default. This is what
        // makes the Send form's fee — and the seeded gas-settings value —
        // reflect the estimate instead of the flat 23000/120000 default.
        let fallbackGasLimit = request.coin.isNativeToken
            ? BigInt(EVMHelper.defaultETHTransferGasUnit)
            : BigInt(EVMHelper.defaultERC20TransferGasUnit)
        let resolvedGasLimit = await blockchain.resolveEVMSendGasLimit(
            coin: cs.coin,
            fromAddress: cs.fromAddress,
            toAddress: cs.toAddress,
            amount: cs.amount,
            memo: cs.memo,
            requestedGasLimit: request.gasLimit,
            customGasLimit: request.customGasLimit
        ) ?? fallbackGasLimit

        let feeInfo = try await service.calculateFees(
            chain: request.coin.chain,
            limit: resolvedGasLimit,
            isSwap: false,
            fromAddress: request.fromAddress,
            feeMode: request.feeMode
        )

        let fee = feeInfo.amount
        let gas: BigInt
        switch feeInfo {
        case let .GasFee(price, _, _, _):
            gas = price
        case let .Eip1559(_, maxFeePerGas, _, _, _):
            gas = maxFeePerGas
        case let .BasicFee(amount, _, limit):
            gas = limit > 0 ? amount / limit : amount
        }

        return SendInteractorFeeResult(fee: fee, gas: gas, gasLimit: resolvedGasLimit)
    }

    func fetchOpStackFeeReserve(coin: Coin, memo: String?, gasLimit: BigInt?) async -> BigInt {
        guard coin.chain.isOpStack, let service = try? EvmService.getService(forChain: coin.chain) else {
            return .zero
        }

        return await Self.opStackReserveSum(
            chain: coin.chain,
            l1DataFee: {
                try await service.fetchOpStackL1DataFee(unsignedTxSize: Self.l1FeeProbeTxSize(memo: memo))
            },
            operatorFee: {
                guard let gasLimit, gasLimit > 0 else { return .zero }
                return try await service.fetchOpStackOperatorFee(gasLimit: gasLimit)
            }
        )
    }

    /// Sums the two surcharges op-geth adds to its balance check. Each term
    /// degrades on its own: Blast's oracle predates `getOperatorFee` and reverts
    /// on it, and letting that failure take the L1 data fee down with it would
    /// leave the chain reserving nothing at all.
    static func opStackReserveSum(
        chain: Chain,
        l1DataFee: () async throws -> BigInt,
        operatorFee: () async throws -> BigInt
    ) async -> BigInt {
        await reserveTerm(named: "L1 data fee", chain: chain, fetch: l1DataFee)
            + reserveTerm(named: "operator fee", chain: chain, fetch: operatorFee)
    }

    /// Runs one reserve lookup, failing open. Reserving nothing is exactly the
    /// behaviour that shipped before these lookups existed, so an unreachable or
    /// too-old oracle degrades the send rather than blocking it. A negative
    /// answer is nonsense from a fee oracle and is floored at zero rather than
    /// handed on to widen the max amount.
    private static func reserveTerm(
        named name: String,
        chain: Chain,
        fetch: () async throws -> BigInt
    ) async -> BigInt {
        do {
            return max(.zero, try await fetch())
        } catch {
            logger.warning("OP-stack \(name, privacy: .public) lookup failed for \(chain.name, privacy: .public); reserving nothing for it")
            return .zero
        }
    }

    /// Size, in bytes, that the L1-fee probe stands in for. The oracle expects
    /// the UNSIGNED serialized transaction and adds its own 68-byte allowance
    /// for the signature, so this models the ~70-byte unsigned EIP-1559 native
    /// transfer with deliberate margin: the payload isn't built yet when the fee
    /// has to be reserved, and over-reserving leaves dust where under-reserving
    /// costs a rejected broadcast after the ceremony already ran. The memo
    /// becomes the transaction's `data`, either UTF-8 bytes or half as many when
    /// it is hex, so its UTF-8 length bounds both.
    private static func l1FeeProbeTxSize(memo: String?) -> Int {
        160 + (memo?.utf8.count ?? 0)
    }

    func calculatePlanFee(tx: SendTransaction, chainSpecific: BlockChainSpecific) async throws -> BigInt {
        let normalizedAmount = tx.amount.replacingOccurrences(of: ",", with: ".")
        let amountDecimal = normalizedAmount.toDecimal()
        let multiplier = pow(Decimal(10), tx.coin.decimals)
        let rawAmount = amountDecimal * multiplier
        let rawAmountNumber = NSDecimalNumber(decimal: rawAmount)
        let behavior = NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let roundedRawAmount = rawAmountNumber.rounding(accordingToBehavior: behavior)

        guard let actualAmount = BigInt(roundedRawAmount.stringValue) else {
            throw HelperError.runtimeError("Invalid amount for fee calculation")
        }

        if actualAmount == 0 {
            throw HelperError.runtimeError("Enter an amount to calculate accurate UTXO fees")
        }

        if tx.coin.chain.chainType == .UTXO {
            await utxo.clearUTXOCache(for: tx.coin)
            _ = try await utxo.fetchBlockchairData(coin: tx.coin.toCoinMeta(), address: tx.coin.address)
        }

        let keysignPayload = try await keysignFactory.buildTransfer(
            coin: tx.coin,
            toAddress: tx.toAddress.isEmpty ? tx.coin.address : tx.toAddress,
            amount: actualAmount,
            memo: tx.memo.isEmpty ? nil : tx.memo,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            vault: tx.vault
        )

        switch tx.coin.chain {
        case .cardano:
            return try CardanoHelper.calculateDynamicFee(keysignPayload: keysignPayload)
        default:
            guard let utxoHelper = UTXOChainsHelper.getHelper(coin: tx.coin) else {
                throw HelperError.runtimeError("UTXO helper not available for \(tx.coin.chain.name)")
            }
            let plan = try utxoHelper.getBitcoinTransactionPlan(keysignPayload: keysignPayload)
            // A failed plan has `fee == 0`. Returning it would quote a free
            // transaction on the Verify screen and let the balance check pass on
            // arithmetic that never held, so the failure only surfaced at Sign
            // time as a generic message. Fail here, with the planner's reason.
            try UTXOTransactionPlanError.validate(plan)
            return BigInt(plan.fee)
        }
    }

    func calculateMaxSendPlan(
        _ request: SendChainSpecificRequest,
        vault: Vault,
        refreshUtxos: Bool
    ) async throws -> SendMaxPlanResult {
        guard request.coin.chainType == .UTXO else {
            throw HelperError.runtimeError("Max-send planning is only supported for UTXO chains")
        }
        guard let utxoHelper = UTXOChainsHelper.getHelper(coin: request.coin) else {
            throw HelperError.runtimeError("UTXO helper not available for \(request.coin.chain.name)")
        }

        if refreshUtxos {
            await utxo.clearUTXOCache(for: request.coin)
            _ = try await utxo.fetchBlockchairData(coin: request.coin.toCoinMeta(), address: request.coin.address)
        }

        let chainSpecific = try await fetchChainSpecific(request)

        // Plan against the sender's own address when there is no recipient yet:
        // the output script type affects the transaction's size, and therefore
        // the fee, so planning needs *an* address rather than none.
        let payload = try await keysignFactory.buildTransfer(
            coin: request.coin,
            toAddress: request.toAddress.isEmpty ? request.coin.address : request.toAddress,
            amount: request.amount,
            memo: request.memo,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            vault: vault
        )

        let plan = try utxoHelper.getBitcoinTransactionPlan(keysignPayload: payload)
        try UTXOTransactionPlanError.validate(plan)
        // A plan with no error but nothing to send is still not a max send —
        // treat it as the funding verdict it is rather than filling the field
        // with zero.
        guard plan.amount > 0, plan.fee > 0 else {
            throw UTXOTransactionPlanError.insufficientFunds
        }

        return SendMaxPlanResult(
            amount: BigInt(plan.amount),
            fee: BigInt(plan.fee),
            byteFee: chainSpecific.gas
        )
    }

    // `async` is required by the protocol so MainActor-isolated conformers (the
    // test mock) can implement it; WalletCore planning itself is synchronous.
    // swiftlint:disable:next async_without_await
    func plannedOutcome(for payload: KeysignPayload) async throws -> SendMaxPlanResult? {
        guard payload.coin.chainType == .UTXO,
              let utxoHelper = UTXOChainsHelper.getHelper(coin: payload.coin) else {
            return nil
        }
        let plan = try utxoHelper.getBitcoinTransactionPlan(keysignPayload: payload)
        try UTXOTransactionPlanError.validate(plan)
        return SendMaxPlanResult(
            amount: BigInt(plan.amount),
            fee: BigInt(plan.fee),
            byteFee: payload.chainSpecific.gas
        )
    }

    func validateUtxosIfNeeded(coin: Coin) async throws {
        guard coin.chain.chainType == .UTXO else { return }
        do {
            _ = try await utxo.fetchBlockchairData(coin: coin.toCoinMeta(), address: coin.address)
        } catch {
            throw HelperError.runtimeError("Failed to fetch UTXO data. Please check your internet connection and try again.")
        }
    }

    func buildKeysignPayload(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        chainSpecific: BlockChainSpecific,
        wasmExecuteContractPayload: WasmExecuteContractPayload?,
        vault: Vault
    ) async throws -> KeysignPayload {
        try await keysignFactory.buildTransfer(
            coin: coin,
            toAddress: toAddress,
            amount: amount,
            memo: memo,
            chainSpecific: chainSpecific,
            swapPayload: nil,
            approvePayload: nil,
            vault: vault,
            wasmExecuteContractPayload: wasmExecuteContractPayload
        )
    }

    func updateBalance(for coin: Coin) async {
        await balance.updateBalance(for: coin)
    }
}
