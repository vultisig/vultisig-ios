//
//  SwapKitLegacyP2PKHSigner.swift
//  VultisigApp
//
//  Shared bridge between a SwapKit PSBT and WalletCore's `TransactionCompiler`
//  for **legacy P2PKH UTXO chains**: DOGE (no segwit ever), BCH (forked 2017,
//  no segwit), DASH (no segwit). Each chain wraps this helper into a typed
//  `SwapKit<Chain>Signer` so call sites can throw chain-specific errors.
//
//  Why this exists separately from `SwapKitBTCSigner`:
//
//  - `SwapKitBTCSigner` consumes WITNESS_UTXO (key `0x01`) per-input records
//    and hands the structured `SignBitcoin` to `BitcoinPsbtSigner`, which
//    computes **BIP-143** sighashes. BIP-143 is segwit-only — its `hashPrevouts`
//    / `hashSequence` / `hashOutputs` construction assumes witness semantics.
//  - DOGE / BCH / DASH inputs are pure P2PKH (`76 a9 14 <20> 88 ac`). They
//    need **legacy sighashing**, which WalletCore's `TransactionCompiler`
//    handles end-to-end via `CoinType.<chain>` (same path the native send
//    helper rides). BCH adds SIGHASH_FORKID natively via
//    `BitcoinScript.hashTypeForCoin(.bitcoinCash)`.
//
//  The "frozen plan" pattern is load-bearing: if we let `AnySigner.plan(...)`
//  replan UTXO selection it would compute a different tx and a different
//  `tx_id`. NEAR Intents tracks the route by the tx_id SwapKit baked into
//  the PSBT — we sign verbatim or we break tracking.
//

import Foundation
import OSLog
import Tss
import WalletCore

/// Errors surfaced by the legacy-P2PKH PSBT bridge. Per-chain signers wrap
/// these into their own typed errors so call sites surface chain-specific
/// messages (the DOGE / BCH signers below produce
/// `SwapKitDogeSignerError.unsupportedScript` etc.).
enum SwapKitLegacyP2PKHSignerError: Error, LocalizedError {
    case missingPSBT
    case truncated
    case invalidMagic
    case missingUnsignedTx
    case unsupportedScript(String)
    case missingPrevUtxo(inputIndex: Int)
    case invalidPrevUtxo(inputIndex: Int, reason: String)
    case planError(String)
    case invalidPublicKey(String)
    case signatureVerifyFailed
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .missingPSBT:
            return "SwapKit PSBT payload is empty"
        case .truncated:
            return "SwapKit PSBT is truncated"
        case .invalidMagic:
            return "SwapKit PSBT magic bytes are invalid"
        case .missingUnsignedTx:
            return "SwapKit PSBT is missing the unsigned-tx global record"
        case .unsupportedScript(let detail):
            return "SwapKit PSBT script not supported: \(detail)"
        case .missingPrevUtxo(let i):
            return "SwapKit PSBT input #\(i) is missing prev-tx UTXO record"
        case .invalidPrevUtxo(let i, let reason):
            return "SwapKit PSBT input #\(i) prev-tx UTXO invalid: \(reason)"
        case .planError(let detail):
            return "SwapKit PSBT transaction plan error: \(detail)"
        case .invalidPublicKey(let key):
            return "Invalid public key: \(key)"
        case .signatureVerifyFailed:
            return "SwapKit PSBT signature verification failed"
        case .underlying(let detail):
            return "SwapKit PSBT signing failed: \(detail)"
        }
    }
}

/// Per-input frozen-plan input. `keyHash` is the 20-byte P2PKH hash160 of
/// the recipient pubkey — used to build the redeem-script entry on
/// `BitcoinSigningInput.scripts[keyHash.hex]`.
struct LegacyP2PKHInput {
    let prevTxIdLE: Data         // 32 bytes, little-endian wire order
    let prevIndex: UInt32
    let sequence: UInt32
    let amount: Int64
    let scriptPubKey: Data       // 25 bytes: 76 a9 14 <20> 88 ac
    let keyHash: Data            // 20 bytes
}

/// Per-output (deposit + change) info pulled from the unsigned-tx body. Used
/// to size the frozen plan's `amount` / `fee` / `change` fields.
struct LegacyP2PKHOutput {
    let amount: Int64
    let scriptPubKey: Data
}

/// Parsed legacy unsigned-tx body. Pre-segwit serialization (no `marker`
/// `flag` `witness` bytes). DOGE / BCH / DASH all use this shape.
struct ParsedLegacyTx {
    let version: UInt32
    let locktime: UInt32
    let inputs: [(prevTxIdLE: Data, prevIndex: UInt32, sequence: UInt32)]
    let outputs: [LegacyP2PKHOutput]
}

enum SwapKitLegacyP2PKHSigner {

    /// Pre-signing hashes for a DOGE/BCH/DASH PSBT. The caller picks `coin`
    /// (`.dogecoin`, `.bitcoinCash`, `.dash`) — WalletCore picks the right
    /// hash type (BCH gets SIGHASH_FORKID via `hashTypeForCoin`). `targetAddress`
    /// is the SwapKit-returned deposit address — populated on the input even
    /// though the frozen plan supersedes; WalletCore's pre-flight validation
    /// rejects empty addresses.
    static func preSigningHashes(
        psbtBytes: Data,
        coin: CoinType,
        targetAddress: String = ""
    ) throws -> [String] {
        let input = try buildSigningInput(
            psbtBytes: psbtBytes,
            coin: coin,
            targetAddress: targetAddress
        )
        let serialized = try input.serializedData()
        let preHashesBytes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: serialized)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashesBytes)
        if !preSignOutputs.errorMessage.isEmpty {
            throw SwapKitLegacyP2PKHSignerError.planError(preSignOutputs.errorMessage)
        }
        return preSignOutputs.hashPublicKeys
            .map { $0.dataHash.hexString }
            .sorted()
    }

    /// Assemble a signed legacy P2PKH transaction. ECDSA-DER signatures from
    /// MPC verified against each per-input preimage hash, then
    /// `TransactionCompiler.compileWithSignatures` produces the broadcast tx.
    static func compileSignedTransaction(
        psbtBytes: Data,
        coin: CoinType,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String,
        targetAddress: String = ""
    ) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: pubKeyHex),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw SwapKitLegacyP2PKHSignerError.invalidPublicKey(pubKeyHex)
        }
        let input = try buildSigningInput(
            psbtBytes: psbtBytes,
            coin: coin,
            targetAddress: targetAddress
        )
        let serialized = try input.serializedData()
        let preHashesBytes = TransactionCompiler.preImageHashes(coinType: coin, txInputData: serialized)
        let preSignOutputs = try BitcoinPreSigningOutput(serializedBytes: preHashesBytes)
        if !preSignOutputs.errorMessage.isEmpty {
            throw SwapKitLegacyP2PKHSignerError.planError(preSignOutputs.errorMessage)
        }
        let allSignatures = DataVector()
        let publicKeys = DataVector()
        let signatureProvider = SignatureProvider(signatures: signatures)
        for h in preSignOutputs.hashPublicKeys {
            let preImageHash = h.dataHash
            let signature = signatureProvider.getDerSignature(preHash: preImageHash)
            guard publicKey.verifyAsDER(signature: signature, message: preImageHash) else {
                throw SwapKitLegacyP2PKHSignerError.signatureVerifyFailed
            }
            allSignatures.add(data: signature)
            publicKeys.add(data: pubkeyData)
        }
        let compileBytes = TransactionCompiler.compileWithSignatures(
            coinType: coin,
            txInputData: serialized,
            signatures: allSignatures,
            publicKeys: publicKeys
        )
        let output = try BitcoinSigningOutput(serializedBytes: compileBytes)
        if !output.errorMessage.isEmpty {
            throw SwapKitLegacyP2PKHSignerError.planError(output.errorMessage)
        }
        return SignedTransactionResult(
            rawTransaction: output.encoded.hexString,
            transactionHash: output.transactionID
        )
    }

    /// Build the `BitcoinSigningInput` with a **frozen** `BitcoinTransactionPlan`
    /// derived directly from the PSBT bytes. Critically, we do NOT call
    /// `AnySigner.plan(...)` — that would re-select UTXOs and recompute fees,
    /// changing the broadcast tx_id and breaking NEAR Intents tracking.
    /// `targetAddress` populates `BitcoinSigningInput.toAddress` so WalletCore's
    /// pre-flight validation accepts the input (the frozen plan supersedes
    /// the field at signing time, but the validator still rejects empty).
    /// Exposed `internal` so per-chain unit tests can pin the structural
    /// shape (input count, scriptPubKey patterns, plan amount/change/fee).
    static func buildSigningInput(
        psbtBytes: Data,
        coin: CoinType,
        targetAddress: String = ""
    ) throws -> BitcoinSigningInput {
        guard !psbtBytes.isEmpty else { throw SwapKitLegacyP2PKHSignerError.missingPSBT }

        // 1. Parse BIP-174 framing.
        let framingPrefix: (cursor: PSBTCursor, globals: [Data: Data], unsignedTxBytes: Data)
        do {
            framingPrefix = try SwapKitPSBTParser.parseFraming(psbtBytes: psbtBytes)
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }

        // 2. Parse the legacy unsigned-tx body.
        let parsedTx = try parseLegacyUnsignedTx(framingPrefix.unsignedTxBytes)

        // 3. Drain the per-input and per-output maps off the cursor.
        var cursor = framingPrefix.cursor
        var inputMaps: [[Data: Data]] = []
        inputMaps.reserveCapacity(parsedTx.inputs.count)
        for _ in 0..<parsedTx.inputs.count {
            do { inputMaps.append(try cursor.readMap()) }
            catch let err as SwapKitPSBTParserError { throw mapParserError(err) }
        }
        // Per-output maps still parsed (forward-compat) even though we don't
        // read per-output fields.
        for _ in 0..<parsedTx.outputs.count {
            do { _ = try cursor.readMap() }
            catch let err as SwapKitPSBTParserError { throw mapParserError(err) }
        }

        // 4. Resolve per-input scriptPubKey + amount + keyHash. SwapKit
        // ships either NON_WITNESS_UTXO (full prev-tx, key `0x00`) or
        // WITNESS_UTXO (key `0x01`, BTC-style compact). Spec says legacy
        // P2PKH SHOULD use NON_WITNESS_UTXO (DOGE confirmed in spike); we
        // accept both for robustness against upstream changes.
        var inputs: [LegacyP2PKHInput] = []
        for (index, parsedInput) in parsedTx.inputs.enumerated() {
            let (amount, scriptPubKey) = try resolvePrevUtxo(
                inputMap: inputMaps[index],
                prevIndex: parsedInput.prevIndex,
                inputIndex: index
            )
            let keyHash = try assertP2PKHAndExtractKeyHash(
                scriptPubKey: scriptPubKey,
                inputIndex: index
            )
            inputs.append(LegacyP2PKHInput(
                prevTxIdLE: parsedInput.prevTxIdLE,
                prevIndex: parsedInput.prevIndex,
                sequence: parsedInput.sequence,
                amount: amount,
                scriptPubKey: scriptPubKey,
                keyHash: keyHash
            ))
        }

        // BitcoinSigningInput's pre-flight validator rejects empty `toAddress`
        // / `changeAddress` (WalletCore tries to derive a script from them
        // even when a frozen plan is present). We don't have a way to derive
        // a canonical chain-specific address from the raw scriptPubKey
        // without a CashAddr / base58check encoder per chain, so reuse the
        // SwapKit-returned `targetAddress` for both fields. The frozen plan
        // dictates the actual outputs at signing time — these fields are
        // structural placeholders.
        let resolvedTarget = targetAddress.isEmpty
            ? Self.legacyAddress(forHash: inputs[0].keyHash, coin: coin)
            : targetAddress
        return try assembleSigningInput(
            coin: coin,
            inputs: inputs,
            outputs: parsedTx.outputs,
            targetAddress: resolvedTarget,
            changeAddress: resolvedTarget
        )
    }

    // MARK: - Frozen plan assembly

    private static func assembleSigningInput(
        coin: CoinType,
        inputs: [LegacyP2PKHInput],
        outputs: [LegacyP2PKHOutput],
        targetAddress: String,
        changeAddress: String
    ) throws -> BitcoinSigningInput {
        guard !inputs.isEmpty, !outputs.isEmpty else {
            throw SwapKitLegacyP2PKHSignerError.planError("empty inputs or outputs")
        }
        let totalIn = inputs.reduce(Int64(0)) { $0 + $1.amount }
        let totalOut = outputs.reduce(Int64(0)) { $0 + $1.amount }
        let fee = totalIn - totalOut
        guard fee >= 0 else {
            throw SwapKitLegacyP2PKHSignerError.planError(
                "negative fee: inputs=\(totalIn) outputs=\(totalOut)"
            )
        }
        // Deposit output is conventionally output 0; change (if any) is the
        // remainder. The frozen plan exposes them as `amount` + `change`,
        // and WalletCore re-emits the same outputs verbatim from
        // `plan.utxos` + the deposit/change pair.
        let depositAmount = outputs[0].amount
        let changeAmount = outputs.dropFirst().reduce(Int64(0)) { $0 + $1.amount }

        // Build UTXO list. `outPoint.hash` is the prev-tx hash in **internal
        // little-endian** wire order (same convention as the native helper
        // at `UTXOChainsHelper.swift:125`).
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

        // Frozen plan. Critical: we do NOT call `AnySigner.plan(...)` here —
        // the replanner would re-select UTXOs against `byteFee` and could
        // produce a different on-chain tx_id, breaking NEAR Intents route
        // tracking.
        let plan = BitcoinTransactionPlan.with {
            $0.amount = depositAmount
            $0.availableAmount = totalIn
            $0.fee = fee
            $0.change = changeAmount
            $0.utxos = utxos
        }

        // `BitcoinSigningInput.scripts` map: keyHash.hex → P2PKH redeem
        // script. Mirrors the native send path
        // (`UTXOChainsHelper.getBitcoinSigningInput` lines 174-180).
        var scripts: [String: Data] = [:]
        for input in inputs {
            let redeem = BitcoinScript.buildPayToPublicKeyHash(hash: input.keyHash)
            scripts[input.keyHash.hexString] = redeem.data
        }

        var signingInput = BitcoinSigningInput.with {
            $0.hashType = BitcoinScript.hashTypeForCoin(coinType: coin)
            $0.byteFee = 1   // Frozen plan supersedes — replanner won't run.
            $0.useMaxAmount = false
            $0.amount = depositAmount
            $0.coinType = coin.rawValue
            // toAddress / changeAddress aren't authoritative once the plan
            // is frozen, but WalletCore's pre-flight validation rejects
            // empty strings. We pass the SwapKit-returned deposit address
            // (or fall back to the source-derived legacy address) so the
            // validator is happy. The frozen plan still authoritatively
            // dictates input/output bytes at preimage time.
            $0.toAddress = targetAddress
            $0.changeAddress = changeAddress
            $0.fixedDustThreshold = coin.getFixedDustThreshold()
        }
        signingInput.scripts = scripts
        signingInput.utxo = utxos
        signingInput.plan = plan
        return signingInput
    }

    // MARK: - Prev-UTXO resolution (NON_WITNESS_UTXO vs WITNESS_UTXO)

    /// SwapKit may ship either `PSBT_IN_NON_WITNESS_UTXO` (key `0x00`,
    /// embedded prev-tx — BIP-174's recommendation for legacy P2PKH inputs;
    /// DOGE fixture confirmed) or `PSBT_IN_WITNESS_UTXO` (key `0x01`, BTC-
    /// style compact amount + scriptPubKey). Both surface the same `amount`
    /// + `scriptPubKey` pair; the helper accepts whichever ships.
    private static func resolvePrevUtxo(
        inputMap: [Data: Data],
        prevIndex: UInt32,
        inputIndex: Int
    ) throws -> (amount: Int64, scriptPubKey: Data) {
        if let nonWitness = inputMap[Data([0x00])] {
            return try parseNonWitnessUtxo(
                nonWitness,
                prevIndex: prevIndex,
                inputIndex: inputIndex
            )
        }
        if let witness = inputMap[Data([0x01])] {
            return try parseWitnessUtxo(witness, inputIndex: inputIndex)
        }
        throw SwapKitLegacyP2PKHSignerError.missingPrevUtxo(inputIndex: inputIndex)
    }

    /// Parse a `PSBT_IN_NON_WITNESS_UTXO` record. The value is the full
    /// previous transaction in standard Bitcoin wire serialization (legacy
    /// pre-segwit shape — version, vin[], vout[], locktime). We extract
    /// `outputs[prevIndex]`.
    private static func parseNonWitnessUtxo(
        _ data: Data,
        prevIndex: UInt32,
        inputIndex: Int
    ) throws -> (amount: Int64, scriptPubKey: Data) {
        var c = PSBTCursor(data: data)
        do {
            _ = try c.readUInt32LE() // version
            let inCount = try c.readCompactSize()
            for _ in 0..<inCount {
                _ = try c.readBytes(32)       // prev txid
                _ = try c.readUInt32LE()       // prev index
                let sigLen = try c.readCompactSize()
                _ = try c.readBytes(Int(sigLen)) // scriptSig
                _ = try c.readUInt32LE()       // sequence
            }
            let outCount = try c.readCompactSize()
            guard UInt64(prevIndex) < outCount else {
                throw SwapKitLegacyP2PKHSignerError.invalidPrevUtxo(
                    inputIndex: inputIndex,
                    reason: "prev index \(prevIndex) >= output count \(outCount)"
                )
            }
            var amount: Int64 = 0
            var scriptPubKey = Data()
            for i in 0..<outCount {
                let unsignedAmount = try c.readUInt64LE()
                let scriptLen = try c.readCompactSize()
                let script = try c.readBytes(Int(scriptLen))
                if i == UInt64(prevIndex) {
                    amount = Int64(bitPattern: unsignedAmount)
                    scriptPubKey = script
                }
            }
            // We don't bother reading the locktime — once we've pulled the
            // target output, the rest is fluff for our purposes.
            return (amount, scriptPubKey)
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }
    }

    private static func parseWitnessUtxo(
        _ data: Data,
        inputIndex: Int
    ) throws -> (amount: Int64, scriptPubKey: Data) {
        var c = PSBTCursor(data: data)
        do {
            let unsignedAmount = try c.readUInt64LE()
            let scriptLen = try c.readCompactSize()
            let script = try c.readBytes(Int(scriptLen))
            guard c.isAtEnd else {
                throw SwapKitLegacyP2PKHSignerError.invalidPrevUtxo(
                    inputIndex: inputIndex,
                    reason: "WITNESS_UTXO has trailing bytes"
                )
            }
            return (Int64(bitPattern: unsignedAmount), script)
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }
    }

    // MARK: - Script-type assertion

    /// P2PKH scriptPubKey: 25 bytes — `OP_DUP OP_HASH160 PUSH20 <20-byte hash>
    /// OP_EQUALVERIFY OP_CHECKSIG` = `76 a9 14 <20> 88 ac`. Returns the
    /// 20-byte hash160. Throws `unsupportedScript` for any other shape.
    private static func assertP2PKHAndExtractKeyHash(
        scriptPubKey: Data,
        inputIndex: Int
    ) throws -> Data {
        guard scriptPubKey.count == 25,
              scriptPubKey[scriptPubKey.startIndex] == 0x76,         // OP_DUP
              scriptPubKey[scriptPubKey.startIndex + 1] == 0xa9,     // OP_HASH160
              scriptPubKey[scriptPubKey.startIndex + 2] == 0x14,     // PUSH 20
              scriptPubKey[scriptPubKey.startIndex + 23] == 0x88,    // OP_EQUALVERIFY
              scriptPubKey[scriptPubKey.startIndex + 24] == 0xac     // OP_CHECKSIG
        else {
            throw SwapKitLegacyP2PKHSignerError.unsupportedScript(
                "input #\(inputIndex) scriptPubKey is not P2PKH: \(scriptPubKey.hexString)"
            )
        }
        let start = scriptPubKey.startIndex + 3
        return Data(scriptPubKey[start..<(start + 20)])
    }

    // MARK: - Legacy unsigned-tx body parser

    private static func parseLegacyUnsignedTx(_ data: Data) throws -> ParsedLegacyTx {
        var c = PSBTCursor(data: data)
        do {
            let version = try c.readUInt32LE()
            // Note: the spec allows an optional segwit `marker+flag` (`0x00 0x01`)
            // after version, but PSBT unsigned-tx records strip witness data
            // (segwit txes are emitted without the marker in PSBT context).
            // DOGE/BCH/DASH have no segwit; this branch never fires for them.
            let inCount = try c.readCompactSize()
            var inputs: [(prevTxIdLE: Data, prevIndex: UInt32, sequence: UInt32)] = []
            for _ in 0..<inCount {
                let prevBytes = try c.readBytes(32)
                let prevIndex = try c.readUInt32LE()
                let sigLen = try c.readCompactSize()
                _ = try c.readBytes(Int(sigLen)) // scriptSig (empty in unsigned tx)
                let sequence = try c.readUInt32LE()
                inputs.append((prevTxIdLE: prevBytes, prevIndex: prevIndex, sequence: sequence))
            }
            let outCount = try c.readCompactSize()
            var outputs: [LegacyP2PKHOutput] = []
            for _ in 0..<outCount {
                let unsignedAmount = try c.readUInt64LE()
                let amount = Int64(bitPattern: unsignedAmount)
                let scriptLen = try c.readCompactSize()
                let script = try c.readBytes(Int(scriptLen))
                outputs.append(LegacyP2PKHOutput(amount: amount, scriptPubKey: script))
            }
            let locktime = try c.readUInt32LE()
            return ParsedLegacyTx(version: version, locktime: locktime, inputs: inputs, outputs: outputs)
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }
    }

    // MARK: - Address derivation from P2PKH hash160

    /// Build a legacy base58-check P2PKH address for `coin` from a 20-byte
    /// hash160. Used to derive a populated `changeAddress` from the source's
    /// pubkey hash (SwapKit only ships the user's UTXOs in PSBT inputs, so
    /// every input shares the same hash160 = the source's pubkey hash).
    /// We re-emit it via WalletCore's `BitcoinAddress` so the version byte
    /// matches the chain's mainnet (DOGE `0x1E`, BCH `0x00`, DASH `0x4C`).
    private static func legacyAddress(forHash hash: Data, coin: CoinType) -> String {
        var prefixed = Data([versionByte(for: coin)])
        prefixed.append(hash)
        if let address = BitcoinAddress(data: prefixed) {
            return address.description
        }
        // Defensive: if WalletCore's `BitcoinAddress` ever rejects (e.g.
        // BCH on certain SDK versions), reuse the raw hash hex as a last-
        // resort token. The frozen plan supersedes anyway — this string is
        // just a validator-satisfying placeholder.
        return hash.hexString
    }

    /// Mainnet P2PKH version bytes per chain. Listed inline rather than
    /// pulled from WalletCore because `CoinType` doesn't surface this byte
    /// directly through Swift bridging.
    private static func versionByte(for coin: CoinType) -> UInt8 {
        switch coin {
        case .dogecoin: return 0x1E       // DOGE `D…`
        case .bitcoinCash: return 0x00    // BCH legacy `1…` (CashAddr derives the same hash)
        case .dash: return 0x4C            // DASH `X…`
        case .zcash: return 0x1C           // ZEC `t1` legacy version byte (high-order)
        default: return 0x00
        }
    }

    // MARK: - Error mapping

    private static func mapParserError(_ err: SwapKitPSBTParserError) -> SwapKitLegacyP2PKHSignerError {
        switch err {
        case .missingPSBT: return .missingPSBT
        case .truncated: return .truncated
        case .invalidMagic: return .invalidMagic
        }
    }
}
