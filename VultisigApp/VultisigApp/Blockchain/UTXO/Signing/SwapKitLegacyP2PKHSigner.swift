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
    case unsupportedVersion(UInt32)
    case malformedPSBT(reason: String)
    case unsupportedScript(String)
    case missingPrevUtxo(inputIndex: Int)
    case pubkeyDoesNotMatchInput(inputIndex: Int)
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
        case .unsupportedVersion(let version):
            return "SwapKit PSBT unsigned-tx version \(version) is unsupported; only version 1 and 2 are reproducible on this signing path"
        case .malformedPSBT(let reason):
            return "SwapKit PSBT is malformed: \(reason)"
        case .unsupportedScript(let detail):
            return "SwapKit PSBT script not supported: \(detail)"
        case .missingPrevUtxo(let i):
            return "SwapKit PSBT input #\(i) is missing prev-tx UTXO record"
        case .pubkeyDoesNotMatchInput(let i):
            return "SwapKit PSBT input #\(i) is locked to a different key than the signing public key"
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

    /// Pre-signing hashes for a DOGE/BCH/DASH PSBT, one per input, computed
    /// directly from the parsed PSBT (see `MARK: - Direct sighash + assembly`
    /// below) rather than through WalletCore's legacy Bitcoin signer — that
    /// signer has no version input and always emits version 1, silently
    /// dropping the PSBT's declared version/locktime.
    static func preSigningHashes(
        psbtBytes: Data,
        coin: CoinType
    ) throws -> [String] {
        let (tx, inputs) = try parseForSigning(psbtBytes: psbtBytes)
        return perInputSighashes(tx: tx, inputs: inputs, coin: coin)
            .map { $0.hexString }
            .sorted()
    }

    /// Assemble a signed legacy P2PKH transaction directly: verify each MPC
    /// signature against its per-input sighash, then serialize the tx with
    /// the PSBT's own version/locktime and the real scriptSigs.
    static func compileSignedTransaction(
        psbtBytes: Data,
        coin: CoinType,
        signatures: [String: TssKeysignResponse],
        pubKeyHex: String
    ) throws -> SignedTransactionResult {
        guard let pubkeyData = Data(hexString: pubKeyHex),
              let publicKey = PublicKey(data: pubkeyData, type: .secp256k1)
        else {
            throw SwapKitLegacyP2PKHSignerError.invalidPublicKey(pubKeyHex)
        }
        let (tx, inputs) = try parseForSigning(psbtBytes: psbtBytes)
        let ourKeyHash = Hash.ripemd(data: Hash.sha256(data: pubkeyData))
        for (index, input) in inputs.enumerated() where input.keyHash != ourKeyHash {
            throw SwapKitLegacyP2PKHSignerError.pubkeyDoesNotMatchInput(inputIndex: index)
        }
        let sighashes = perInputSighashes(tx: tx, inputs: inputs, coin: coin)
        let signatureProvider = SignatureProvider(signatures: signatures)
        let type = sighashType(for: coin)

        var scriptSigs: [Data] = []
        scriptSigs.reserveCapacity(inputs.count)
        for sighash in sighashes {
            let derSignature = signatureProvider.getDerSignature(preHash: sighash)
            guard publicKey.verifyAsDER(signature: derSignature, message: sighash) else {
                throw SwapKitLegacyP2PKHSignerError.signatureVerifyFailed
            }
            var sigPlusType = derSignature
            sigPlusType.append(UInt8(type & 0xff))
            scriptSigs.append(pushData(sigPlusType) + pushData(pubkeyData))
        }

        let rawTransaction = serializeSignedTransaction(tx: tx, inputs: inputs, scriptSigs: scriptSigs)
        let transactionHash = Data(hash256(rawTransaction).reversed()).hexString
        return SignedTransactionResult(
            rawTransaction: rawTransaction.hexString,
            transactionHash: transactionHash
        )
    }

    /// Build the `BitcoinSigningInput` with a **frozen** `BitcoinTransactionPlan`
    /// derived directly from the PSBT bytes. No longer used by
    /// `preSigningHashes`/`compileSignedTransaction` (see the direct
    /// sighash + assembly path below) — kept so per-chain unit tests can
    /// still pin the structural shape (input count, scriptPubKey patterns,
    /// plan amount/change/fee) independently of the signing math.
    static func buildSigningInput(
        psbtBytes: Data,
        coin: CoinType,
        targetAddress: String = ""
    ) throws -> BitcoinSigningInput {
        let (tx, inputs) = try parseForSigning(psbtBytes: psbtBytes)
        // Output scriptPubKeys come from the PSBT body verbatim. WalletCore's
        // `BitcoinSigner` reconstructs each output from `toAddress` /
        // `changeAddress` (NOT from the frozen plan — the plan dictates
        // amounts/fees/UTXOs but the output scripts are derived from the
        // address strings on `BitcoinSigningInput`). To preserve the PSBT's
        // actual recipients we derive both addresses from the parsed P2PKH
        // hash160s and reject any non-P2PKH output (OP_RETURN, P2SH, P2WSH
        // we can't faithfully re-emit through the address-only API).
        return try assembleSigningInput(
            coin: coin,
            inputs: inputs,
            outputs: tx.outputs,
            targetAddressHint: targetAddress
        )
    }

    // MARK: - Shared PSBT parsing

    /// Steps shared by every entry point: parse BIP-174 framing, parse the
    /// legacy unsigned-tx body (validates version — see
    /// `parseLegacyUnsignedTx`), drain the per-input/output maps, and
    /// resolve each input's prev-tx scriptPubKey + amount + P2PKH key hash.
    private static func parseForSigning(
        psbtBytes: Data
    ) throws -> (tx: ParsedLegacyTx, inputs: [LegacyP2PKHInput]) {
        guard !psbtBytes.isEmpty else { throw SwapKitLegacyP2PKHSignerError.missingPSBT }

        let framingPrefix: (cursor: PSBTCursor, globals: [Data: Data], unsignedTxBytes: Data)
        do {
            framingPrefix = try SwapKitPSBTParser.parseFraming(psbtBytes: psbtBytes)
        } catch let err as SwapKitPSBTParserError {
            throw mapParserError(err)
        }

        let parsedTx = try parseLegacyUnsignedTx(framingPrefix.unsignedTxBytes)

        var cursor = framingPrefix.cursor
        var inputMaps: [[Data: Data]] = []
        inputMaps.reserveCapacity(parsedTx.inputs.count)
        for _ in 0..<parsedTx.inputs.count {
            do {
                inputMaps.append(try cursor.readMap())
            } catch let err as SwapKitPSBTParserError {
                throw mapParserError(err)
            }
        }
        // Per-output maps still parsed (forward-compat) even though we don't
        // read per-output fields.
        for _ in 0..<parsedTx.outputs.count {
            do {
                _ = try cursor.readMap()
            } catch let err as SwapKitPSBTParserError {
                throw mapParserError(err)
            }
        }

        // Resolve per-input scriptPubKey + amount + keyHash. SwapKit ships
        // either NON_WITNESS_UTXO (full prev-tx, key `0x00`) or WITNESS_UTXO
        // (key `0x01`, BTC-style compact). Spec says legacy P2PKH SHOULD use
        // NON_WITNESS_UTXO (DOGE confirmed in spike); we accept both for
        // robustness against upstream changes.
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
        try validateOutputShape(inputs: inputs, outputs: parsedTx.outputs)
        return (parsedTx, inputs)
    }

    /// SwapKit always ships one deposit output plus an optional change
    /// output, and every output must be a P2PKH we can faithfully re-emit
    /// (anything else — OP_RETURN, P2SH, P2WSH, multisig — we hard-reject so
    /// we never broadcast a tx that differs from the PSBT's intent).
    private static func validateOutputShape(inputs: [LegacyP2PKHInput], outputs: [LegacyP2PKHOutput]) throws {
        guard !inputs.isEmpty, !outputs.isEmpty else {
            throw SwapKitLegacyP2PKHSignerError.planError("empty inputs or outputs")
        }
        guard outputs.count <= 2 else {
            throw SwapKitLegacyP2PKHSignerError.unsupportedScript(
                "PSBT has \(outputs.count) outputs; legacy signer expects 1 deposit + optional 1 change"
            )
        }
        for (idx, out) in outputs.enumerated() {
            _ = try assertP2PKHForOutput(scriptPubKey: out.scriptPubKey, outputIndex: idx)
        }
    }

    // MARK: - Direct sighash + assembly (preserves PSBT version/locktime)
    //
    // WalletCore's legacy Bitcoin `SigningInput` proto has no version field —
    // its C++/Rust signer always constructs a version-1 `Transaction`
    // regardless of what's asked. Going through it (as this file did before
    // issue #5483) silently re-versions every broadcast to 1 and drops any
    // non-zero locktime. Computing the sighash and assembling the signed tx
    // directly — the same approach `BitcoinPsbtSigner` already uses for
    // BTC's segwit PSBT path — lets us honor whatever version/locktime the
    // PSBT declares.

    /// BCH signs with a BIP-143-style digest under SIGHASH_FORKID (WalletCore's
    /// own Rust `ForkIdSighash` delegates verbatim to its witness-v0 digest —
    /// this mirrors that, with the P2PKH scriptPubKey standing in for the
    /// witness-program-derived scriptCode). DOGE and DASH have no fork-id
    /// history and use the original pre-BIP143 whole-tx-substitution sighash.
    private static func isForkIdCoin(_ coin: CoinType) -> Bool {
        coin == .bitcoinCash
    }

    /// SIGHASH_ALL, with SIGHASH_FORKID (`0x40`) added for BCH.
    private static func sighashType(for coin: CoinType) -> UInt32 {
        isForkIdCoin(coin) ? 0x41 : 0x01
    }

    private static func perInputSighashes(
        tx: ParsedLegacyTx,
        inputs: [LegacyP2PKHInput],
        coin: CoinType
    ) -> [Data] {
        let type = sighashType(for: coin)
        let forkId = isForkIdCoin(coin)
        return inputs.indices.map { index in
            forkId
                ? forkIdSighash(tx: tx, inputs: inputs, signingIndex: index, sighashType: type)
                : legacySighash(tx: tx, inputs: inputs, signingIndex: index, sighashType: type)
        }
    }

    /// Classic pre-BIP143 sighash (DOGE, DASH — SIGHASH_ALL, no
    /// ANYONECANPAY, no fork id): substitute the signed input's scriptSig
    /// with its scriptPubKey, empty every other input's scriptSig,
    /// serialize the whole transaction, append the 4-byte LE sighash type,
    /// hash256.
    private static func legacySighash(
        tx: ParsedLegacyTx,
        inputs: [LegacyP2PKHInput],
        signingIndex: Int,
        sighashType: UInt32
    ) -> Data {
        var data = Data()
        data.append(writeUInt32LE(tx.version))
        data.append(writeVarInt(UInt64(inputs.count)))
        for (index, input) in inputs.enumerated() {
            data.append(input.prevTxIdLE)
            data.append(writeUInt32LE(input.prevIndex))
            let scriptSig = index == signingIndex ? input.scriptPubKey : Data()
            data.append(writeVarInt(UInt64(scriptSig.count)))
            data.append(scriptSig)
            data.append(writeUInt32LE(input.sequence))
        }
        data.append(writeVarInt(UInt64(tx.outputs.count)))
        for output in tx.outputs {
            data.append(writeUInt64LE(UInt64(bitPattern: output.amount)))
            data.append(writeVarInt(UInt64(output.scriptPubKey.count)))
            data.append(output.scriptPubKey)
        }
        data.append(writeUInt32LE(tx.locktime))
        data.append(writeUInt32LE(sighashType))
        return hash256(data)
    }

    /// BIP-143-with-fork-id sighash (BCH). Structurally identical to
    /// `BitcoinPsbtSigner`'s P2WPKH digest, with the P2PKH scriptPubKey
    /// standing in for the witness-program-derived scriptCode.
    private static func forkIdSighash(
        tx: ParsedLegacyTx,
        inputs: [LegacyP2PKHInput],
        signingIndex: Int,
        sighashType: UInt32
    ) -> Data {
        let hashPrevouts = hash256(inputs.reduce(Data()) { acc, input in
            acc + input.prevTxIdLE + writeUInt32LE(input.prevIndex)
        })
        let hashSequence = hash256(inputs.reduce(Data()) { acc, input in
            acc + writeUInt32LE(input.sequence)
        })
        let hashOutputs = hash256(tx.outputs.reduce(Data()) { acc, output in
            acc + writeUInt64LE(UInt64(bitPattern: output.amount))
                + writeVarInt(UInt64(output.scriptPubKey.count)) + output.scriptPubKey
        })
        let input = inputs[signingIndex]

        var preimage = Data()
        preimage.append(writeUInt32LE(tx.version))
        preimage.append(hashPrevouts)
        preimage.append(hashSequence)
        preimage.append(input.prevTxIdLE)
        preimage.append(writeUInt32LE(input.prevIndex))
        preimage.append(writeVarInt(UInt64(input.scriptPubKey.count)))
        preimage.append(input.scriptPubKey)
        preimage.append(writeUInt64LE(UInt64(input.amount)))
        preimage.append(writeUInt32LE(input.sequence))
        preimage.append(hashOutputs)
        preimage.append(writeUInt32LE(tx.locktime))
        preimage.append(writeUInt32LE(sighashType))
        return hash256(preimage)
    }

    /// Serializes the fully-signed legacy transaction: version, inputs (with
    /// the real `scriptSig` per input), outputs, locktime — all lifted
    /// verbatim from the parsed PSBT except for `scriptSigs`, which don't
    /// exist until signing.
    private static func serializeSignedTransaction(
        tx: ParsedLegacyTx,
        inputs: [LegacyP2PKHInput],
        scriptSigs: [Data]
    ) -> Data {
        var data = Data()
        data.append(writeUInt32LE(tx.version))
        data.append(writeVarInt(UInt64(inputs.count)))
        for (index, input) in inputs.enumerated() {
            data.append(input.prevTxIdLE)
            data.append(writeUInt32LE(input.prevIndex))
            let scriptSig = scriptSigs[index]
            data.append(writeVarInt(UInt64(scriptSig.count)))
            data.append(scriptSig)
            data.append(writeUInt32LE(input.sequence))
        }
        data.append(writeVarInt(UInt64(tx.outputs.count)))
        for output in tx.outputs {
            data.append(writeUInt64LE(UInt64(bitPattern: output.amount)))
            data.append(writeVarInt(UInt64(output.scriptPubKey.count)))
            data.append(output.scriptPubKey)
        }
        data.append(writeUInt32LE(tx.locktime))
        return data
    }

    /// Bitcoin script push: `<len><data>` for data under 76 bytes
    /// (`OP_PUSHDATA1`'s threshold) — DER signatures and compressed pubkeys
    /// never reach it, but this stays correct rather than assuming.
    private static func pushData(_ data: Data) -> Data {
        var out = Data()
        if data.count < 0x4c {
            out.append(UInt8(data.count))
        } else if data.count <= 0xff {
            out.append(0x4c)
            out.append(UInt8(data.count))
        } else {
            out.append(0x4d)
            out.append(UInt8(data.count & 0xff))
            out.append(UInt8((data.count >> 8) & 0xff))
        }
        out.append(data)
        return out
    }

    // MARK: - Frozen plan assembly (test-only shape, see `buildSigningInput`)

    private static func assembleSigningInput(
        coin: CoinType,
        inputs: [LegacyP2PKHInput],
        outputs: [LegacyP2PKHOutput],
        targetAddressHint: String
    ) throws -> BitcoinSigningInput {
        let outputKeyHashes = try outputs.enumerated().map { (idx, out) -> Data in
            try assertP2PKHForOutput(scriptPubKey: out.scriptPubKey, outputIndex: idx)
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
        // Derive the addresses that round-trip back to the exact
        // scriptPubKeys the PSBT shipped. `targetAddressHint` is only used
        // if address derivation from a hash160 fails for `coin` (shouldn't
        // happen for the supported chains — DOGE/BCH/DASH all decode cleanly
        // via single-byte base58check).
        let depositAddress = Self.legacyAddress(forHash: outputKeyHashes[0], coin: coin)
            ?? targetAddressHint
        let changeAddress: String
        if outputs.count >= 2 {
            changeAddress = Self.legacyAddress(forHash: outputKeyHashes[1], coin: coin)
                ?? targetAddressHint
        } else {
            // No change output — point `changeAddress` at the source pubkey
            // hash so the WalletCore validator accepts the input. The plan's
            // `change = 0` means WalletCore won't actually emit a change
            // output, so the address is a structural placeholder.
            changeAddress = Self.legacyAddress(forHash: inputs[0].keyHash, coin: coin)
                ?? targetAddressHint
        }

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
            // toAddress / changeAddress drive the output scripts WalletCore
            // emits. We derive them from the PSBT's actual output hash160s
            // (above) so the rebuilt tx is byte-identical to the PSBT's
            // intended outputs — preserves the NEAR Intents route's
            // `tx_id` and the deposit destination.
            $0.toAddress = depositAddress
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

    /// Output-side P2PKH assertion. Same shape check as
    /// `assertP2PKHAndExtractKeyHash` but tags the error with `output #N`
    /// so non-P2PKH output rejections (OP_RETURN, P2SH, P2WSH) read
    /// distinctly from input-side rejections in logs.
    private static func assertP2PKHForOutput(
        scriptPubKey: Data,
        outputIndex: Int
    ) throws -> Data {
        guard scriptPubKey.count == 25,
              scriptPubKey[scriptPubKey.startIndex] == 0x76,
              scriptPubKey[scriptPubKey.startIndex + 1] == 0xa9,
              scriptPubKey[scriptPubKey.startIndex + 2] == 0x14,
              scriptPubKey[scriptPubKey.startIndex + 23] == 0x88,
              scriptPubKey[scriptPubKey.startIndex + 24] == 0xac
        else {
            throw SwapKitLegacyP2PKHSignerError.unsupportedScript(
                "output #\(outputIndex) scriptPubKey is not P2PKH: \(scriptPubKey.hexString)"
            )
        }
        let start = scriptPubKey.startIndex + 3
        return Data(scriptPubKey[start..<(start + 20)])
    }

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
            //
            // Only versions 1 and 2 are reproducible: the direct sighash +
            // assembly below re-serializes this exact version, so any value
            // is technically "supported" mechanically — but a version we've
            // never observed in the wild is more likely a wire-format change
            // we haven't accounted for than a legitimate new value, so we
            // fail loudly rather than sign and broadcast a guess.
            guard version == 1 || version == 2 else {
                throw SwapKitLegacyP2PKHSignerError.unsupportedVersion(version)
            }
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
    /// hash160. Used to derive the deposit + change `toAddress` strings
    /// WalletCore emits as output scripts. Version-byte / prefix per chain:
    /// DOGE `0x1E` (`D…`), BCH `0x00` legacy (`1…` — CashAddr derives the
    /// same hash), DASH `0x4C` (`X…`), ZEC `0x1C 0xB8` (`t1…`, two-byte
    /// transparent prefix). Returns `nil` if no prefix is defined for the
    /// coin — caller falls back to the SwapKit `targetAddress` hint to
    /// satisfy WalletCore's non-empty validator.
    static func legacyAddress(forHash hash: Data, coin: CoinType) -> String? {
        guard let prefix = versionPrefix(for: coin) else { return nil }
        var data = Data(prefix)
        data.append(hash)
        return Base58.encode(data: data)
    }

    /// Mainnet P2PKH version prefix per chain. Multi-byte for chains whose
    /// transparent address namespace uses a longer prefix (ZEC = 2 bytes).
    /// Listed inline rather than pulled from WalletCore because `CoinType`
    /// doesn't surface the prefix bytes through Swift bridging.
    private static func versionPrefix(for coin: CoinType) -> [UInt8]? {
        switch coin {
        case .dogecoin: return [0x1E]            // DOGE `D…`
        case .bitcoinCash: return [0x00]         // BCH legacy `1…` (CashAddr derives the same hash)
        case .dash: return [0x4C]                 // DASH `X…`
        case .zcash: return [0x1C, 0xB8]          // ZEC `t1…` (two-byte transparent prefix)
        default: return nil
        }
    }

    // MARK: - Error mapping

    private static func mapParserError(_ err: SwapKitPSBTParserError) -> SwapKitLegacyP2PKHSignerError {
        switch err {
        case .missingPSBT: return .missingPSBT
        case .truncated: return .truncated
        case .invalidMagic: return .invalidMagic
        case .malformed(let reason): return .malformedPSBT(reason: reason)
        }
    }
}

// MARK: - Byte helpers (mirrors `BitcoinPsbtSigner`'s private helpers)

private func writeUInt32LE(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func writeUInt64LE(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

/// Bitcoin CompactSize varint encoding.
private func writeVarInt(_ value: UInt64) -> Data {
    if value < 0xFD {
        return Data([UInt8(value)])
    }
    if value <= 0xFFFF {
        var buf = Data([0xFD])
        buf.append(writeUInt32LE(UInt32(value)).prefix(2))
        return buf
    }
    if value <= 0xFFFFFFFF {
        var buf = Data([0xFE])
        buf.append(writeUInt32LE(UInt32(value)))
        return buf
    }
    var buf = Data([0xFF])
    buf.append(writeUInt64LE(value))
    return buf
}

/// double-SHA256 (Bitcoin's hash256).
private func hash256(_ data: Data) -> Data {
    Hash.sha256SHA256(data: data)
}
