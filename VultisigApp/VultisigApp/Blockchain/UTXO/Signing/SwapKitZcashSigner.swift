//
//  SwapKitZcashSigner.swift
//  VultisigApp
//
//  Signs SwapKit's pre-built ZEC PSBT. The transparent ZEC tx is wrapped in
//  a BIP-174 envelope but the inner unsigned-tx body is **Sapling-v4**, not
//  BIP-144 segwit: extra `nVersionGroupId` (4B), `expiryHeight` (4B),
//  `valueBalance` (i64), and three varint zeros for shielded counts. We
//  walk those, assert the chain is on Sapling v4 transparent-only (v5 NU5
//  hard-rejected; non-zero shielded fields hard-rejected), then hand the
//  P2PKH inputs to WalletCore's `CoinType.zcash` path.
//
//  Sighash: WalletCore's ZEC signer implements ZIP-243 (the Sapling
//  signature digest with the personalised Blake2b-256). It reads the branch
//  ID from `BitcoinTransactionPlan.branchID` — the existing native ZEC
//  send (`UTXOChainsHelper.swift:138-139`) uses `f04dec4d`, and we match
//  that here so the digest output is identical to a manually-sent ZEC
//  transaction. (Deviating to the Sapling-v4 spec ID `0x76b809bb` would
//  produce a different digest that the chain rejects.)
//
//  Real fixture: captured during the ZEC source-chain spike (`ZEC.ZEC →
//  ETH.USDC`, funded `t1bnxtY7aLCjWx9Ru1YcGwRWch3eEWUFK7u` source). The
//  body is 201 bytes — see `__fixtures__/v3-real-zec-swap.json`.
//

import Foundation
import OSLog
import Tss
import WalletCore

private let logger = Logger(subsystem: "com.vultisig.app", category: "swapkit-zec-signer")

enum SwapKitZcashSignerError: Error, LocalizedError {
    case unsupportedZcashVersion(version: UInt32, group: UInt32)
    case unsupportedShieldedTransaction
    case underlying(SwapKitLegacyP2PKHSignerError)

    var errorDescription: String? {
        switch self {
        case .unsupportedZcashVersion(let version, let group):
            return String(format: "swapKitErrorUnsupportedZcashVersion".localized, "0x\(String(version, radix: 16))", "0x\(String(group, radix: 16))")
        case .unsupportedShieldedTransaction:
            return "swapKitErrorUnsupportedShieldedTransaction".localized
        case .underlying(let err):
            return err.errorDescription
        }
    }
}

/// Sapling-v4 consensus group ID. `nVersionGroupId` field must equal this
/// or the tx is on a different consensus epoch we don't sign.
private let saplingVersionGroupID: UInt32 = 0x892F2085
/// Overwinter flag (high bit) + version 4. Matches `0x04 0x00 0x00 0x80` LE.
private let saplingTxVersion: UInt32 = 0x80000004
/// NU5 consensus group ID — we hard-reject this until SwapKit's wire flips.
private let nu5VersionGroupID: UInt32 = 0x26A7270A
/// Branch ID matches the existing native ZEC send
/// (`UTXOChainsHelper.swift:138-139`). WalletCore reads it as the branch
/// identifier for ZIP-243's personalised Blake2b. Diverging to the
/// Sapling-v4-spec `0x76b809bb` would produce a digest the network rejects.
private let zcashBranchID: Data = Data(hexString: "f04dec4d")!

enum SwapKitZcashSigner {

    /// ZIP-243 preimage hashes for every input. WalletCore handles the per-
    /// input personalised Blake2b construction via `CoinType.zcash` + the
    /// branchID injected on the frozen plan.
    static func preSigningHashes(payload: SwapKitSwapPayload) throws -> [String] {
        let input = try Self.buildSigningInput(payload: payload)
        let serialized = try input.serializedData()
        let preHashesBytes = TransactionCompiler.preImageHashes(coinType: .zcash, txInputData: serialized)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashesBytes)
        if !preSignOutputs.errorMessage.isEmpty {
            throw SwapKitZcashSignerError.underlying(.planError(preSignOutputs.errorMessage))
        }
        return preSignOutputs.hashPublicKeys
            .map { $0.dataHash.hexString }
            .sorted()
    }

    /// Assemble the signed broadcast tx with the Sapling-v4 header + ZIP-243
    /// sighash already baked into WalletCore's compileWithSignatures.
    static func compileSignedTransaction(
        payload: SwapKitSwapPayload,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: pubKeyHex),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw SwapKitZcashSignerError.underlying(.invalidPublicKey(pubKeyHex))
        }
        let input = try Self.buildSigningInput(payload: payload)
        let serialized = try input.serializedData()
        let preHashesBytes = TransactionCompiler.preImageHashes(coinType: .zcash, txInputData: serialized)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashesBytes)
        if !preSignOutputs.errorMessage.isEmpty {
            throw SwapKitZcashSignerError.underlying(.planError(preSignOutputs.errorMessage))
        }
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let provider = SignatureProvider(signatures: signatures)
        for h in preSignOutputs.hashPublicKeys {
            let preImage = h.dataHash
            let signature = provider.getDerSignature(preHash: preImage)
            guard publicKey.verifyAsDER(signature: signature, message: preImage) else {
                throw SwapKitZcashSignerError.underlying(.signatureVerifyFailed)
            }
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
        }
        let compileBytes = TransactionCompiler.compileWithSignatures(
            coinType: .zcash,
            txInputData: serialized,
            signatures: allSignatures,
            publicKeys: publicKeys
        )
        let output = try BitcoinSigningOutput(serializedBytes: compileBytes)
        if !output.errorMessage.isEmpty {
            throw SwapKitZcashSignerError.underlying(.planError(output.errorMessage))
        }
        return SignedTransactionResult(
            rawTransaction: output.encoded.hexString,
            transactionHash: output.transactionID
        )
    }

    /// Exposed for unit tests: build the WalletCore signing input with the
    /// frozen Sapling plan + branchID set.
    static func buildSigningInput(payload: SwapKitSwapPayload) throws -> BitcoinSigningInput {
        let parsed = try parseSaplingPSBT(
            payload.txPayload,
            targetAddress: payload.targetAddress
        )
        var input = parsed.input
        // ZEC ZIP-243 needs `branchID` on the plan — WalletCore reads it
        // during preimage construction. Mirror the value the native send
        // path uses so digest derivation is identical.
        var plan = input.plan
        plan.branchID = zcashBranchID
        input.plan = plan
        return input
    }

    /// Exposed for unit tests so callers can pin the Sapling-header parser
    /// in isolation.
    static func parseSaplingUnsignedTx(_ data: Data) throws -> ParsedSaplingTx {
        var cursor = PSBTCursor(data: data)
        do {
            let version = try cursor.readUInt32LE()
            let versionGroupID = try cursor.readUInt32LE()
            // Reject NU5 (v5) outright — different sighash construction
            // (ZIP-244) that WalletCore may not handle, and our branchID
            // assumes Sapling-v4 + Vultisig's existing native-send path.
            guard version == saplingTxVersion, versionGroupID == saplingVersionGroupID else {
                throw SwapKitZcashSignerError.unsupportedZcashVersion(
                    version: version,
                    group: versionGroupID
                )
            }
            let inputCount = try cursor.readCompactSize()
            var inputs: [(prevTxIdLE: Data, prevIndex: UInt32, sequence: UInt32)] = []
            for _ in 0..<inputCount {
                let prevBytes = try cursor.readBytes(32)
                let prevIndex = try cursor.readUInt32LE()
                let sigLen = try cursor.readCompactSize()
                _ = try cursor.readBytes(Int(sigLen))
                let sequence = try cursor.readUInt32LE()
                inputs.append((prevTxIdLE: prevBytes, prevIndex: prevIndex, sequence: sequence))
            }
            let outputCount = try cursor.readCompactSize()
            var outputs: [LegacyP2PKHOutput] = []
            for _ in 0..<outputCount {
                let amount = try cursor.readInt64LE()
                let scriptLen = try cursor.readCompactSize()
                let script = try cursor.readBytes(Int(scriptLen))
                outputs.append(LegacyP2PKHOutput(amount: amount, scriptPubKey: script))
            }
            let lockTime = try cursor.readUInt32LE()
            let expiryHeight = try cursor.readUInt32LE()
            // Sapling-v4 transparent-only: all shielded fields must be zero.
            // If SwapKit ever returns a tx with shielded value flowing,
            // hard-reject — we can't sign shielded bundles with MPC.
            let valueBalance = try cursor.readInt64LE()
            let nShieldedSpend = try cursor.readCompactSize()
            let nShieldedOutput = try cursor.readCompactSize()
            let nJoinSplit = try cursor.readCompactSize()
            guard valueBalance == 0,
                  nShieldedSpend == 0,
                  nShieldedOutput == 0,
                  nJoinSplit == 0 else {
                throw SwapKitZcashSignerError.unsupportedShieldedTransaction
            }
            return ParsedSaplingTx(
                version: version,
                versionGroupID: versionGroupID,
                lockTime: lockTime,
                expiryHeight: expiryHeight,
                inputs: inputs,
                outputs: outputs
            )
        } catch let err as SwapKitPSBTParserError {
            throw SwapKitZcashSignerError.underlying(mapParserError(err))
        }
    }

    // MARK: - Private — full PSBT walker (framing + Sapling body + per-input maps)

    private struct ParsedSaplingPSBT {
        let input: BitcoinSigningInput
    }

    private static func parseSaplingPSBT(_ psbtBytes: Data, targetAddress: String) throws -> ParsedSaplingPSBT {
        // 1. Parse BIP-174 framing.
        let framingPrefix: (cursor: PSBTCursor, globals: [Data: Data], unsignedTxBytes: Data)
        do {
            framingPrefix = try SwapKitPSBTParser.parseFraming(psbtBytes: psbtBytes)
        } catch let err as SwapKitPSBTParserError {
            throw SwapKitZcashSignerError.underlying(mapParserError(err))
        }

        // 2. Parse the Sapling-v4 body.
        let parsedTx = try parseSaplingUnsignedTx(framingPrefix.unsignedTxBytes)

        // 3. Drain per-input + per-output maps.
        var cursor = framingPrefix.cursor
        var inputMaps: [[Data: Data]] = []
        for _ in 0..<parsedTx.inputs.count {
            do {
                inputMaps.append(try cursor.readMap())
            } catch let err as SwapKitPSBTParserError {
                throw SwapKitZcashSignerError.underlying(mapParserError(err))
            }
        }
        for _ in 0..<parsedTx.outputs.count {
            do {
                _ = try cursor.readMap()
            } catch let err as SwapKitPSBTParserError {
                throw SwapKitZcashSignerError.underlying(mapParserError(err))
            }
        }

        // 4. Resolve per-input UTXO (ZEC ships WITNESS_UTXO per the spike
        // fixture — different from DOGE's NON_WITNESS_UTXO — but the shared
        // resolver accepts both).
        var legacyInputs: [LegacyP2PKHInput] = []
        for (index, parsedInput) in parsedTx.inputs.enumerated() {
            let (amount, scriptPubKey) = try resolvePrevUtxo(
                inputMap: inputMaps[index],
                inputIndex: index
            )
            let keyHash = try assertP2PKHAndExtractKeyHash(
                scriptPubKey: scriptPubKey,
                inputIndex: index
            )
            legacyInputs.append(LegacyP2PKHInput(
                prevTxIdLE: parsedInput.prevTxIdLE,
                prevIndex: parsedInput.prevIndex,
                sequence: parsedInput.sequence,
                amount: amount,
                scriptPubKey: scriptPubKey,
                keyHash: keyHash
            ))
        }

        // 5. Build the BitcoinSigningInput with a frozen plan.
        let input = try assembleZcashSigningInput(
            inputs: legacyInputs,
            outputs: parsedTx.outputs,
            expiryHeight: parsedTx.expiryHeight,
            targetAddress: targetAddress
        )
        return ParsedSaplingPSBT(input: input)
    }

    private static func resolvePrevUtxo(
        inputMap: [Data: Data],
        inputIndex: Int
    ) throws -> (amount: Int64, scriptPubKey: Data) {
        // ZEC ships WITNESS_UTXO (key 0x01) — confirmed in the captured
        // fixture. The shared `parseWitnessUtxo` lives on
        // `SwapKitLegacyP2PKHSigner` but it's `private`; reimplement
        // locally (8 lines).
        if let witness = inputMap[Data([0x01])] {
            var c = PSBTCursor(data: witness)
            do {
                let amount = try c.readInt64LE()
                let scriptLen = try c.readCompactSize()
                let script = try c.readBytes(Int(scriptLen))
                return (amount, script)
            } catch let err as SwapKitPSBTParserError {
                throw SwapKitZcashSignerError.underlying(mapParserError(err))
            }
        }
        throw SwapKitZcashSignerError.underlying(.missingPrevUtxo(inputIndex: inputIndex))
    }

    private static func assertP2PKHAndExtractKeyHash(
        scriptPubKey: Data,
        inputIndex: Int
    ) throws -> Data {
        guard scriptPubKey.count == 25,
              scriptPubKey[scriptPubKey.startIndex] == 0x76,
              scriptPubKey[scriptPubKey.startIndex + 1] == 0xa9,
              scriptPubKey[scriptPubKey.startIndex + 2] == 0x14,
              scriptPubKey[scriptPubKey.startIndex + 23] == 0x88,
              scriptPubKey[scriptPubKey.startIndex + 24] == 0xac
        else {
            throw SwapKitZcashSignerError.underlying(.unsupportedScript(
                "input #\(inputIndex) scriptPubKey is not P2PKH: \(scriptPubKey.hexString)"
            ))
        }
        let start = scriptPubKey.startIndex + 3
        return Data(scriptPubKey[start..<(start + 20)])
    }

    private static func assembleZcashSigningInput(
        inputs: [LegacyP2PKHInput],
        outputs: [LegacyP2PKHOutput],
        expiryHeight _: UInt32,
        targetAddress: String
    ) throws -> BitcoinSigningInput {
        guard !inputs.isEmpty, !outputs.isEmpty else {
            throw SwapKitZcashSignerError.underlying(.planError("empty inputs or outputs"))
        }
        let totalIn = inputs.reduce(Int64(0)) { $0 + $1.amount }
        let totalOut = outputs.reduce(Int64(0)) { $0 + $1.amount }
        let fee = totalIn - totalOut
        guard fee >= 0 else {
            throw SwapKitZcashSignerError.underlying(.planError(
                "negative fee: inputs=\(totalIn) outputs=\(totalOut)"
            ))
        }
        let depositAmount = outputs[0].amount
        let changeAmount = outputs.dropFirst().reduce(Int64(0)) { $0 + $1.amount }

        var utxos: [BitcoinUnspentTransaction] = []
        for input in inputs {
            let utxo = BitcoinUnspentTransaction.with {
                $0.outPoint = BitcoinOutPoint.with {
                    $0.hash = input.prevTxIdLE
                    $0.index = input.prevIndex
                    $0.sequence = input.sequence
                }
                $0.amount = input.amount
                $0.script = input.scriptPubKey
            }
            utxos.append(utxo)
        }

        let plan = BitcoinTransactionPlan.with {
            $0.amount = depositAmount
            $0.availableAmount = totalIn
            $0.fee = fee
            $0.change = changeAmount
            $0.utxos = utxos
            $0.branchID = zcashBranchID
        }

        var scripts: [String: Data] = [:]
        for input in inputs {
            let redeem = BitcoinScript.buildPayToPublicKeyHash(hash: input.keyHash)
            scripts[input.keyHash.hexString] = redeem.data
        }

        var signingInput = BitcoinSigningInput.with {
            $0.hashType = BitcoinScript.hashTypeForCoin(coinType: .zcash)
            $0.byteFee = 1
            $0.useMaxAmount = false
            $0.amount = depositAmount
            $0.coinType = CoinType.zcash.rawValue
            // toAddress / changeAddress: WalletCore validates non-empty
            // strings even with a frozen plan. Reuse SwapKit's returned
            // `targetAddress` for both — the plan supersedes at signing.
            $0.toAddress = targetAddress
            $0.changeAddress = targetAddress
        }
        signingInput.scripts = scripts
        signingInput.utxo = utxos
        signingInput.plan = plan
        return signingInput
    }

    private static func mapParserError(_ err: SwapKitPSBTParserError) -> SwapKitLegacyP2PKHSignerError {
        switch err {
        case .missingPSBT: return .missingPSBT
        case .truncated: return .truncated
        case .invalidMagic: return .invalidMagic
        }
    }
}

/// Result of parsing the Sapling-v4 unsigned-tx body. Exposed so tests can
/// pin the structural fields (version, group, expiry, input/output counts)
/// without going through the full PSBT walker.
struct ParsedSaplingTx {
    let version: UInt32
    let versionGroupID: UInt32
    let lockTime: UInt32
    let expiryHeight: UInt32
    let inputs: [(prevTxIdLE: Data, prevIndex: UInt32, sequence: UInt32)]
    let outputs: [LegacyP2PKHOutput]
}
