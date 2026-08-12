//
//  KaminoTransactionPreparer.swift
//  VultisigApp
//

import BigInt
import Foundation
import OSLog

/// The Solana reads a Kamino transaction needs on top of the Kamino API.
///
/// Narrow on purpose: this is the seam the preparer is driven through in tests,
/// and everything on it is a *measurement* — what the transaction would do, what
/// the network is charging, what the runtime requires an account to hold.
protocol KaminoSolanaMeasuring {
    func simulateTransaction(
        base64Transaction: String,
        replaceRecentBlockhash: Bool,
        accountAddresses: [String]
    ) async throws -> SolanaSimulationResult

    /// `nil` when the network reported no non-zero fee. The Kamino floor is
    /// applied here, not inherited from another caller's default.
    func fetchPrioritizationFeeSample() async throws -> UInt64?

    func fetchRentExemptMinimum(size: Int) async throws -> UInt64
}

extension SolanaService: KaminoSolanaMeasuring {}

/// The compute-unit price both forms pin for the lifetime of a session.
protocol KaminoPriorityPricing {
    func resolveUnitPrice() async -> UInt64
}

/// What a deposit form needs from the pipeline.
///
/// Separated from the concrete preparer so a form's own decisions — the minimum
/// gate, the maximum, which unit an amount is in — can be asserted without
/// standing up the whole build/validate/simulate chain, which has its own tests.
protocol KaminoDepositPreparing: KaminoPriorityPricing {
    func prepareDeposit(
        vault: KaminoVaultInfo,
        owner: String,
        amount: KaminoTokenAmount,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction

    func maxNativeDepositLamports(
        vault: KaminoVaultInfo,
        owner: String,
        probe: KaminoTokenAmount,
        unitPrice: UInt64
    ) async throws -> BigInt
}

/// What a withdraw form needs from the pipeline.
///
/// The amount is a `KaminoWithdrawRequest`, whose `shares` is a
/// `KaminoShareAmount` and cannot be anything else: the API takes the same
/// `amount` field for both actions with inverted units, and the type is what
/// makes handing it a token amount a compile error rather than a withdraw
/// mis-sized by the share rate. The request also carries the unstaked half of
/// the position, because that is what decides which of the two withdraw shapes
/// the API will build and therefore which one the validator must require.
protocol KaminoWithdrawPreparing: KaminoPriorityPricing {
    func prepareWithdraw(
        vault: KaminoVaultInfo,
        owner: String,
        request: KaminoWithdrawRequest,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction
}

/// A Kamino transaction that has passed every gate and is ready to be signed.
struct KaminoPreparedTransaction: Equatable {
    /// The base64 wire bytes, ComputeBudget instructions included. These are
    /// signed verbatim.
    let base64: String
    /// The compute budget this app injected. Pinned into the payload so the
    /// verify screen and the validator both read the same numbers.
    let priorityFee: KaminoPriorityFee
    /// Compute units the injected transaction consumed when simulated.
    let unitsConsumed: UInt64?
    /// Lamports the fee payer is left holding after the transaction, measured by
    /// the final simulation. `nil` when the node did not return the account.
    let payerLamportsAfter: UInt64?
    /// The blockhash the bytes carry now. Replaced immediately before keysign.
    let recentBlockhash: String
}

enum KaminoPreparationError: Error, LocalizedError, Equatable {
    /// The transaction was built and validated but would not execute. `stage`
    /// says which of the two simulations refused it — as built, or after the
    /// compute budget was injected — and is for diagnosis, not for the user.
    case simulationFailed(stage: Stage, reason: String)
    /// The node ran the transaction but did not report the payer's balance, so
    /// nothing here can say what the transaction costs.
    case payerBalanceUnavailable

    enum Stage: String, Equatable {
        case asBuilt
        case budgeted
    }

    var errorDescription: String? {
        switch self {
        case .simulationFailed(_, let reason):
            return String(format: "kaminoSimulationFailed".localized, reason)
        case .payerBalanceUnavailable:
            return "kaminoPayerBalanceUnavailable".localized
        }
    }
}

/// Turns a user's deposit request into signable bytes, refusing at every step
/// that cannot be proven.
///
/// Kamino builds the transaction, so the app's whole safety argument is what it
/// does between the response and the signature:
///
/// 1. **Build** through `KaminoService`, whose typed amounts carry their unit.
/// 2. **Validate** with `priorityFee: nil`. At this point the transaction is
///    exactly what Kamino returned, and Kamino emits no ComputeBudget
///    instructions — so any ComputeBudget instruction here is a fee the app did
///    not choose, and the validator refuses it.
/// 3. **Simulate.** A transaction that does not execute is refused before a
///    signer ever sees it, and the run also measures what it costs.
/// 4. **Inject** the compute budget. Kamino's transactions carry none and every
///    one of them consumes more than the runtime's default would allow once a
///    limit is set, so the limit is chosen here from measured usage.
/// 5. **Re-validate** with the injected `KaminoPriorityFee`. Now both
///    ComputeBudget instructions are *required* and pinned to the exact values
///    injected — a second pass, not a repeat, because the contract being checked
///    is the opposite one.
/// 6. **Re-simulate, requiring success.** The bytes that get signed are the
///    bytes that were proven to execute.
///
/// Steps 2 and 5 are deliberately not collapsed. "No fee unless we put one
/// there" and "exactly the fee we put there" are different statements, and only
/// running both makes an injected instruction distinguishable from a supplied
/// one.
struct KaminoTransactionPreparer: KaminoDepositPreparing, KaminoWithdrawPreparing {

    private let service: KaminoServiceProtocol
    private let solana: KaminoSolanaMeasuring
    private let validator: KaminoTransactionValidator
    private let logger = Log.defi.service

    /// Data size of a plain wallet account — the rent-exempt floor its balance
    /// has to clear.
    private static let walletAccountDataSize = 0

    init(
        service: KaminoServiceProtocol = KaminoService(),
        solana: KaminoSolanaMeasuring = SolanaService.shared,
        validator: KaminoTransactionValidator = KaminoTransactionValidator()
    ) {
        self.service = service
        self.solana = solana
        self.validator = validator
    }

    // MARK: - Priority fee

    /// The compute-unit price to use for this deposit, clamped into a bounded
    /// range.
    ///
    /// Resolved once by the caller and reused for both the reserve probe and the
    /// real transaction: the two must be priced identically or the measured
    /// reserve would not describe the transaction it is used to size. A failed
    /// sample is not an error — the fallback is a usable price — and a network
    /// that reported no priority fees at all is the fallback case too, not a
    /// reason to pay the ceiling.
    func resolveUnitPrice() async -> UInt64 {
        do {
            guard let sample = try await solana.fetchPrioritizationFeeSample() else {
                return KaminoComputeBudget.fallbackUnitPriceMicroLamports
            }
            return KaminoComputeBudget.clampedUnitPrice(sample)
        } catch {
            logger.warning(
                "[kamino] priority fee sample failed, using fallback: \(error.localizedDescription, privacy: .public)"
            )
            return KaminoComputeBudget.fallbackUnitPriceMicroLamports
        }
    }

    // MARK: - Deposit

    /// Builds, checks and budgets a deposit of `amount` of the vault's
    /// underlying token.
    func prepareDeposit(
        vault: KaminoVaultInfo,
        owner: String,
        amount: KaminoTokenAmount,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction {
        let built = try await service.buildDepositTransaction(
            owner: owner,
            vault: vault.descriptor,
            amount: amount
        )

        return try await finish(
            base64: built,
            operation: .deposit(amount),
            vault: vault,
            owner: owner,
            unitLimit: KaminoComputeBudget.depositUnitLimit(for: vault),
            unitPrice: unitPrice
        )
    }

    /// The largest deposit this wallet can make out of its native SOL balance,
    /// in lamports.
    ///
    /// Derived, not estimated. A SOL deposit spends more than the amount: the
    /// base fee, the priority fee (`limit × price`), the rent for a wrapped-SOL
    /// account that the deposit creates and never closes, and the rent for
    /// whichever of the share account and farm-user account do not exist yet.
    /// Every one of those varies — with the fee market, with the compute limit,
    /// and with which accounts this particular wallet already has — so the only
    /// honest number comes from running the transaction.
    ///
    /// So a probe deposit is prepared and simulated, and the payer's balance
    /// *after* it is read back. What the payer is left with, plus what the probe
    /// deposited, is what a deposit could have consumed in total; subtracting the
    /// rent-exempt floor keeps the wallet account alive and above the balance
    /// band the runtime rejects.
    ///
    /// The reserve does not depend on the deposit amount — a fee and a rent are
    /// the same whatever is being deposited — which is what makes measuring it
    /// once at `probe` valid for the maximum. And if it were ever wrong, the real
    /// transaction is re-simulated at the amount actually chosen, so the failure
    /// mode is a refusal rather than a stranded transaction.
    ///
    /// One assumption is worth naming: the runtime debits the fee from the payer
    /// while loading the transaction, so the post-simulation balance is net of it.
    /// If a node ever reported a pre-fee balance instead, this maximum would be
    /// too large by the fee — and the deposit at that maximum would leave the
    /// payer just under the rent-exempt floor and be rejected on chain. That
    /// shows up as the final simulation refusing, never as a signed transaction
    /// that fails, which is why it is safe to depend on.
    func maxNativeDepositLamports(
        vault: KaminoVaultInfo,
        owner: String,
        probe: KaminoTokenAmount,
        unitPrice: UInt64
    ) async throws -> BigInt {
        let prepared = try await prepareDeposit(
            vault: vault,
            owner: owner,
            amount: probe,
            unitPrice: unitPrice
        )
        guard let remaining = prepared.payerLamportsAfter else {
            throw KaminoPreparationError.payerBalanceUnavailable
        }

        let floor = try await solana.fetchRentExemptMinimum(size: Self.walletAccountDataSize)
        let spendable = BigInt(remaining) + probe.baseUnits - BigInt(floor)
        return max(spendable, 0)
    }

    // MARK: - Withdraw

    /// Builds, checks and budgets a withdraw of `shares` from the vault.
    ///
    /// The same `finish`/`inject` core as a deposit — only the build call, the
    /// unit in the amount and the compute limit differ. What the caller decides
    /// is the one thing this cannot: how many shares. `KaminoWithdrawMath` owns
    /// that, and the reason it must is the API's `u64::MAX` rewrite of an
    /// over-sized request.
    ///
    /// The validator's second pass pins the withdraw instruction's `u64` to
    /// exactly `request.shares`, so a response that came back carrying the
    /// sentinel — or any other amount — is refused before simulation and before
    /// signing. That is what makes a stale balance read cost a refusal rather
    /// than a full exit. When the request exceeds the shares already unstaked it
    /// also pins the farm release to exactly the shortfall, and requires it to
    /// be there.
    func prepareWithdraw(
        vault: KaminoVaultInfo,
        owner: String,
        request: KaminoWithdrawRequest,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction {
        let built = try await service.buildWithdrawTransaction(
            owner: owner,
            vault: vault.descriptor,
            shares: request.shares
        )

        return try await finish(
            base64: built,
            operation: .withdraw(request),
            vault: vault,
            owner: owner,
            unitLimit: KaminoComputeBudget.withdrawUnitLimit,
            unitPrice: unitPrice
        )
    }

    // MARK: - Pipeline

    private func finish(
        base64: String,
        operation: KaminoOperation,
        vault: KaminoVaultInfo,
        owner: String,
        unitLimit: UInt32,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction {
        let transaction = try SolanaV0Transaction(base64Transaction: base64)

        // Phase one. No fee has been chosen yet, so a ComputeBudget instruction
        // can only have come from the response — and the response is the thing
        // being checked.
        let asBuilt = KaminoTransactionIntent(
            operation: operation,
            vault: vault,
            owner: owner,
            priorityFee: nil
        )
        try await validator.validate(transaction: transaction, intent: asBuilt)

        // `replaceRecentBlockhash` because the response's blockhash is already
        // ageing and the live one is spliced in later anyway; what is being
        // proven here is the instructions, not the blockhash.
        let dryRun = try await solana.simulateTransaction(
            base64Transaction: base64,
            replaceRecentBlockhash: true,
            accountAddresses: []
        )
        guard dryRun.succeeded else {
            throw KaminoPreparationError.simulationFailed(
                stage: .asBuilt,
                reason: dryRun.failure ?? "unknown"
            )
        }

        return try await inject(
            transaction: transaction,
            operation: operation,
            vault: vault,
            owner: owner,
            unitLimit: unitLimit,
            unitPrice: unitPrice
        )
    }

    private func inject(
        transaction: SolanaV0Transaction,
        operation: KaminoOperation,
        vault: KaminoVaultInfo,
        owner: String,
        unitLimit: UInt32,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction {
        let fee = KaminoPriorityFee(limit: unitLimit, price: unitPrice)
        let budgeted = try transaction.injectingComputeBudget(price: fee.price, limit: fee.limit)

        // Phase two, and the opposite contract: both ComputeBudget instructions
        // are now required, in order, carrying exactly the values above.
        let injected = KaminoTransactionIntent(
            operation: operation,
            vault: vault,
            owner: owner,
            priorityFee: fee
        )
        try await validator.validate(transaction: budgeted, intent: injected)

        let base64 = budgeted.base64EncodedTransaction
        let verdict = try await solana.simulateTransaction(
            base64Transaction: base64,
            replaceRecentBlockhash: true,
            accountAddresses: [owner]
        )
        guard verdict.succeeded else {
            throw KaminoPreparationError.simulationFailed(
                stage: .budgeted,
                reason: verdict.failure ?? "unknown"
            )
        }

        return KaminoPreparedTransaction(
            base64: base64,
            priorityFee: fee,
            unitsConsumed: verdict.unitsConsumed,
            payerLamportsAfter: verdict.accountLamports[owner],
            recentBlockhash: budgeted.recentBlockhash
        )
    }
}
