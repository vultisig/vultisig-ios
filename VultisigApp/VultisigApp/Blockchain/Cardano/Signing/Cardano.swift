//
//  Cardano.swift
//  VultisigApp
//
//  Created by Enrique Souza on 11.06.2025.
//

import Foundation
import Tss
import WalletCore
import BigInt
import OSLog

private let cardanoLogger = Logger(subsystem: "com.vultisig.app", category: "cardano-helper")

/*
 Cardano UTXO Validation & Send Max Recommendations
 
 This implementation provides comprehensive validation for Cardano transactions with focus on:
 
 1. MINIMUM SEND AMOUNT: ≥ 1.4 ADA (Alonzo era real-world requirement)
 2. SUFFICIENT BALANCE: Balance must cover send amount + fees
 3. CHANGE/TROCO VALIDATION: If change exists, it must be ≥ 1.4 ADA OR exactly 0
 4. SEND MAX RECOMMENDATIONS: Proactively suggest "Send Max" to avoid UTXO issues
 
 Key Benefits:
 - Prevents transaction failures due to invalid change amounts
 - User-friendly error messages with actionable solutions
 - Proactive recommendations for low balance scenarios
 - Follows real-world Cardano Alonzo era requirements (based on transaction evidence)
 
 Example scenarios:
 ✅ Send 2 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 2.83 ADA (valid)
 ✅ Send 3.2 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 1.63 ADA (valid)
 ❌ Send 4.0 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 0.83 ADA (invalid - below 1.4 ADA)
 ✅ Send Max 5 ADA, Balance 5 ADA → WalletCore subtracts fee automatically (valid)
 */

class CardanoHelper {

    /*
     Cardano minimum UTXO value requirement (Alonzo Era) - UPDATED BASED ON REAL EVIDENCE
     Official Alonzo documentation shows:
     - utxoEntrySize = 38 words × coinsPerUTxOWord (34,482) = 1,310,316 lovelace ≈ 1.31 ADA
     - Real-world evidence from transactions shows failures below ~1.4 ADA
     Using conservative 1.4 ADA to prevent transaction failures
     https://cardano-ledger.readthedocs.io/en/latest/explanations/min-utxo-alonzo.html
     */
    static let defaultMinUTXOValue: BigInt = 1_400_000 // 1.4 ADA in lovelaces (real-world tested)

    /// Lovelace floor we attach to the recipient output of a CNT send. Cardano
    /// (Babbage era) requires every output to carry a minimum ADA value that
    /// scales with the bundle's CBOR size; a single-CNT output is typically
    /// ~0.85 ADA, but we use 1.5 ADA to leave headroom and avoid the network
    /// 3125 "insufficiently funded outputs" rejection. Computing the exact
    /// minimum dynamically is a future enhancement — see the `min-ada-dynamic`
    /// note in the wiki spec.
    static let minLovelaceOnTokenOutput: UInt64 = 1_500_000

    /// Decimal places used when a validation message quotes a suggested
    /// "Send Max" amount. ADA carries 6 decimals and `Coin.getMaxValue` fills
    /// the full precision, so the suggestion must quote all 6 — quoting fewer
    /// would advertise a smaller amount than Max actually sends.
    private static let adaDisplayDecimals = 6

    /// Validate Cardano transaction meets UTXO requirements for both send amount and remaining balance
    /// 
    /// Cardano UTXO Validation Rules:
    /// 1. Send amount must be ≥ 1.4 ADA (minUTXO)
    /// 2. Total balance must cover send amount + fees  
    /// 3. If there's change/troco, it must be ≥ 1.4 ADA OR exactly 0 (no change)
    ///
    /// Examples:
    /// - Send 2 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 2.83 ADA ✅ (valid)
    /// - Send 4.0 ADA, Balance 5 ADA, Fee 0.17 ADA → Change 0.83 ADA ❌ (invalid - change < 1.4)
    /// - Send Max 5 ADA, Balance 5 ADA → WalletCore subtracts fee automatically ✅ (valid)
    ///
    /// - Parameters:
    ///   - sendAmount: Amount to send in lovelaces
    ///   - totalBalance: Total available balance in lovelaces  
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    ///   - sendMaxAmount: Whether this is a MAX send (skips fee validation like UTXO chains)
    /// - Returns: Tuple with validation result and error message if any
    static func validateUTXORequirements(sendAmount: BigInt, totalBalance: BigInt, estimatedFee: BigInt, sendMaxAmount: Bool = false) -> (isValid: Bool, errorMessage: String?) {
        let minUTXOValue = defaultMinUTXOValue

        // For MAX sends, only validate that we have enough balance to cover fees
        // The wallet will automatically deduct fees from the total, just like UTXO chains
        if sendMaxAmount {
            if totalBalance <= estimatedFee {
                let availableADA = totalBalance.toADAString
                return (false, "Insufficient balance (\(availableADA) ADA). Balance must be greater than transaction fees.")
            }
            return (true, nil)
        }

        // Regular validation for non-MAX sends
        // 1. Check send amount meets minimum
        if sendAmount < minUTXOValue {
            let minAmountADA = minUTXOValue.toADAString
            return (false, "Minimum send amount is \(minAmountADA) ADA. Cardano requires this to prevent spam.")
        }

        // 2. Check sufficient balance
        let totalNeeded = sendAmount + estimatedFee
        if totalBalance < totalNeeded {
            // Quote the suggested MAX at ADA's full precision, matching getMaxValue.
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: adaDisplayDecimals)
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: adaDisplayDecimals)

            // Recommend Send Max for insufficient balance
            if totalBalance > estimatedFee && totalBalance > 0 {
                return (false, "Insufficient balance. 💡 Try 'Send Max' to send \(totalBalanceADA) ADA instead.")
            } else {
                let availableADA = totalBalance.toADAString
                return (false, "Insufficient balance (\(availableADA) ADA). You need more ADA to complete this transaction.")
            }
        }

        // 3. Check remaining balance (change) meets minimum UTXO requirement
        let remainingBalance = totalBalance - sendAmount - estimatedFee
        if remainingBalance > 0 && remainingBalance < minUTXOValue {
            // Quote the suggested MAX at ADA's full precision, matching getMaxValue.
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: adaDisplayDecimals)
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: adaDisplayDecimals)

            // Always recommend Send Max for change issues - simplest solution
            return (false, "This amount would leave too little change. 💡 Try 'Send Max' (\(totalBalanceADA) ADA) to avoid this issue.")
        }

        return (true, nil)
    }

    /// Check if balance is low and should recommend "Send Max" to avoid UTXO issues
    /// - Parameters:
    ///   - totalBalance: Total available balance in lovelaces
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    /// - Returns: Tuple indicating if balance is low and recommendation message
    static func shouldRecommendSendMax(totalBalance: BigInt, estimatedFee: BigInt) -> (shouldRecommend: Bool, message: String?) {

        // Balance is considered "low" if total balance is less than 3.5 ADA
        // This helps avoid change issues with the 1.4 ADA minimum
        let lowBalanceThreshold: BigInt = 3_500_000 // 3.5 ADA in lovelaces

        if totalBalance <= lowBalanceThreshold && totalBalance > estimatedFee {
            // Quote the suggested MAX at ADA's full precision, matching getMaxValue.
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: adaDisplayDecimals)
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: adaDisplayDecimals)

            return (true, "💡 Low balance detected. Consider 'Send Max' (\(totalBalanceADA) ADA) to avoid change issues.")
        }

        return (false, nil)
    }

    /// Display fee for the Verify screen. Returns `chainSpecific.byteFee`, which
    /// the initiator now populates with the real size-based fee
    /// (`minFeeA*size + minFeeB`, via `estimateDynamicByteFee`). Every co-signer
    /// forces this exact value into the body, so the displayed fee equals what
    /// is actually signed.
    static func calculateDynamicFee(keysignPayload: KeysignPayload) throws -> BigInt {
        guard case .Cardano(let byteFee, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Cardano chain specific parameters")
        }
        return byteFee
    }

    // MARK: - Helper Functions

    /// Build a WalletCore `CardanoSigningInput`. For CNT sends, per-UTxO
    /// token data is read off the wire from `keysignPayload.utxos[i].cardanoTokens`
    /// (populated by the initiator in `KeysignPayloadFactory.selectCardanoUTXOs`).
    /// Both MPC peers consume identical input bytes — no per-device Koios fetch.
    static func getPreSignedInputData(
        keysignPayload: KeysignPayload
    ) throws -> CardanoSigningInput {
        guard keysignPayload.coin.chain == .cardano else {
            throw HelperError.runtimeError("coin is not ADA")
        }

        guard case .Cardano(let byteFee, let sendMaxAmount, let ttl) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Cardano chain specific parameters")
        }

        guard AnyAddress(string: keysignPayload.toAddress, coin: .cardano) != nil else {
            throw HelperError.runtimeError("fail to get to address: \(keysignPayload.toAddress)")
        }

        let tokenBundle: CardanoTokenBundle? = try makeTokenBundle(for: keysignPayload)

        // `useMaxAmount` is an ADA-only flag — it tells the signer to drain
        // every input lovelace (minus fee) into the recipient output. For
        // CNT sends the user's "Send Max" toggle means "send all the token",
        // and the lovelace floor is fixed at min-UTxO; never set this for
        // token sends.
        var safeGuardMaxAmount = false
        if tokenBundle == nil,
           let rawBalance = Int64(keysignPayload.coin.rawBalance),
           sendMaxAmount,
           rawBalance > 0,
           rawBalance == Int64(keysignPayload.toAmount) {
            safeGuardMaxAmount = true
        }

        // `transferMessage.amount` is the lovelace value of the recipient
        // output. For an ADA-only send it's the user-typed amount. For a CNT
        // send the user-typed amount is denominated in the token's base units
        // (e.g. 665000 = 0.665 USDM), NOT lovelace — passing it here would
        // produce an output below Cardano's min-UTxO floor and the network
        // rejects it with code 3125. Use a conservative floor instead.
        let recipientLovelace: UInt64 = tokenBundle == nil
            ? UInt64(keysignPayload.toAmount)
            : Self.minLovelaceOnTokenOutput

        // CIP-20 memo (label 674). When present, WalletCore commits
        // blake2b-256(auxDataCbor) into the body at map key 7 and emits the
        // aux CBOR as element [3] of the signed tx. The encoder is byte-parity
        // pinned to the SDK golden vector so co-signers agree on the sighash.
        let auxDataCbor = cip20AuxData(for: keysignPayload)

        // `byteFee` is a SHARED payload constant: the initiator computes a real
        // size-based fee once (see `CardanoHelper.estimateDynamicByteFee`) and
        // every co-signing device forces that exact value here. Seeding a
        // non-zero `forceFee` before `AnySigner.plan(...)` makes WalletCore's
        // Cardano `doPlan()` honor it verbatim, so `plan.fee == byteFee` and the
        // body carries the same fee on every device — guaranteeing Blake2b
        // sighash parity across iOS/Windows/Android regardless of any per-device
        // planner differences. This matches the SDK resolver, which forces
        // `byteFee` the same way.
        var input = CardanoSigningInput.with {
            $0.transferMessage = CardanoTransfer.with {
                $0.toAddress = keysignPayload.toAddress
                $0.changeAddress = keysignPayload.coin.address
                $0.amount = recipientLovelace
                $0.useMaxAmount = safeGuardMaxAmount
                $0.forceFee = UInt64(byteFee)
                if let tokenBundle {
                    $0.tokenAmount = tokenBundle
                }
            }
            $0.ttl = ttl
            if let auxDataCbor {
                $0.auxiliaryData = auxDataCbor
            }
        }

        // Add UTXOs to the input. Per-UTXO token data is carried on the wire
        // (`UtxoInfo.cardanoTokens`), populated by the initiator before keysign.
        // Without this, WalletCore's planner can't reconcile a TokenBundle
        // output against the inputs and trips `errorLowBalance`.
        for inputUtxo in keysignPayload.utxos {
            let utxo = CardanoTxInput.with {
                $0.outPoint = CardanoOutPoint.with {
                    $0.txHash = Data(hexString: inputUtxo.hash)!
                    $0.outputIndex = UInt64(inputUtxo.index)
                }
                $0.amount = UInt64(inputUtxo.amount)
                $0.address = keysignPayload.coin.address
                if !inputUtxo.cardanoTokens.isEmpty {
                    $0.tokenAmount = inputUtxo.cardanoTokens.map { asset in
                        CardanoTokenAmount.with {
                            $0.policyID = asset.policyId
                            $0.assetNameHex = asset.assetNameHex
                            $0.amount = unsignedBigEndianBytes(asset.amount)
                        }
                    }
                }
            }
            input.utxos.append(utxo)
        }

        return input
    }

    /// Canonical CIP-20 auxiliary-data CBOR (label 674) for the payload memo,
    /// or `nil` when there is no memo. Both the pre-sign input
    /// (`CardanoSigningInput.auxiliaryData`) and the hand-built signed envelope
    /// (element [3]) derive from this single source, so the body's key-7 hash
    /// and the embedded aux bytes stay consistent — and byte-identical to the
    /// SDK/Android/Extension co-signers.
    static func cip20AuxData(for keysignPayload: KeysignPayload) -> Data? {
        guard let memo = keysignPayload.memo, !memo.isEmpty else { return nil }
        return CardanoCIP20.buildAuxData(memo: memo).auxDataCbor
    }

    /// Encode an unsigned integer as minimal big-endian bytes (matches
    /// SDK `amountToBytes`). Returns `[0x00]` for zero.
    private static func unsignedBigEndianBytes(_ amount: BigInt) -> Data {
        let unsigned = BigUInt(amount.description) ?? .zero
        return unsigned.isZero ? Data([0x00]) : unsigned.serialize()
    }

    /// Build a WalletCore TokenBundle when the active coin is a Cardano native
    /// token (`coin.contractAddress` non-empty). The bundle carries one token
    /// matching the asset id; the amount is encoded as minimal big-endian
    /// unsigned bytes — matches `vultisig-sdk/.../signingInputs/resolvers/cardano.ts`.
    static func makeTokenBundle(for keysignPayload: KeysignPayload) throws -> CardanoTokenBundle? {
        let contractAddress = keysignPayload.coin.contractAddress
        guard !contractAddress.isEmpty else { return nil }

        let parsed = try CardanoAssetId.parse(contractAddress)
        let amount = BigUInt(keysignPayload.toAmount.description) ?? .zero
        // BigUInt.serialize() strips leading zero bytes — empty for zero.
        // SDK encodes zero as a single 0x00 byte (Buffer.from("00", "hex")).
        let amountBytes = amount.isZero ? Data([0x00]) : amount.serialize()

        var bundle = CardanoTokenBundle()
        bundle.token = [
            CardanoTokenAmount.with {
                $0.policyID = parsed.policyId
                $0.assetNameHex = parsed.assetName
                $0.amount = amountBytes
            }
        ]
        return bundle
    }

    /// Pre-image hash for MPC keysign. Per-UTXO token data is read off the
    /// wire from `keysignPayload.utxos[i].cardanoTokens` — the initiator
    /// fetched it from Koios when building the payload, so both peers
    /// produce identical body bytes by construction.
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        let inputData = try getCardanoPreSignInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }

    static func getCardanoPreSignInputData(keysignPayload: KeysignPayload) throws -> Data {
        var input = try getPreSignedInputData(keysignPayload: keysignPayload)
        let plan: CardanoTransactionPlan = AnySigner.plan(input: input, coin: .cardano)
        if plan.error != .ok {
            throw HelperError.runtimeError("Cardano transaction plan error: \(plan.error)")
        }
        input.plan = plan
        // Pin the planned fee into the body so the pre-image hash and the compile
        // phase agree on identical bytes. Because `forceFee` was seeded above with
        // the shared `byteFee`, `doPlan()` honors it and `plan.fee == byteFee` —
        // the body carries the fee that every device forces identically.
        input.transferMessage.forceFee = plan.fee
        return try input.serializedData()
    }

    /// Fallback flat fee used only when the initiator's preliminary plan fails.
    /// Mirrors the SDK's historical `cardanoDefaultFee`. It underpays bodies
    /// above ~560 bytes, so it is a last resort — `estimateDynamicByteFee`
    /// normally returns the real size-based fee.
    static let fallbackByteFee: BigInt = 180_000

    /// Compute the shared `byteFee` the INITIATOR seeds into the keysign payload.
    ///
    /// MPC requires every co-signing device to bake a byte-identical fee into the
    /// Cardano body, or the Blake2b sighash diverges and signing fails. We make
    /// the fee a single shared constant: the initiator runs a preliminary plan
    /// over the selected UTXOs/outputs WITHOUT forcing the fee, lets WalletCore
    /// derive the real size-based fee (`minFeeA*size + minFeeB`), and stores that
    /// into `chainSpecific.byteFee`. Every co-signer (iOS/SDK/Windows/Android)
    /// then forces that exact value, so the body fee is identical everywhere.
    ///
    /// A flat fee underpays any body above ~560 bytes (CNT / multi-input /
    /// metadata sends), which the network rejects with `FeeTooSmallUTxO`; a
    /// size-derived fee fixes that. If planning fails we fall back to the flat
    /// `fallbackByteFee` (logged) rather than crashing the send flow.
    static func estimateDynamicByteFee(keysignPayload: KeysignPayload) -> BigInt {
        do {
            let input = try getPreSignedInputData(keysignPayload: keysignPayload)
            // Drop any seeded fee so the planner derives a size-based one.
            var unforced = input
            unforced.transferMessage.forceFee = 0
            let plan: CardanoTransactionPlan = AnySigner.plan(input: unforced, coin: .cardano)
            guard plan.error == .ok, plan.fee > 0 else {
                cardanoLogger.warning("Cardano fee plan failed (error: \(String(describing: plan.error)), fee: \(plan.fee)); falling back to flat \(fallbackByteFee) lovelace")
                return fallbackByteFee
            }
            return BigInt(plan.fee)
        } catch {
            cardanoLogger.warning("Cardano fee estimation threw (\(error.localizedDescription)); falling back to flat \(fallbackByteFee) lovelace")
            return fallbackByteFee
        }
    }

    static func getSignedTransaction(vaultHexPubKey: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) throws -> SignedTransactionResult {

        // Build the verification key (raw 32-byte EdDSA spending key) — matches TSS output.
        guard let spendingKeyData = Data(hexString: vaultHexPubKey),
              let verificationKey = PublicKey(data: spendingKeyData, type: .ed25519) else {
            throw HelperError.runtimeError("failed to create EdDSA public key for verification")
        }

        let inputData = try getCardanoPreSignInputData(keysignPayload: keysignPayload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }

        let signatureProvider = SignatureProvider(signatures: signatures)
        let signature = signatureProvider.getSignature(preHash: preSigningOutput.dataHash)
        guard verificationKey.verify(signature: signature, message: preSigningOutput.dataHash) else {
            throw HelperError.runtimeError("Cardano signature verification failed")
        }

        // WalletCore's compileWithSignatures crashes on Cardano under certain
        // builds (AddressV2::isValid). Build the signed CBOR envelope by hand
        // from the pre-image body bytes — see CardanoSignedTxBuilder. The body
        // is embedded verbatim; the signature covers Blake2b of those bytes.
        // When a CIP-20 memo is present, the pre-image body already carries the
        // aux hash at key 7 (WalletCore committed it from `auxiliaryData`); we
        // embed the same aux CBOR as element [3]. The body, witness, and aux
        // bytes match AnySigner's native output; the envelope framing follows
        // the SDK/mainnet-verified 4-element `[body, witness, is_valid, aux]`
        // format (AnySigner uses the 3-element Shelley form — same txid).
        let signedTx = try CardanoSignedTxBuilder.build(
            txBody: preSigningOutput.data,
            publicKey: spendingKeyData,
            signature: signature,
            auxData: cip20AuxData(for: keysignPayload)
        )

        // Cardano txId IS Blake2b-256 of the body, which is exactly the
        // dataHash we already fed to MPC.
        return SignedTransactionResult(
            rawTransaction: signedTx.hexString,
            transactionHash: preSigningOutput.dataHash.hexString
        )
    }
}

// MARK: - BigInt Extension for ADA Formatting
extension BigInt {
    /// Safely convert lovelaces to ADA using Decimal for precision
    var toADA: Decimal {
        return Decimal(string: self.description)! / 1_000_000
    }

    /// Format as ADA string with appropriate decimal places
    var toADAString: String {
        let decimal = self.toADA
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.numberStyle = .decimal
        return formatter.string(from: decimal as NSDecimalNumber) ?? "0"
    }
}
