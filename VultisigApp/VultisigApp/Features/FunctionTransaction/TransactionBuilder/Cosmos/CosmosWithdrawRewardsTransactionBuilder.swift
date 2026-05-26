//
//  CosmosWithdrawRewardsTransactionBuilder.swift
//  VultisigApp
//
//  Per-flow builder for LUNA / LUNC `MsgWithdrawDelegatorReward`. Carries
//  a `[String]` of validator operator addresses; the SignDoc resolver
//  emits one `MsgWithdrawDelegatorReward` per validator and packs them
//  into a single TxBody — atomic multi-msg signed in one MPC ceremony.
//
//  No amount field — `MsgWithdrawDelegatorReward` doesn't carry a Coin.
//  The verify-overview row surfaces the *expected* reward total via the
//  view-model so the user knows what they're claiming.
//

import Foundation
import VultisigCommonData

struct CosmosWithdrawRewardsTransactionBuilder: TransactionBuilder {
    let coin: Coin
    let validatorAddresses: [String]

    /// No amount on `MsgWithdrawDelegatorReward`; we still surface the
    /// expected reward total in the verify summary via the view-model,
    /// not via the builder's `amount`. Empty string keeps the legacy
    /// `FunctionCallForm` round-trip safe — but we bypass that path
    /// entirely for staking flows in `FunctionTransactionScreen.onVerify`.
    var amount: String { "" }
    var sendMaxAmount: Bool { false }

    var memo: String { "" }

    var memoFunctionDictionary: ThreadSafeDictionary<String, String> {
        ThreadSafeDictionary<String, String>()
    }

    var transactionType: VSTransactionType { .unspecified }
    var wasmContractPayload: WasmExecuteContractPayload? { nil }
    /// For the verify-screen "destination" we surface the first validator;
    /// the full list lives in `cosmosStakingPayload.validators`.
    var toAddress: String { validatorAddresses.first ?? "" }

    /// Always return a staking payload — including for an empty validator
    /// list — so `isStakingOperation` stays true downstream. The resolver
    /// surfaces a precise `noValidatorsToClaim` error from there; returning
    /// nil here would route the tx to the generic non-staking path and
    /// hide the real reason it failed.
    var cosmosStakingPayload: CosmosStakingPayload? {
        let denom = (try? CosmosStakingConfig.bondDenom(for: coin.chain)) ?? ""
        return CosmosStakingPayload.withdrawRewards(
            validators: validatorAddresses,
            denom: denom
        )
    }
}
