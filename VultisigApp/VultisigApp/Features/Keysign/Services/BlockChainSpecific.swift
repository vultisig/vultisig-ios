//
//  BlockChainSpecific.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.07.2024.
//

import Foundation
import BigInt
import VultisigCommonData

enum BlockChainSpecific: Codable, Hashable {
    /// `zcashBranchId` is the live ZIP-243 consensus branch id (little-endian
    /// hex, e.g. `30f33754`) fetched at send time for Zcash; nil for every
    /// other UTXO chain and when the RPC was unreachable. Transient: it is NOT
    /// carried by the proto `UTXOSpecific`, so a co-signing device that rebuilds
    /// the payload from proto must repopulate it (see JoinKeysignViewModel)
    /// before signing.
    case UTXO(byteFee: BigInt, sendMaxAmount: Bool, zcashBranchId: String? = nil)
    case Cardano(byteFee: BigInt, sendMaxAmount: Bool, ttl: UInt64)
    case Ethereum(maxFeePerGasWei: BigInt, priorityFeeWei: BigInt, nonce: Int64, gasLimit: BigInt)
    case THORChain(accountNumber: UInt64, sequence: UInt64, fee: UInt64, isDeposit: Bool, transactionType: Int = 0)
    case MayaChain(accountNumber: UInt64, sequence: UInt64, isDeposit: Bool)
    /// `gasLimit` is the relayed dynamic gas limit (proto `CosmosSpecific.gas_limit`)
    /// from a `/cosmos/tx/v1beta1/simulate` estimate. nil means "use the static
    /// per-chain gas limit". It is part of the SignDoc, so every co-signing
    /// device must apply it identically or the MPC signature fails.
    case Cosmos(accountNumber: UInt64, sequence: UInt64, gas: UInt64, transactionType: Int, ibcDenomTrace: CosmosIbcDenomTraceDenomTrace?, gasLimit: UInt64?)
    case Solana(recentBlockHash: String, priorityFee: BigInt, priorityLimit: BigInt, fromAddressPubKey: String?, toAddressPubKey: String?, hasProgramId: Bool) // priority fee is in microlamports
    case Sui(referenceGasPrice: BigInt, coins: [[String: String]], gasBudget: BigInt)
    case Polkadot(recentBlockHash: String, nonce: UInt64, currentBlockNumber: BigInt, specVersion: UInt32, transactionVersion: UInt32, genesisHash: String, gas: BigInt? = nil)
    case Ton(sequenceNumber: UInt64, expireAt: UInt64, bounceable: Bool, sendMaxAmount: Bool, jettonAddress: String = "", isActiveDestination: Bool = false)
    /// `destinationTag` carries the first-class XRPL DestinationTag
    /// (`RippleSpecific.destination_tag`). It is populated at the payload-build
    /// seam alongside the legacy memo carrier (dual-write): the signer prefers
    /// this field and falls back to parsing the memo, so a co-signer that does
    /// not read the field still rebuilds a byte-identical signing input from
    /// the memo. `nil` means "no field present — use the memo".
    case Ripple(sequence: UInt64, gas: UInt64, lastLedgerSequence: UInt64, destinationTag: UInt32? = nil)

    case Tron(
        timestamp: UInt64,
        expiration: UInt64,
        blockHeaderTimestamp: UInt64,
        blockHeaderNumber: UInt64,
        blockHeaderVersion: UInt64,
        blockHeaderTxTrieRoot: String,
        blockHeaderParentHash: String,
        blockHeaderWitnessAddress: String,
        gasFeeEstimation: UInt64
    )

    /// Return a copy with the EVM gas limit replaced. No-op for non-EVM cases
    /// (gas-limit overrides only apply to Ethereum-family swaps). Used to honour
    /// a user-supplied custom gas limit from the swap advanced settings.
    func overridingEVMGasLimit(_ gasLimit: BigInt) -> BlockChainSpecific {
        guard case let .Ethereum(maxFeePerGasWei, priorityFeeWei, nonce, _) = self else {
            return self
        }
        return .Ethereum(
            maxFeePerGasWei: maxFeePerGasWei,
            priorityFeeWei: priorityFeeWei,
            nonce: nonce,
            gasLimit: gasLimit
        )
    }

    var gas: BigInt {
        switch self {
        case .UTXO(let byteFee, _, _):
            return byteFee
        case .Cardano(let byteFee, _, _):
            return byteFee
        case .Ethereum(let maxFeePerGasWei, _, _, _):
            return maxFeePerGasWei
        case .THORChain(_, _, let fee, _, _):
            return fee.description.toBigInt()
        case .MayaChain:
            return MayaChainHelper.MayaChainGas.description.toBigInt() // Maya uses 10e10
        case .Cosmos(_, _, let gas, _, _, _):
            return gas.description.toBigInt()
        case .Solana(_, _, _, let fromAddressPubKey, let toAddressPubKey, _):
            // Include ATA rent when the recipient's associated token account must be
            // created alongside the SPL transfer (sender has an ATA, recipient does not).
            if let from = fromAddressPubKey, !from.isEmpty,
               toAddressPubKey == nil || toAddressPubKey?.isEmpty == true {
                return SolanaHelper.defaultFeeInLamports + SolanaHelper.ataRentLamports
            }
            return SolanaHelper.defaultFeeInLamports
        case .Sui(_, _, let gasBudget):
            return gasBudget
        case .Polkadot(_, _, _, _, _, _, let gas):
            guard let dynamicGas = gas else {
                return 0 // We should throw
            }
            return dynamicGas
        case .Ton:
            return TonHelper.defaultFee
        case .Ripple(_, let gas, _, _):
            return gas.description.toBigInt()
        case .Tron(_, _, _, _, _, _, _, _, let gasFeeEstimation):
            return gasFeeEstimation.description.toBigInt()
        }
    }

    var fee: BigInt {
        switch self {
        case .Ethereum(let maxFeePerGas, _, _, let gasLimit):
            return maxFeePerGas * gasLimit
        case .UTXO:
            return gas // For UTXO, gas represents the byteFee (sats/byte rate), not the total fee
        case .Sui(_, _, let gasBudget):
            return gasBudget // For Sui, return the actual gas budget (total fee estimate)
        case .Cardano, .THORChain, .MayaChain, .Cosmos, .Solana, .Polkadot, .Ton, .Ripple, .Tron:
            return gas
        }
    }

    var gasLimit: BigInt? {
        switch self {
        case .Ethereum(_, _, _, let gasLimit):
            return gasLimit
        case .UTXO, .Cardano, .THORChain, .MayaChain, .Cosmos, .Solana, .Sui, .Polkadot, .Ton, .Ripple, .Tron:
            return nil
        }
    }

    /// Live ZIP-243 branch id carried on a Zcash payload's UTXO specific, or nil
    /// for non-Zcash payloads and when the RPC was unreachable.
    var zcashBranchId: String? {
        guard case .UTXO(_, _, let zcashBranchId) = self else {
            return nil
        }
        return zcashBranchId
    }
}
