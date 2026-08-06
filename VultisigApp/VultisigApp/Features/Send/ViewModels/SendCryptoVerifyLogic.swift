//
//  SendCryptoVerifyLogic.swift
//  VultisigApp
//
//  Business logic for SendCryptoVerifyViewModel
//

import Foundation
import BigInt
import VultisigCommonData
import WalletCore

struct SendCryptoVerifyLogic {

    // MARK: - Dependencies

    let interactor: SendInteractor
    private let rippleService: RippleService

    init(
        interactor: SendInteractor = DefaultSendInteractor.live,
        rippleService: RippleService = .shared
    ) {
        self.interactor = interactor
        self.rippleService = rippleService
    }

    // MARK: - Fee Calculation

    struct FeeResult {
        let fee: BigInt
        let gas: BigInt
        /// The gas limit the fee was computed against, for EVM. Needed to price
        /// the OP-stack operator fee, which is levied per unit of gas LIMIT
        /// rather than gas used. `nil` off EVM.
        var gasLimit: BigInt? = nil
        /// For a UTXO max send: the recipient amount the plan this fee came from
        /// will actually produce. `nil` everywhere else, where the amount is
        /// re-derived as `balance − fee`.
        ///
        /// A UTXO max send signs `Σ selected inputs − fee`, which is not
        /// `balance − fee` whenever an output was left out of the selection
        /// (dust, unconfirmed, a chain whose balance and UTXO sources differ).
        /// Carrying the planned amount is what keeps the figure Verify confirms
        /// equal to the one that gets signed.
        var maxSendAmountRaw: BigInt? = nil
    }

    func calculateFee(tx: SendTransaction) async throws -> FeeResult {
        if tx.coin.chain.chainType == .EVM {
            return try await calculateEVMFee(tx: tx)
        } else {
            return try await calculateNonEVMFee(tx: tx)
        }
    }

    private func calculateEVMFee(tx: SendTransaction) async throws -> FeeResult {
        // Send-pilot decision 3: thread tx.feeMode through instead of
        // hardcoding .default. The user's custom fee mode chosen in the
        // Details screen is otherwise dropped on Verify refresh.
        let result = try await interactor.calculateEVMFee(SendFeeEstimateRequest(tx: tx))
        return FeeResult(fee: result.fee, gas: result.gas, gasLimit: result.gasLimit)
    }

    private func calculateNonEVMFee(tx: SendTransaction) async throws -> FeeResult {
        let chainSpecific = try await interactor.fetchChainSpecific(tx: tx)

        var fee: BigInt

        switch tx.coin.chain.chainType {
        case .UTXO, .Cardano:
            do {
                // A UTXO max send: take the amount AND the fee off ONE plan, so
                // the summary the user confirms describes the transaction that
                // will be signed. `balance − fee` diverges from it whenever the
                // selection excluded an output.
                if tx.coin.chainType == .UTXO, tx.sendMaxAmount, tx.coin.isNativeToken {
                    let plan = try await interactor.calculateMaxSendPlan(
                        SendChainSpecificRequest(tx: tx),
                        vault: tx.vault,
                        refreshUtxos: true
                    )
                    return FeeResult(fee: plan.fee, gas: plan.fee, maxSendAmountRaw: plan.amount)
                }
                fee = try await interactor.calculatePlanFee(tx: tx, chainSpecific: chainSpecific)
            } catch is CancellationError {
                // A superseded load pass must stay a cancellation — the caller
                // aborts quietly on it and would otherwise show a spurious alert.
                throw CancellationError()
            } catch {
                // The load path reaches the same UTXO builder as the Sign path,
                // so it must speak the same language. Without this it surfaced
                // the raw `localizedDescription` and the identical failure read
                // differently depending on when it happened.
                throw Self.sendFailure(error)
            }

        case .Cosmos, .THORChain:
            // Cosmos batched-claim signs one msg per validator and the
            // resolver scales gas + fee linearly. Mirror that scaling here
            // so the Verify summary and the balance-validation check both
            // reflect the real signed fee, not the single-msg base. Any
            // other staking op is 1 msg → multiplier collapses to 1.
            fee = chainSpecific.fee
            if let payload = tx.cosmosStakingPayload,
               payload.opType == .withdrawRewards,
               let count = payload.validators?.count, count > 1 {
                fee *= BigInt(count)
            }

        default:
            fee = chainSpecific.gas
        }

        return FeeResult(fee: fee, gas: fee)
    }

    // MARK: - Balance Validation

    struct BalanceValidationResult {
        let isValid: Bool
        let errorMessage: String?
    }

    func validateBalanceWithFee(tx: SendTransaction) -> BalanceValidationResult {
        // An XRPL TrustSet's amount is the trust-line LIMIT, not a transfer, so
        // comparing it to the token balance is meaningless — every activation
        // would fail as "balance exceeded" against a zero balance, which is
        // exactly the state a trust line is being opened to leave. What must be
        // affordable is the XRP the operation really costs; that is the async
        // `validateTrustLineReserveIfNeeded`, which reads the live owner reserve.
        // This synchronous pass only rules out the case that needs no network:
        // no XRP coin at all.
        if tx.coin.chain == .ripple, tx.transactionType == .rippleTrustSet {
            guard tx.vault.coins.nativeCoin(chain: .ripple) != nil else {
                // A trust line is an object OWNED BY an XRP account and paid for
                // out of its reserve; without one there is nothing to attach it
                // to and nothing to pay the fee. Fail closed — an absent coin is
                // not a reason to let the ceremony start.
                return BalanceValidationResult(isValid: false, errorMessage: "rippleTrustLineNoXrpAccountError")
            }
            return BalanceValidationResult(isValid: true, errorMessage: nil)
        }

        let amount = tx.amountInRaw
        let balance = tx.coin.balanceRaw
        // TRON staking operations: skip balance validation entirely
        // The balance is already validated in TronFreezeScreen/TronUnfreezeScreen
        // and the user sees the available balance on the screen
        let isTronStaking = tx.coin.chain == .tron && tx.isStakingOperation

        if isTronStaking {
            return BalanceValidationResult(isValid: true, errorMessage: nil)
        }
        if tx.coin.isNativeToken {
            if tx.sendMaxAmount {
                if tx.fee > balance {
                    return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
                }
            } else {
                let totalAmount = amount + tx.fee
                if totalAmount > balance {
                    return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
                }
            }

            // Existential-deposit guard for chains that reap the *sender*
            // (DOT). It signs `transfer_keep_alive`, which fails on-chain
            // after the ceremony if the send would drop the sender below ED.
            // Inert for XRP: its rawBalance is already reserve-net, so the
            // balance checks above are the reserve guard.
            if SendCryptoLogic.canBeReaped(coin: tx.coin, amount: tx.amount, gas: tx.fee) {
                return BalanceValidationResult(isValid: false, errorMessage: "belowExistentialDepositError".localized)
            }

            // Protocol minimum send floor (e.g. Cardano's ~1.4 ADA UTXO): a
            // native send below it is silently dropped by the node. Mirror the
            // Details-screen guard so the ceremony never starts on an amount the
            // node rejects.
            if SendCryptoLogic.isBelowMinimumSendAmount(coin: tx.coin, amount: tx.amount),
               let minimum = tx.coin.chain.minimumSendAmount {
                let minAmount = tx.coin.decimal(for: minimum).description
                return BalanceValidationResult(isValid: false, errorMessage: String(format: "cardanoMinimumSendAmountError".localized, minAmount))
            }
        } else if tx.coin.chain == .terraClassic
                    && TerraClassicTax.isBankDenom(
                        contractAddress: tx.coin.contractAddress,
                        isNativeToken: tx.coin.isNativeToken
                    ) {
            // Terra Classic bank-denom tokens (USTC / uusd) pay their gas + burn
            // tax in the SAME denom they're sending, so the fee comes out of the
            // token balance — not the native LUNC balance. Validate amount + fee
            // against the token balance and skip the native-gas check below.
            // CW20 (terra1…) and IBC (ibc/…) Terra Classic tokens pay the fee in
            // native LUNC, so they fall through to the generic non-native branch.
            let totalAmount = tx.sendMaxAmount ? tx.fee : amount + tx.fee
            if totalAmount > balance {
                return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
            }
        } else {
            if amount > balance {
                return BalanceValidationResult(isValid: false, errorMessage: "walletBalanceExceededError")
            }

            // Cardano native-token sends must fund both the recipient output
            // and the change output at the protocol min-UTXO floor (~1.4 ADA
            // each, Alonzo era), in addition to the fee. Surface a dedicated
            // error when the vault's ADA balance can't cover that.
            if tx.coin.chain == .cardano,
               let nativeToken = tx.vault.coins.nativeCoin(chain: .cardano) {
                let nativeBalance = nativeToken.balanceRaw
                let minAdaReserve = CardanoHelper.defaultMinUTXOValue * 2
                if nativeBalance < tx.fee + minAdaReserve {
                    return BalanceValidationResult(isValid: false, errorMessage: "cardanoOutputBelowMinAda")
                }
            }

            // Validate gas balance for non-native tokens. Decision 2 win:
            // vault is now non-optional, so the singleton fallback is gone.
            if let nativeToken = tx.vault.coins.nativeCoin(chain: tx.coin.chain) {
                let nativeBalance = nativeToken.balanceRaw
                if tx.fee > nativeBalance {
                    let errorMessage = String(format: "insufficientGasTokenError".localized, nativeToken.ticker, tx.coin.ticker)
                    return BalanceValidationResult(isValid: false, errorMessage: errorMessage)
                }
            }
        }

        return BalanceValidationResult(isValid: true, errorMessage: nil)
    }

    // MARK: - UTXO Validation

    func validateUtxosIfNeeded(tx: SendTransaction) async throws {
        try await interactor.validateUtxosIfNeeded(coin: tx.coin)
    }

    // MARK: - Destination Validation

    /// XRPL rejects a Payment that would create the destination account with
    /// less than the base reserve (`tecNO_DST_INSUF_XRP`) — on-chain, after
    /// the keysign ceremony, with the fee burned. Gate it here so the failure
    /// surfaces before signing starts; no-op for every other chain. Matches
    /// the guard the SDK and Android run at submit time.
    ///
    /// ⚠️ The `isNativeToken` gate is deliberate and must NOT be widened to
    /// issued-currency coins. The rule it enforces is "an account is created by
    /// receiving at least the base reserve **in XRP**" — an issued-currency
    /// Payment delivers no XRP at all, so it can neither create the destination
    /// nor satisfy that minimum, and applying the check would reject every token
    /// send to an unfunded account with a message about an XRP amount the
    /// transaction does not carry. A token send to an account that cannot receive
    /// is caught by `validateDestinationTrustLineIfNeeded` instead, which tests
    /// the thing that actually applies: the trust line.
    func validateDestinationIfNeeded(tx: SendTransaction) async throws {
        guard tx.coin.chain == .ripple, tx.coin.isNativeToken else { return }
        do {
            try await rippleService.validateDestinationActivation(
                address: tx.toAddress,
                amountDrops: tx.amountInRaw
            )
        } catch is CancellationError {
            // A cancelled lookup (the screen is tearing down, or the load pass
            // was superseded) must propagate as a cancel — never be rewrapped
            // into a destination error that the load-time guard would surface
            // as a spurious balance error.
            throw CancellationError()
        } catch {
            // The Verify screen's alert plumbing presents only `HelperError`
            // (`error as? HelperError`), so rewrap — same convention as
            // `buildKeysignPayload` — or the guard would block silently.
            throw HelperError.runtimeError(error.localizedDescription)
        }
    }

    /// Pre-ceremony guard for an XRPL issued-currency Payment: the destination
    /// must hold a trust line for the currency, or the Payment fails on-ledger
    /// (`tecPATH_DRY` / `tecNO_LINE`) after the ceremony with the fee burned.
    ///
    /// FAIL OPEN, matching `validateDestinationIfNeeded`: it blocks only on
    /// positive proof the destination cannot receive. A transport failure, a node
    /// error or an unreadable response leaves the send to proceed — a lookup we
    /// couldn't complete must never start blocking a send that worked before this
    /// guard existed.
    ///
    /// No-op for native XRP (which has no trust line) and for a TrustSet (which
    /// has no destination at all).
    func validateDestinationTrustLineIfNeeded(tx: SendTransaction) async throws {
        guard tx.coin.chain == .ripple,
              !tx.coin.isNativeToken,
              tx.transactionType != .rippleTrustSet else {
            return
        }

        let state = await rippleService.destinationTrustLine(
            for: tx.coin.toCoinMeta(),
            destination: tx.toAddress
        )
        // Fail-open means a cancelled lookup answers `.unknown`, exactly like a
        // node error — so the guard would otherwise complete as a successful
        // validation and let a superseded load pass run to the end. Ask the task
        // itself, which is the only thing that can tell the two apart.
        try Task.checkCancellation()
        guard state == .noTrustLine else { return }

        // The Verify screen's alert plumbing presents only `HelperError`, so
        // rewrap — same convention as `validateDestinationIfNeeded`.
        throw HelperError.runtimeError(
            String(format: "xrpDestinationNoTrustLineError".localized, tx.coin.ticker)
        )
    }

    /// Pre-ceremony guard for a TrustSet: spendable XRP must cover the owner
    /// reserve the new trust line locks up PLUS the fee, or the TrustSet fails
    /// on-ledger with `tecINSUFFICIENT_RESERVE` after the ceremony, with the fee
    /// already burned.
    ///
    /// The activation sheet quotes the same figures, but that quote is taken when
    /// the sheet opens. This re-checks at Verify against the freshly loaded
    /// balance and fee, so a balance that moved in between — a concurrent send, a
    /// stale reading, or a `SendTransaction` built somewhere other than the sheet
    /// — cannot walk past it.
    ///
    /// The reserve increment is read LIVE (`server_state` → cache → seed), never
    /// hardcoded, so this and the sheet can never present different arithmetic.
    /// No-op for every non-TrustSet transaction.
    func validateTrustLineReserveIfNeeded(tx: SendTransaction) async throws {
        guard tx.coin.chain == .ripple, tx.transactionType == .rippleTrustSet else { return }

        guard let nativeToken = tx.vault.coins.nativeCoin(chain: .ripple) else {
            throw HelperError.runtimeError("rippleTrustLineNoXrpAccountError".localized)
        }

        // `fetchReserveValues` collapses every failure it can recover from into
        // `nil` (its own live → cache → seed chain) and rethrows ONLY
        // cancellation. `try?` would erase that one distinction and let a
        // cancelled pass carry on to a seeded verdict — which, landing after a
        // newer pass, writes `hasBalanceError` and leaves a spurious banner
        // blocking Sign. Propagate instead, the way `validateDestinationIfNeeded`
        // does, so the caller's cancellation branch aborts the whole load.
        let reserveValues: RippleReserveValues?
        do {
            reserveValues = try await rippleService.fetchReserveValues()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            reserveValues = nil
        }
        // `reserve_base` is excluded: the account already exists and already
        // meets it. What this operation adds is exactly one owner increment.
        let ownerReserve = RippleReserve.reservedDrops(
            ownerCount: 1,
            reserveBase: 0,
            reserveInc: reserveValues?.reserveInc
        )
        // The XRP balance is already reserve-net, so it is what can actually be
        // locked up and spent.
        let spendable = nativeToken.balanceRaw
        let required = ownerReserve + tx.fee
        guard spendable >= required else {
            throw HelperError.runtimeError(
                String(
                    format: "rippleTrustLineInsufficientXrpError".localized,
                    RippleReserve.xrpAmount(drops: required)
                )
            )
        }
    }

    // MARK: - Fee-shortfall amount adjustment

    /// True when the balance covers the amount but not the amount PLUS the fee.
    /// That is the one shape Verify can rescue by clamping the amount down,
    /// instead of dead-ending on an error whose only answer is to go back and
    /// retype a number the user has no way to compute.
    ///
    /// Deliberately narrow:
    /// - **Native coins only.** A token send pays gas out of the native sibling,
    ///   so the token balance is never what the fee overruns.
    /// - **Not a MAX send.** That amount is already re-derived from the fee a
    ///   few lines earlier; clamping it twice would just fight itself.
    /// - **Plain transfers only.** A stake, a bond, an unbond, an XRPL TrustSet
    ///   limit or a function call carries an amount that means something other
    ///   than "how much to move" — quietly reducing it would change the
    ///   operation rather than make it affordable. A memo is enough to
    ///   disqualify a send on its own: on EVM the memo IS the calldata, so the
    ///   amount is a contract call's `msg.value` and not a transfer at all, and
    ///   elsewhere a memo is what tells a protocol how to interpret the deposit.
    ///   The send this issue is about carries none of that.
    /// - **The amount alone has to fit.** If the user asked to send more than
    ///   they hold, the fee is not what went wrong and the error is the honest
    ///   answer. Clamping there would silently replace the send they asked for
    ///   with a different one.
    static func hasFeeOnlyShortfall(tx: SendTransaction) -> Bool {
        guard tx.coin.isNativeToken,
              !tx.sendMaxAmount,
              !tx.isStakingOperation,
              tx.transactionType == .unspecified,
              tx.memo.isEmpty,
              tx.memoFunctionDictionary.isEmpty,
              tx.wasmContractPayload == nil,
              tx.cosmosStakingPayload == nil,
              tx.solanaStakingPayload == nil else {
            return false
        }

        let balance = tx.coin.balanceRaw
        let amount = tx.amountInRaw
        return amount <= balance && amount + tx.fee > balance
    }

    /// What to fall back to when the fee is what pushed the send past the
    /// balance: the very same `balance − fee − ED − extraReserve` the MAX path
    /// derives. Sharing it is the point — a DOT clamp keeps reserving the
    /// existential deposit, and an OP-stack clamp keeps reserving the L1 data
    /// and operator fees op-geth bills on top of gas.
    ///
    /// `nil` when there is nothing safe to fall back TO: the clamp landed at or
    /// below zero (the balance cannot even fund its own fee — a zero-value send
    /// is not a rescue), or it somehow came out no smaller than what was asked
    /// for (this only ever adjusts DOWNWARD). Both leave the existing balance
    /// error standing.
    static func feeShortfallAdjustedAmountRaw(tx: SendTransaction, extraReserve: BigInt) -> BigInt? {
        guard hasFeeOnlyShortfall(tx: tx) else { return nil }

        let candidate = SendCryptoLogic.verifyMaxCandidateRaw(
            coin: tx.coin,
            fee: tx.fee,
            previousAmountRaw: tx.amountInRaw,
            extraReserve: extraReserve
        )
        guard candidate > 0, candidate < tx.amountInRaw else { return nil }
        return candidate
    }

    // MARK: - EVM balance-derived amount re-fit

    /// True for a send whose value the APP derived from the balance rather than
    /// the user typing it: a native EVM MAX, or a native EVM amount Verify
    /// adjusted down to what the balance could actually fund. Both settle at
    /// `balance − fee`, so both stop being affordable the moment the fee moves
    /// between the Verify quote and the payload build — which is exactly when
    /// the signed value has to be re-fitted.
    ///
    /// Token sends move the whole token balance and pay gas from the native
    /// sibling, so a native fee that moved cannot underfund them. And a typed
    /// amount the app never touched is the user's number: it must never be
    /// rewritten, however close to the balance it sits.
    static func needsEVMBalanceRefit(tx: SendTransaction) -> Bool {
        (tx.sendMaxAmount || tx.amountWasAutoAdjusted)
            && tx.coin.isNativeToken
            && tx.coin.chainType == .EVM
    }

    /// Headroom a native send whose amount came from the balance has to leave on
    /// OP-stack rollups, where op-geth checks
    /// `value + gasLimit × maxFeePerGas + l1Cost + operatorCost` against the
    /// balance — a MAX, or an amount Verify adjusted down to fit the fee.
    /// `.zero` for token sends, whose gas comes out of the native sibling rather
    /// than the amount being sent, and for every chain that charges neither term.
    func opStackFeeReserve(tx: SendTransaction, gasLimit: BigInt?) async -> BigInt {
        guard tx.coin.isNativeToken else { return .zero }
        return await interactor.fetchOpStackFeeReserve(coin: tx.coin, memo: tx.memo, gasLimit: gasLimit)
    }

    // MARK: - Keysign Payload

    /// Memo slot of the keysign payload. XRP populates it per the send the
    /// initiator built (the tag rides the first-class field via
    /// `dualWritingRippleTag`):
    /// - a genuine text memo (tag+memo combo, or memo-only) rides the slot as
    ///   the on-chain memo;
    /// - a tag-only send ECHOES the tag's canonical uint32 decimal into the
    ///   slot, so a legacy memo-only co-signer rebuilds the identical tagged
    ///   payment (byte-parity);
    /// - otherwise nil.
    static func payloadMemo(tx: SendTransaction) -> String? {
        if tx.coin.chain == .ripple {
            if !tx.memo.isEmpty {
                return tx.memo
            }
            if let tag = tx.destinationTag {
                return String(tag)
            }
            return nil
        }
        return tx.memo.isEmpty ? nil : tx.memo
    }

    /// Dual-write half of the destination-tag rollout: set the first-class
    /// `RippleSpecific.destination_tag` field from the resolved tag. For a
    /// tag-only send the memo slot echoes the same value (`payloadMemo`); for a
    /// tag+memo combo the field holds the tag while the memo slot holds the
    /// text; a `nil` tag leaves the field unset, keeping memo-only sends
    /// byte-identical for co-signers that don't read the field. No-op for
    /// non-Ripple.
    ///
    /// `transactionType` rides the same seam because it answers a different
    /// question about the same payload — WHICH XRPL operation to build. A
    /// non-native Ripple coin alone cannot distinguish "open a trust line"
    /// (TrustSet, amount = limit) from "send this token" (Payment with a
    /// `CurrencyAmount`), so the discriminator has to be on the wire. Passing
    /// `.unspecified` (the default) leaves the field off the wire, so native XRP
    /// and pre-existing flows produce byte-identical payloads.
    /// The only XRPL operation discriminator this flow is allowed to put on the
    /// wire. `SendTransaction.transactionType` is a shared field other chains
    /// populate with their own operations (`tonDeposit`, `thorMerge`, …); a
    /// value like that leaking into `RippleSpecific.transaction_type` would tell
    /// every co-signer something untrue about the XRPL operation. Narrow it to
    /// the one XRPL value, so anything else — including a future enum case this
    /// build predates — falls back to `.unspecified` and keeps the legacy
    /// interpretation.
    static func rippleTransactionType(tx: SendTransaction) -> VSTransactionType {
        tx.transactionType == .rippleTrustSet ? .rippleTrustSet : .unspecified
    }

    static func dualWritingRippleTag(
        _ chainSpecific: BlockChainSpecific,
        tag: UInt32?,
        transactionType: VSTransactionType = .unspecified
    ) -> BlockChainSpecific {
        guard case .Ripple(let sequence, let gas, let lastLedgerSequence, _, _) = chainSpecific else {
            return chainSpecific
        }
        return .Ripple(
            sequence: sequence,
            gas: gas,
            lastLedgerSequence: lastLedgerSequence,
            destinationTag: tag,
            transactionType: transactionType.rawValue
        )
    }

    func buildKeysignPayload(tx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        do {
            var chainSpecific = try await interactor.fetchChainSpecific(tx: tx)

            // Dual-write the resolved destination tag into the first-class
            // RippleSpecific field. The memo slot now legitimately carries a
            // real on-chain memo (tag+memo combo, or memo-only), so it is no
            // longer re-validated as a tag here — the tag rides the field, and
            // the signing helper (running on every device, initiator included)
            // is the ultimate gate on the tag/memo pair.
            let memo = Self.payloadMemo(tx: tx)
            if tx.coin.chain == .ripple {
                chainSpecific = Self.dualWritingRippleTag(
                    chainSpecific,
                    tag: tx.destinationTag,
                    transactionType: Self.rippleTransactionType(tx: tx)
                )
            }

            // An amount the app derived from the balance — a native EVM MAX, or
            // one Verify adjusted down to fit the fee — is `balance − fee`, and
            // the fee it was derived from is NOT the one in `chainSpecific`
            // above: that is a second, independent reading of the fee market.
            // Re-fit the value to the fee the payload actually carries, or the
            // node rejects the send for the difference once the ceremony has
            // already run.
            let amount = try await balanceRefittedAmount(tx: tx, chainSpecific: chainSpecific)

            let basePayload = try await interactor.buildKeysignPayload(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: amount,
                memo: memo,
                chainSpecific: chainSpecific,
                wasmExecuteContractPayload: tx.wasmContractPayload,
                vault: vault
            )

            try await assertPlanMatchesDisplayed(tx: tx, payload: basePayload)

            // Cosmos staking branch — when the per-flow builder produced a
            // `cosmosStakingPayload`, swap the base payload's `signData` for
            // a freshly-resolved `.signDirect(...)` carrying the proto-encoded
            // MsgDelegate / MsgUndelegate / MsgBeginRedelegate /
            // MsgWithdrawDelegatorReward bytes. The SignDoc is the contract
            // the peer device sees; everything else on `KeysignPayload`
            // becomes descriptive (verify-summary) only.
            if tx.cosmosStakingPayload != nil {
                let signDirect = try CosmosStakingSignDataResolver.resolve(
                    sendTransaction: tx,
                    chainSpecific: chainSpecific
                )
                return basePayload.withSignData(.signDirect(signDirect))
            }

            // Solana native-staking branch — the per-flow builder produced a
            // `solanaStakingPayload`. Build the unsigned delegate transaction
            // once (pinning the recent blockhash + derived stake-account
            // address) and relay it via `signData = .signSolana`. The local-only
            // `solanaStakingPayload` is also attached so the verify summary and
            // the initiator's helper have the intent, but byte parity rides the
            // relayed raw bytes — peer devices sign those without the payload.
            if let solanaStakingPayload = tx.solanaStakingPayload {
                let payloadWithStaking = basePayload.withSolanaStakingPayload(solanaStakingPayload)
                let signSolana = try await SolanaStakingVerifyResolver.resolve(
                    payload: solanaStakingPayload,
                    basePayload: payloadWithStaking,
                    coin: tx.coin
                )
                return payloadWithStaking.withSignData(.signSolana(signSolana))
            }

            return basePayload

        } catch is CancellationError {
            // Matches the convention the destination guards above already
            // follow: a cancelled build is not a failure to report. Wrapping it
            // into a `HelperError` would raise an alert on a screen that is
            // tearing down, or on a pass a newer one has already superseded.
            throw CancellationError()
        } catch {
            throw Self.sendFailure(error)
        }
    }

    /// The value to sign, given the chain-specific the payload is being built
    /// from. Passes a typed amount through untouched; re-derives a native EVM
    /// amount the app took from the balance against `chainSpecific`'s own
    /// `gasLimit × maxFeePerGas` plus the OP-stack L1 data fee, clamping down
    /// only.
    ///
    /// Throws rather than signing when nothing is left after the fee: a send the
    /// balance cannot fund is a rejected broadcast, and refusing it here costs
    /// the user nothing where discovering it after the ceremony costs a signing
    /// round.
    private func balanceRefittedAmount(
        tx: SendTransaction,
        chainSpecific: BlockChainSpecific
    ) async throws -> BigInt {
        guard Self.needsEVMBalanceRefit(tx: tx) else { return tx.amountInRaw }

        let amount = SendCryptoLogic.evmMaxSendAmountRaw(
            coin: tx.coin,
            displayedAmountRaw: tx.amountInRaw,
            signedFee: chainSpecific.fee,
            extraReserve: await opStackFeeReserve(tx: tx, gasLimit: chainSpecific.gasLimit)
        )
        guard amount > 0 else {
            throw HelperError.runtimeError("walletBalanceExceededError")
        }
        return amount
    }

    /// Closes the display/sign gap on the one path where the signed amount is
    /// not fixed by the form.
    ///
    /// A UTXO max send signs `Σ selected inputs − fee`, so the transaction is
    /// defined by the input set at *build* time — and `validateUtxosIfNeeded`
    /// deliberately refetches that set moments before the payload is built. If
    /// an output confirmed (or arrived) since the Verify screen planned what it
    /// displayed, the ceremony would sign a larger amount and a larger fee than
    /// the user approved. Refuse rather than sign it, and let them review the
    /// updated figures.
    ///
    /// Only max sends are gated: every other send pins its recipient amount in
    /// the payload, so a changed input set can move the fee but never the amount.
    private func assertPlanMatchesDisplayed(tx: SendTransaction, payload: KeysignPayload) async throws {
        guard tx.sendMaxAmount, tx.coin.chainType == .UTXO, tx.coin.isNativeToken else { return }
        guard let outcome = try await interactor.plannedOutcome(for: payload) else { return }
        guard outcome.amount == tx.amountInRaw, outcome.fee == tx.fee else {
            throw HelperError.runtimeError("maxSendPlanChangedError".localized)
        }
    }

    /// Maps a send-build failure onto the message the Verify screen presents.
    ///
    /// The screen's alert plumbing only presents `HelperError`, so everything is
    /// rewrapped. Shared by the Sign path (`buildKeysignPayload`) and the
    /// fee-load path (`calculateNonEVMFee`) so the same underlying failure can
    /// never read two different ways depending on which one hit it first.
    ///
    /// `UTXOTransactionPlanError` needs no case here: it is a `LocalizedError`,
    /// so the default branch already yields its own mapped message.
    static func sendFailure(_ error: Error) -> HelperError {
        let errorMessage: String
        switch error {
        case KeysignPayloadFactory.Errors.notEnoughUTXOError:
            errorMessage = NSLocalizedString("notEnoughUTXOError", comment: "")
        case KeysignPayloadFactory.Errors.utxoTooSmallError:
            errorMessage = NSLocalizedString("utxoTooSmallError", comment: "")
        case KeysignPayloadFactory.Errors.utxoSelectionFailedError:
            errorMessage = NSLocalizedString("utxoSelectionFailedError", comment: "")
        case KeysignPayloadFactory.Errors.notEnoughBalanceError:
            errorMessage = NSLocalizedString("notEnoughBalanceError", comment: "")
        default:
            errorMessage = error.localizedDescription
        }
        return HelperError.runtimeError(errorMessage)
    }
}
