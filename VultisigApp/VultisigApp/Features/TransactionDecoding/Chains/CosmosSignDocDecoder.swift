//
//  CosmosSignDocDecoder.swift
//  VultisigApp
//
//  Reads initiator Cosmos staking pre-images or the active SignDoc body sent to
//  a co-signer, never adjacent flat sidecars.
//

import BigInt
import Foundation

struct CosmosSignDocDecoder: TransactionContentDecoder {

    /// Only chains whose signing paths consume Cosmos SignDocs.
    var handles: Set<Chain>? {
        Set(Chain.allCases.filter { $0.chainType == .Cosmos })
    }

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        if let intent = tx.cosmosStakingIntent {
            return decode(intent)
        }

        guard tx.signedDataBodyIsActive,
              case .signDirect(let direct)? = tx.signedData,
              let reading = CosmosSignDocReader.read(bodyBytes: direct.bodyBytes)
        else { return nil }

        return DecodedTransaction(
            operation: reading.operation,
            amount: reading.amount,
            counterparty: reading.counterparty,
            evidence: .signedData
        )
    }

    /// Maps a validated initiator pre-image into the SignDoc vocabulary.
    private func decode(_ intent: CosmosStakingPayload) -> DecodedTransaction? {
        func amount() -> DecodedAmount? {
            guard !intent.denom.isEmpty,
                  let text = intent.amount,
                  let value = BigInt(text),
                  value >= 0
            else { return nil }
            return .units(value, of: .denom(intent.denom))
        }

        switch intent.opType {
        case .delegate:
            guard let validator = intent.validatorAddress, !validator.isEmpty,
                  let amount = amount() else { return nil }
            return DecodedTransaction(
                operation: .delegate,
                amount: amount,
                counterparty: .validator(validator),
                evidence: .structuredPayload
            )

        case .undelegate:
            guard let validator = intent.validatorAddress, !validator.isEmpty,
                  let amount = amount() else { return nil }
            return DecodedTransaction(
                operation: .undelegate,
                amount: amount,
                counterparty: .validator(validator),
                evidence: .structuredPayload
            )

        case .redelegate:
            guard let source = intent.validatorSrcAddress, !source.isEmpty,
                  let destination = intent.validatorDstAddress, !destination.isEmpty,
                  let amount = amount() else { return nil }
            return DecodedTransaction(
                operation: .redelegate,
                amount: amount,
                counterparty: .validator(destination),
                evidence: .structuredPayload
            )

        case .withdrawRewards:
            guard let validators = intent.validators,
                  (1...64).contains(validators.count),
                  validators.allSatisfy({ !$0.isEmpty })
            else { return nil }
            return DecodedTransaction(
                operation: .claimRewards,
                amount: .unstated,
                counterparty: validators.count == 1 ? .validator(validators[0]) : nil,
                evidence: .structuredPayload
            )
        }
    }
}
