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
        var gasLimit: BigInt?
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
            fee = try await interactor.calculatePlanFee(tx: tx, chainSpecific: chainSpecific)

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
        let balance = tx.coin.rawBalance.toBigInt(decimals: tx.coin.decimals)
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
                let nativeBalance = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
                let minAdaReserve = CardanoHelper.defaultMinUTXOValue * 2
                if nativeBalance < tx.fee + minAdaReserve {
                    return BalanceValidationResult(isValid: false, errorMessage: "cardanoOutputBelowMinAda")
                }
            }

            // Validate gas balance for non-native tokens. Decision 2 win:
            // vault is now non-optional, so the singleton fallback is gone.
            if let nativeToken = tx.vault.coins.nativeCoin(chain: tx.coin.chain) {
                let nativeBalance = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
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
        let spendable = nativeToken.rawBalance.toBigInt(decimals: nativeToken.decimals)
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

    // MARK: - EVM max-send clamp

    /// True for the one send whose value is derived from the balance rather than
    /// typed by the user: a native EVM MAX. Its amount is `balance − fee`, so it
    /// is the only case where a fee that moved between the Verify quote and the
    /// payload build makes the signed value unaffordable. Token sends move the
    /// whole token balance and pay gas from the native sibling; a typed amount
    /// is the user's number and must never be rewritten.
    static func needsEVMMaxClamp(tx: SendTransaction) -> Bool {
        tx.sendMaxAmount && tx.coin.isNativeToken && tx.coin.chainType == .EVM
    }

    /// Headroom a native MAX send has to leave on OP-stack rollups, where
    /// op-geth checks `value + gasLimit × maxFeePerGas + l1Cost + operatorCost`
    /// against the balance. `.zero` for token sends, whose gas comes out of the
    /// native sibling rather than the amount being sent, and for every chain
    /// that charges neither term.
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

            // A native EVM MAX is `balance − fee`, and the fee it was derived
            // from is NOT the one in `chainSpecific` above — that is a second,
            // independent reading of the fee market. Re-fit the value to the
            // fee the payload actually carries, or the node rejects the send
            // for the difference once the ceremony has already run.
            let amount = try await clampedMaxSendAmount(tx: tx, chainSpecific: chainSpecific)

            let basePayload = try await interactor.buildKeysignPayload(
                coin: tx.coin,
                toAddress: tx.toAddress,
                amount: amount,
                memo: memo,
                chainSpecific: chainSpecific,
                wasmExecuteContractPayload: tx.wasmContractPayload,
                vault: vault
            )

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

        } catch {
            // Handle UTXO-specific errors with more user-friendly messages
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
            throw HelperError.runtimeError(errorMessage)
        }
    }

    /// The value to sign, given the chain-specific the payload is being built
    /// from. Passes a typed amount through untouched; re-derives a native EVM
    /// MAX against `chainSpecific`'s own `gasLimit × maxFeePerGas` plus the
    /// OP-stack L1 data fee, clamping down only.
    ///
    /// Throws rather than signing when nothing is left after the fee: a send the
    /// balance cannot fund is a rejected broadcast, and refusing it here costs
    /// the user nothing where discovering it after the ceremony costs a signing
    /// round.
    private func clampedMaxSendAmount(
        tx: SendTransaction,
        chainSpecific: BlockChainSpecific
    ) async throws -> BigInt {
        guard Self.needsEVMMaxClamp(tx: tx) else { return tx.amountInRaw }

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
}
