//
//  SolanaTransactionDecoder.swift
//  VultisigApp
//
//  Reads initiator staking pre-images or the opaque transaction bytes sent to a
//  co-signer. Flat sidecars are never consulted for relayed transactions.
//

import BigInt
import Foundation

struct SolanaTransactionDecoder: TransactionContentDecoder {

    var handles: Set<Chain>? { [.solana] }

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        // Initiators hold the pre-image; co-signers hold its encoded bytes.
        if let intent = tx.stakingIntent {
            return read(intent)
        }

        guard case .signSolana(let solana)? = tx.signedData else { return nil }

        // Multiple relayed transactions have no single operation.
        guard solana.rawTransactions.count == 1,
              let raw = solana.rawTransactions.first,
              let reading = SolanaTransactionReader.read(base64: raw)
        else { return nil }

        return DecodedTransaction(
            operation: reading.operation,
            amount: reading.amount,
            counterparty: reading.counterparty,
            evidence: .signedData
        )
    }
    /// Reads the operation committed by an initiator staking pre-image.
    private func read(_ intent: SolanaStakingPayload) -> DecodedTransaction {
        switch intent.opType {
        case .delegate:
            let amount: DecodedAmount = intent.lamports.map {
                .accountFunding(BigInt($0), of: .chainNative)
            } ?? .unstated
            return DecodedTransaction(
                operation: .delegate,
                amount: amount,
                counterparty: intent.votePubkey.map(DecodedCounterparty.validator),
                evidence: .structuredPayload
            )
        case .unstake:
            // Funds move only on the later withdrawal.
            return DecodedTransaction(
                operation: .unstake,
                amount: .unstated,
                counterparty: intent.stakeAccount.map(DecodedCounterparty.stakeAccount),
                evidence: .structuredPayload
            )
        case .withdraw:
            // Withdraw lamports are the committed quantity.
            let amount: DecodedAmount = intent.lamports.map { .units(BigInt($0), of: .chainNative) } ?? .unstated
            return DecodedTransaction(
                operation: .withdrawStake,
                amount: amount,
                counterparty: intent.stakeAccount.map(DecodedCounterparty.stakeAccount),
                evidence: .structuredPayload
            )
        }
    }

}

/// Converts exact stake-account funding into active stake using the live rent reserve.
struct SolanaDelegatedAmountReader: PositionReading {
    var readRentReserve: () async throws -> UInt64 = {
        try await SolanaStakingService.shared.fetchRentReserve()
    }

    func handles(_ decoded: DecodedTransaction, coin: Coin) -> Bool {
        guard coin.chain == .solana, decoded.operation == .delegate,
              case .accountFunding = decoded.amount else { return false }
        return true
    }

    func amount(for decoded: DecodedTransaction, coin: Coin) async -> HeroCoinAmount? {
        guard case .accountFunding(let funding, .chainNative) = decoded.amount,
              let reserve = try? await readRentReserve(),
              funding > BigInt(reserve) else { return nil }
        return Self.heroAmount(raw: funding - BigInt(reserve), coin: coin)
    }

    fileprivate static func heroAmount(raw: BigInt, coin: Coin) -> HeroCoinAmount? {
        guard raw > 0 else { return nil }
        let amount = coin.decimal(for: raw)
        return HeroCoinAmount(amount: amount, coin: coin)
    }
}

/// Resolves a whole-account deactivate to the exact delegated lamports in that account.
struct SolanaStakeAccountAmountReader: PositionReading {
    var readStakeAccounts: (String) async throws -> [SolanaStakeAccount] = {
        try await SolanaStakingService.shared.fetchStakeAccounts(owner: $0)
    }

    func handles(_ decoded: DecodedTransaction, coin: Coin) -> Bool {
        guard coin.chain == .solana, decoded.operation == .unstake,
              case .stakeAccount = decoded.counterparty else { return false }
        return true
    }

    func amount(for decoded: DecodedTransaction, coin: Coin) async -> HeroCoinAmount? {
        guard case .stakeAccount(let address) = decoded.counterparty,
              let accounts = try? await readStakeAccounts(coin.address),
              let stake = accounts.first(where: { $0.pubkey == address })?.delegation?.stake else {
            return nil
        }
        return SolanaDelegatedAmountReader.heroAmount(raw: BigInt(stake), coin: coin)
    }
}
