//
//  DefiChainScreenModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import BigInt
import Foundation

/// Owns the business logic behind `DefiChainMainScreen`: the governance
/// vote-fee preflight, the compound/index coin mappings, the stake/unstake
/// intent → `FunctionTransactionType` translation, the governance memo/tx
/// builders, and the async coin-add / gas-fetch orchestration. Every method
/// returns a value (a built `SendTransaction`, a `FunctionTransactionType`,
/// a coin, or a bool) — navigation stays in the view, which consumes these
/// and forwards them to `router.navigate`.
@MainActor
final class DefiChainScreenModel: ObservableObject {
    private(set) var vault: Vault
    let chain: Chain

    init(vault: Vault, chain: Chain) {
        self.vault = vault
        self.chain = chain
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    var nativeCoin: Coin? {
        vault.nativeCoin(for: chain)
    }

    // MARK: - Governance vote-fee preflight

    /// Whether the given native coin balance can cover a governance vote's flat
    /// tx fee. A vote is an on-chain tx that costs gas, so a 0/dust-balance user
    /// would otherwise walk verify → ML-DSA keysign only for the broadcast to
    /// fail. We compare the raw balance against the chain's flat `min_tx_fee`
    /// (`CosmosStakingConfig`, the single source of truth for QBTC fee). The
    /// fee is the exact flat floor — `min_gas_price` is 0 on qbtc-testnet, so
    /// gas is free and the fee doesn't vary by message — so this is a precise
    /// pre-flight, not an approximation. Gates both vote entry points and
    /// greys the vote controls with a hint.
    func canCoverVoteFee(nativeCoin: Coin?) -> Bool {
        guard let nativeCoin else { return false }
        guard let feeAmount = try? CosmosStakingConfig.feeAmount(for: chain) else {
            // No fee config for this chain — don't block (non-QBTC fallback).
            return true
        }
        return nativeCoin.rawBalance.toBigInt() >= BigInt(feeAmount)
    }

    // MARK: - Coin mapping

    func stakeCoin(for compoundCoin: CoinMeta) -> CoinMeta {
        switch compoundCoin.ticker.uppercased() {
        case "STCY":
            return TokensStore.tcy
        case "YBRUNE":
            return TokensStore.brune
        case "SRUJI":
            return TokensStore.ruji
        default:
            return compoundCoin
        }
    }

    func coin(for yCoin: CoinMeta) -> CoinMeta {
        let coin: CoinMeta
        switch yCoin {
        case TokensStore.yrune:
            coin = TokensStore.rune
        case TokensStore.ytcy:
            coin = TokensStore.tcy
        default:
            coin = TokensStore.rune
        }
        return coin
    }

    // MARK: - Stake / unstake / transfer intents

    /// Maps a stake action on a position to the function-call transaction the
    /// view should present. TON reuses/initialises its nominator pool; the
    /// other chains route stake / compound / index through their respective
    /// `FunctionTransactionType` cases.
    func stakeTransactionType(for position: StakePosition) -> FunctionTransactionType {
        if position.coin.chain == .ton {
            // Add-more reuses the existing pool; a first-time stake (no pool yet)
            // routes with `nil` so the screen prompts for the pool address.
            return .tonStake(
                coin: position.coin,
                poolAddress: position.poolAddress,
                poolImplementation: position.poolImplementation
            )
        }
        switch position.type {
        case .stake:
            return .stake(coin: position.coin, isAutocompound: false)
        case .compound:
            return .stake(coin: stakeCoin(for: position.coin), isAutocompound: true)
        case .index:
            return .mint(coin: coin(for: position.coin), yCoin: position.coin)
        }
    }

    /// Maps an unstake action to the function-call transaction, or `nil` when the
    /// action is a no-op (a TON unstake with no pool address to unwind).
    func unstakeTransactionType(for position: StakePosition) -> FunctionTransactionType? {
        if position.coin.chain == .ton {
            guard let poolAddress = position.poolAddress, !poolAddress.isEmpty else { return nil }
            return .tonUnstake(
                coin: position.coin,
                poolAddress: poolAddress,
                poolImplementation: position.poolImplementation,
                stakedAmount: position.amount
            )
        }
        switch position.type {
        case .stake:
            return .unstake(
                coin: position.coin,
                isAutocompound: false,
                availableToUnstake: position.availableToUnstake
            )
        case .compound:
            return .unstake(
                coin: stakeCoin(for: position.coin),
                isAutocompound: true,
                availableToUnstake: position.amount
            )
        case .index:
            return .redeem(coin: coin(for: position.coin), yCoin: position.coin)
        }
    }

    /// The vault coin matching a stake position, used to seed the send flow for
    /// a transfer. `nil` when the vault doesn't hold the position's coin.
    func transferCoin(for position: StakePosition) -> Coin? {
        vault.coins.first(where: { $0.toCoinMeta() == position.coin })
    }

    // MARK: - Governance vote builders

    /// Builds a single-option QBTC governance vote tx straight from the
    /// proposal + chosen option for the existing verify → ML-DSA keysign flow.
    /// The memo (`QBTC_VOTE:<OPTION>:<ID>`) is what `QBTCHelper.buildMsgVote`
    /// consumes; the dictionary is display-only so verify reads
    /// "Vote <OPTION> on Proposal #N" rather than the raw memo. Returns `nil`
    /// when there is no native coin or the balance can't cover the vote fee.
    func makeGovernanceVoteTransaction(
        proposal: CosmosGovProposal,
        choice: CosmosGovVoteChoice
    ) -> SendTransaction? {
        guard let nativeCoin, canCoverVoteFee(nativeCoin: nativeCoin) else { return nil }
        let memo = QBTCGovVoteMemo.singleVote(proposalID: proposal.id, choice: choice)
        let displayDictionary: [String: String] = [
            "action": "governanceVoteAction".localized,
            "vote": choice.displayTitle,
            "proposal": String(format: "governanceProposalNumber".localized, String(proposal.id))
        ]
        return SendTransaction.empty(coin: nativeCoin, vault: vault).copy(
            memo: memo,
            transactionType: .vote,
            memoFunctionDictionary: displayDictionary
        )
    }

    /// Builds a weighted QBTC governance vote tx from per-option weights for the
    /// verify → ML-DSA keysign flow. The memo (`QBTC_VOTEW:<ID>:OPT=W,...`) is
    /// what `QBTCHelper.buildMsgVoteWeighted` consumes; weights are passed as
    /// plain decimals and the helper canonicalizes them to the 18-decimal
    /// `cosmos.Dec` form. Returns `nil` when there is no native coin, the
    /// balance can't cover the vote fee, or no options were supplied.
    func makeGovernanceWeightedVoteTransaction(
        proposal: CosmosGovProposal,
        options: [CosmosGovVoteOption]
    ) -> SendTransaction? {
        guard let nativeCoin, canCoverVoteFee(nativeCoin: nativeCoin), !options.isEmpty else { return nil }
        let memo = QBTCGovVoteMemo.weightedVote(proposalID: proposal.id, options: options)
        let displayValue = QBTCGovVoteMemo.weightedDisplayValue(options: options)
        let displayDictionary: [String: String] = [
            "action": "governanceVoteAction".localized,
            "vote": displayValue,
            "proposal": String(format: "governanceProposalNumber".localized, String(proposal.id))
        ]
        return SendTransaction.empty(coin: nativeCoin, vault: vault).copy(
            memo: memo,
            transactionType: .vote,
            memoFunctionDictionary: displayDictionary
        )
    }

    // MARK: - Coin-add / gas-fetch orchestration

    /// Whether presenting the given transaction requires adding one or more of
    /// its coins to the vault first.
    func needsCoinAddition(for type: FunctionTransactionType) -> Bool {
        let vaultCoins = vault.coins.map { $0.toCoinMeta() }
        return type.coins.contains { !vaultCoins.contains($0) }
    }

    /// Adds the transaction's coins to the vault. Only call when
    /// `needsCoinAddition(for:)` is `true`.
    func addCoins(for type: FunctionTransactionType) async throws {
        try await CoinService.addToChain(assets: type.coins, to: vault)
    }

    /// Builds the unsigned tx and pre-fetches the chain-specific gas so Verify
    /// shows the fee immediately. Mirrors `FunctionTransactionScreen.onVerify`:
    /// the gas is re-fetched during Verify anyway, so a fetch failure here is
    /// non-fatal and the un-gassed tx is returned unchanged.
    func buildVerifyTransaction(for builder: TransactionBuilder) async -> SendTransaction {
        var sendTx = builder.buildSendTransaction(vault: vault)
        do {
            let chainSpecific = try await BlockChainService.shared.fetchSpecific(tx: sendTx)
            sendTx = sendTx.copy(gas: chainSpecific.gas)
        } catch {
            // Non-fatal: gas is re-fetched during Verify.
        }
        return sendTx
    }
}
