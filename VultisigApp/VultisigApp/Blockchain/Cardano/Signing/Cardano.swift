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
            // For MAX amount display, truncate to 5 decimal places to match getMaxValue behavior
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: 5) // ADA has 6 decimals, so decimals - 1 = 5
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: 5)

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
            // For MAX amount display, truncate to 5 decimal places to match getMaxValue behavior
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: 5) // ADA has 6 decimals, so decimals - 1 = 5
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: 5)

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
            // For MAX amount display, truncate to 5 decimal places to match getMaxValue behavior
            let totalBalanceDecimal = totalBalance.toADA
            let truncatedBalance = totalBalanceDecimal.truncated(toPlaces: 5) // ADA has 6 decimals, so decimals - 1 = 5
            let totalBalanceADA = truncatedBalance.formatToDecimal(digits: 5)

            return (true, "💡 Low balance detected. Consider 'Send Max' (\(totalBalanceADA) ADA) to avoid change issues.")
        }

        return (false, nil)
    }

    /// Display fee for the Verify screen. Returns `chainSpecific.byteFee`
    /// (default `180_000` lovelace, matches SDK `cardanoDefaultFee`). The
    /// real fee baked into the body comes from `AnySigner.plan(...)` at sign
    /// time — this is the user-facing estimate.
    static func calculateDynamicFee(keysignPayload: KeysignPayload) throws -> BigInt {
        guard case .Cardano(let byteFee, _, _) = keysignPayload.chainSpecific else {
            throw HelperError.runtimeError("fail to get Cardano chain specific parameters")
        }
        return byteFee
    }

    // MARK: - Helper Functions

    /// Build a WalletCore `CardanoSigningInput`. For CNT sends, pass the
    /// pre-fetched extended UTXOs so each `TxInput` can carry its per-UTXO
    /// `tokenAmount` — without that, WalletCore's Cardano planner trips
    /// `errorLowBalance` because it can't see any tokens in the inputs.
    /// `extendedUtxos` may be empty for ADA-only sends (no token data needed).
    static func getPreSignedInputData(
        keysignPayload: KeysignPayload,
        extendedUtxos: [CardanoExtendedUtxo] = []
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

        // `forceFee` must be set before `AnySigner.plan(...)` — WalletCore's Cardano
        // `doPlan()` reads it only during planning, so a size-derived fee here would
        // diverge from the SDK/Windows body and break MPC sighash parity.
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
        }

        // Add UTXOs to the input. For CNT sends, attach per-UTXO token data
        // by matching on (hash, index) against the extended UTXO list;
        // without this, the planner can't reconcile a TokenBundle output.
        let extendedByOutPoint: [String: CardanoExtendedUtxo] = Dictionary(
            uniqueKeysWithValues: extendedUtxos.map { ("\($0.hash):\($0.index)", $0) }
        )
        for inputUtxo in keysignPayload.utxos {
            let utxo = CardanoTxInput.with {
                $0.outPoint = CardanoOutPoint.with {
                    $0.txHash = Data(hexString: inputUtxo.hash)!
                    $0.outputIndex = UInt64(inputUtxo.index)
                }
                $0.amount = UInt64(inputUtxo.amount)
                $0.address = keysignPayload.coin.address
                if let extended = extendedByOutPoint["\(inputUtxo.hash):\(inputUtxo.index)"] {
                    $0.tokenAmount = extended.assets.map { asset in
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

    /// Synchronous pre-image hash — used by tests with ADA-only fixtures
    /// that don't need per-UTXO token data. Real keysign flows go through
    /// `getPreSignedImageHashAsync(...)` which fetches extended UTXOs from
    /// Koios so the planner can balance CNT sends.
    static func getPreSignedImageHash(keysignPayload: KeysignPayload) throws -> [String] {
        try preSignedImageHash(keysignPayload: keysignPayload, extendedUtxos: [])
    }

    /// Async pre-image hash. Fetches extended UTXOs (with per-UTXO assets)
    /// from Koios when the active coin is a CNT — the WalletCore Cardano
    /// planner needs that token data on inputs to balance the TokenBundle
    /// output. Both MPC peers fetch independently; Koios returns the same
    /// UTXO set for the same address so both produce identical body bytes.
    static func getPreSignedImageHashAsync(keysignPayload: KeysignPayload) async throws -> [String] {
        let extendedUtxos = try await fetchExtendedUtxosIfNeeded(for: keysignPayload)
        return try preSignedImageHash(keysignPayload: keysignPayload, extendedUtxos: extendedUtxos)
    }

    private static func preSignedImageHash(
        keysignPayload: KeysignPayload,
        extendedUtxos: [CardanoExtendedUtxo]
    ) throws -> [String] {
        let inputData = try getCardanoPreSignInputData(
            keysignPayload: keysignPayload,
            extendedUtxos: extendedUtxos
        )
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        if !preSigningOutput.errorMessage.isEmpty {
            throw HelperError.runtimeError(preSigningOutput.errorMessage)
        }
        return [preSigningOutput.dataHash.hexString]
    }

    static func getCardanoPreSignInputData(
        keysignPayload: KeysignPayload,
        extendedUtxos: [CardanoExtendedUtxo] = []
    ) throws -> Data {
        var input = try getPreSignedInputData(keysignPayload: keysignPayload, extendedUtxos: extendedUtxos)
        let plan: CardanoTransactionPlan = AnySigner.plan(input: input, coin: .cardano)
        if plan.error != .ok {
            throw HelperError.runtimeError("Cardano transaction plan error: \(plan.error)")
        }
        input.plan = plan
        input.transferMessage.forceFee = plan.fee
        return try input.serializedData()
    }

    /// Fetch extended UTXOs (per-UTXO `asset_list`) from Koios when the
    /// active coin is a CNT — needed by the planner to balance tokens.
    /// Returns an empty array for ADA-only sends so we don't pay the
    /// network cost when it's not required.
    private static func fetchExtendedUtxosIfNeeded(for keysignPayload: KeysignPayload) async throws -> [CardanoExtendedUtxo] {
        guard !keysignPayload.coin.contractAddress.isEmpty else { return [] }
        return try await CardanoService.shared.getExtendedUTXOs(coin: keysignPayload.coin)
    }
    static func getSignedTransaction(vaultHexPubKey: String,
                                     keysignPayload: KeysignPayload,
                                     signatures: [String: TssKeysignResponse]) async throws -> SignedTransactionResult {

        // Build the verification key (raw 32-byte EdDSA spending key) — matches TSS output.
        guard let spendingKeyData = Data(hexString: vaultHexPubKey),
              let verificationKey = PublicKey(data: spendingKeyData, type: .ed25519) else {
            throw HelperError.runtimeError("failed to create EdDSA public key for verification")
        }

        let extendedUtxos = try await fetchExtendedUtxosIfNeeded(for: keysignPayload)
        let inputData = try getCardanoPreSignInputData(
            keysignPayload: keysignPayload,
            extendedUtxos: extendedUtxos
        )
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
        let signedTx = try CardanoSignedTxBuilder.build(
            txBody: preSigningOutput.data,
            publicKey: spendingKeyData,
            signature: signature
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
