//
//  CosmosGasEstimator.swift
//  VultisigApp
//
//  Initiator-side dynamic gas estimation for Cosmos native sends.
//

import Foundation
import OSLog
import WalletCore
import VultisigCommonData

private let logger = Logger(subsystem: "com.vultisig.app", category: "cosmos-gas-estimator")

/// Simulates a Cosmos native send via `/cosmos/tx/v1beta1/simulate` and derives
/// a padded gas limit the initiator relays to co-signers in
/// `CosmosSpecific.gas_limit`. Every method fails closed: a thrown error / nil
/// return makes the caller fall back to the static per-chain gas limit, so
/// simulation never blocks signing.
enum CosmosGasEstimator {
    /// The node's reported `gas_used` is a tight lower bound; pad it so the tx
    /// can't run out of gas on-chain due to execution nondeterminism. 1.3×
    /// matches the cosmjs default multiplier.
    static let safetyMultiplier: Decimal = 1.3

    /// `ceil(gasUsed × multiplier)`.
    static func scaledGasLimit(gasUsed: UInt64, multiplier: Decimal = safetyMultiplier) -> UInt64 {
        let scaled = Decimal(gasUsed) * multiplier
        var input = scaled
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .up)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }

    /// Build the base64 `tx_bytes` (protobuf `TxRaw`) for a native bank send,
    /// carrying a dummy signature. The simulate endpoint decodes this and skips
    /// signature verification, so the bogus signature is accepted. Only models a
    /// native `MsgSend` — callers must restrict simulation to native sends.
    static func buildSimulateTxBytes(
        chain: Chain,
        hexPublicKey: String,
        fromAddress: String,
        toAddress: String,
        amount: String,
        memo: String? = nil,
        accountNumber: UInt64,
        sequence: UInt64
    ) throws -> String {
        let config = try CosmosHelperConfig.getConfig(forChain: chain)
        guard let pubKeyData = Data(hexString: hexPublicKey) else {
            throw HelperError.runtimeError("simulate: invalid hex public key")
        }

        let input = CosmosSigningInput.with {
            $0.publicKey = pubKeyData
            $0.signingMode = .protobuf
            $0.chainID = config.coinType.chainId
            $0.accountNumber = accountNumber
            $0.sequence = sequence
            $0.mode = .sync
            // A non-empty memo grows the tx body, which the node charges gas
            // for. Include it so the simulated gas matches the real send.
            if let memo, !memo.isEmpty {
                $0.memo = memo
            }
            // Simulate ignores the fee, but the tx must still be well-formed.
            // `WalletCore.` disambiguates from the SignData model `CosmosFee`.
            $0.fee = WalletCore.CosmosFee.with {
                $0.gas = config.gasLimit
                $0.amounts = [CosmosAmount.with {
                    $0.denom = config.denom
                    $0.amount = "1"
                }]
            }
            $0.messages = [WalletCore.CosmosMessage.with {
                $0.sendCoinsMessage = WalletCore.CosmosMessage.Send.with {
                    $0.fromAddress = fromAddress
                    $0.toAddress = toAddress
                    $0.amounts = [CosmosAmount.with {
                        $0.denom = config.denom
                        $0.amount = amount
                    }]
                }
            }]
        }

        let inputData = try input.serializedData()
        let preImage = TransactionCompiler.preImageHashes(coinType: config.coinType, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: preImage)
        guard preSigningOutput.errorMessage.isEmpty else {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }

        // The node skips sig verification in simulate mode, so a fixed 64-byte
        // dummy compact signature is sufficient to assemble a decodable TxRaw.
        let dummySignature = Data(repeating: 0x01, count: 64)
        let signatures = DataVector()
        signatures.add(data: dummySignature)
        let publicKeys = DataVector()
        publicKeys.add(data: pubKeyData)

        let compiled = TransactionCompiler.compileWithSignatures(
            coinType: config.coinType,
            txInputData: inputData,
            signatures: signatures,
            publicKeys: publicKeys
        )
        let output = try CosmosSigningOutput(serializedBytes: compiled)
        // WalletCore may set a non-fatal errorMessage for the dummy signature
        // while still emitting usable tx_bytes (the real signing path tolerates
        // this too), so treat a missing/empty tx_bytes — surfaced by the parser
        // — as the real failure signal rather than errorMessage.
        return try CosmosSerializedParser.parse(output.serialized).txBytes
    }

    /// Simulate the native send and return a padded gas limit, or nil on any
    /// failure (caller falls back to the static per-chain limit).
    static func estimateGasLimit(
        chain: Chain,
        hexPublicKey: String,
        fromAddress: String,
        toAddress: String,
        amount: String,
        memo: String? = nil,
        accountNumber: UInt64,
        sequence: UInt64,
        service: CosmosService
    ) async -> UInt64? {
        do {
            let txBytes = try buildSimulateTxBytes(
                chain: chain,
                hexPublicKey: hexPublicKey,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                memo: memo,
                accountNumber: accountNumber,
                sequence: sequence
            )
            let gasUsed = try await service.simulateGas(txBytes: txBytes)
            guard gasUsed > 0 else {
                logger.warning("Cosmos gas simulation returned 0 gas_used on \(chain.rawValue, privacy: .public); falling back to static limit")
                return nil
            }
            return scaledGasLimit(gasUsed: gasUsed)
        } catch {
            logger.warning("Cosmos gas simulation failed on \(chain.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public); falling back to static limit")
            return nil
        }
    }
}
