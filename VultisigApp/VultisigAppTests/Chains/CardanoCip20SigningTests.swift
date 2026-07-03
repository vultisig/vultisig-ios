//
//  CardanoCip20SigningTests.swift
//  VultisigApp
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

/// End-to-end wiring for the Cardano CIP-20 memo (label 674) via WalletCore
/// 4.7.0's native `CardanoSigningInput.auxiliaryData`.
///
/// The byte-level CBOR encoding is pinned in `CardanoCIP20Tests`; this suite
/// proves the encoder is wired into the signing path correctly:
///   - the memo becomes `auxiliaryData` on the pre-sign input,
///   - WalletCore commits `blake2b-256(auxDataCbor)` into the body at map key 7,
///   - the hand-built signed envelope embeds the same aux CBOR as element [3],
///   - the hand-built envelope is byte-identical to WalletCore's `AnySigner`
///     native output (the manual builder exists only because
///     `compileWithSignatures` crashes on Cardano — it must not diverge),
///   - the no-memo path is unchanged (aux stays the `0xF6` null sentinel),
///   - the dynamic fee prices the aux bytes so the memo is paid for.
final class CardanoCip20SigningTests: XCTestCase {

    private let cardanoAddress = "addr1v9g9wnzsutrxt7vcg4efdfwhagwh3x2f6hjwykk7acdpsfgyt4h2j"
    private let utxoHash = "f074134aabbfb13b8aec7cf5465b1e5a862d1cadc175d431c1d9339150db8a1d"

    /// mainnet minFeeA (lovelace per byte) — the size-based fee slope.
    private let minFeeA = 44

    private func makeCoin() throws -> Coin {
        let pubKey = "75be85178816db3bc71a4f3e64e5c89866d8b7daae827ba9cf4ecd1ed9e645d5"
        let chainCode = String(repeating: "0", count: 64)
        let coin = try CoinFactory.create(
            asset: TokensStore.Token.cardano,
            publicKeyECDSA: pubKey,
            publicKeyEdDSA: pubKey,
            hexChainCode: chainCode,
            isDerived: false
        )
        coin.address = cardanoAddress
        return coin
    }

    private func makePayload(
        coin: Coin,
        toAmount: BigInt,
        utxos: [UtxoInfo],
        byteFee: BigInt,
        memo: String?
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: cardanoAddress,
            toAmount: toAmount,
            chainSpecific: .Cardano(byteFee: byteFee, sendMaxAmount: false, ttl: 190_000_000),
            utxos: utxos,
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "ECDSAKey",
            vaultLocalPartyID: "localPartyID",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func singleUtxo() -> [UtxoInfo] {
        [UtxoInfo(hash: utxoHash, amount: 10_000_000, index: 0)]
    }

    // MARK: - Pre-sign input wiring

    func testPreSignInputSetsAuxiliaryDataWhenMemoPresent() throws {
        let coin = try makeCoin()
        let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: singleUtxo(), byteFee: 180_000, memo: "hello world")

        let input = try CardanoHelper.getPreSignedInputData(keysignPayload: payload)

        let expected = CardanoCIP20.buildAuxData(memo: "hello world").auxDataCbor
        XCTAssertEqual(input.auxiliaryData, expected)
        // Byte-parity anchor: matches the pinned SDK golden vector.
        XCTAssertEqual(input.auxiliaryData.hexString, "a11902a2a1636d7367816b" + Data("hello world".utf8).hexString)
    }

    func testPreSignInputHasNoAuxiliaryDataWhenMemoNil() throws {
        let coin = try makeCoin()
        let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: singleUtxo(), byteFee: 180_000, memo: nil)

        let input = try CardanoHelper.getPreSignedInputData(keysignPayload: payload)
        XCTAssertTrue(input.auxiliaryData.isEmpty)
    }

    func testPreSignInputHasNoAuxiliaryDataWhenMemoEmpty() throws {
        let coin = try makeCoin()
        let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: singleUtxo(), byteFee: 180_000, memo: "")

        let input = try CardanoHelper.getPreSignedInputData(keysignPayload: payload)
        XCTAssertTrue(input.auxiliaryData.isEmpty)
    }

    // MARK: - Body commits the aux hash at map key 7 (byte parity)

    /// With a memo set, the pre-image body (what MPC signs and hashes to the
    /// Cardano txid) must carry `auxiliary_data_hash` at CBOR map key 7 —
    /// `07 5820 <blake2b-256(auxDataCbor)>`. This is WalletCore committing the
    /// aux hash natively; every co-signer that emits the identical aux CBOR
    /// therefore produces a byte-identical body ⇒ matching Blake2b sighash.
    func testBodyCommitsAuxHashAtKey7WhenMemoPresent() throws {
        let coin = try makeCoin()
        let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: singleUtxo(), byteFee: 180_000, memo: "hello world")

        let (_, auxDataHash) = CardanoCIP20.buildAuxData(memo: "hello world")
        let body = try preSignBody(for: payload)

        XCTAssertTrue(
            body.hexString.contains("075820" + auxDataHash.hexString),
            "body must carry auxiliary_data_hash (key 7 = blake2b-256 of the aux CBOR)"
        )
    }

    func testBodyHasNoAuxHashWhenMemoAbsent() throws {
        let coin = try makeCoin()
        let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: singleUtxo(), byteFee: 180_000, memo: nil)

        let body = try preSignBody(for: payload)
        // No key-7 aux-hash field: the 32-byte `5820` byte-string head only
        // appears for the aux hash in a simple ADA send.
        XCTAssertFalse(body.hexString.contains("075820"), "no memo ⇒ no auxiliary_data_hash in the body")
    }

    // MARK: - Signed envelope embeds the aux CBOR as element [3]

    func testEnvelopeEmbedsAuxCborAsElement3() throws {
        let body = Data(hexString: "a10200")!
        let pubkey = Data(repeating: 0x11, count: 32)
        let sig = Data(repeating: 0x22, count: 64)
        let aux = CardanoCIP20.buildAuxData(memo: "hello world").auxDataCbor

        let signed = try CardanoSignedTxBuilder.build(txBody: body, publicKey: pubkey, signature: sig, auxData: aux)

        // Envelope tail is `f5 <aux>` (is_valid = true, then the aux CBOR) —
        // NOT the `f6` null sentinel.
        XCTAssertTrue(signed.hexString.hasSuffix("f5" + aux.hexString))
        XCTAssertFalse(signed.hexString.hasSuffix("f6"))
    }

    func testEnvelopeKeepsNullSentinelWhenNoAux() throws {
        let body = Data(hexString: "a10200")!
        let pubkey = Data(repeating: 0x11, count: 32)
        let sig = Data(repeating: 0x22, count: 64)

        let signed = try CardanoSignedTxBuilder.build(txBody: body, publicKey: pubkey, signature: sig)
        XCTAssertTrue(signed.hexString.hasSuffix("f5f6"))
    }

    // MARK: - Manual builder vs AnySigner native output (byte-for-byte)

    /// The hand-built envelope must share every parity-critical byte with what
    /// WalletCore's `AnySigner` emits natively when `auxiliaryData` is set: the
    /// transaction body (⇒ txid + MPC sighash), the vkey/signature witness, and
    /// the CIP-20 aux element. We drive `AnySigner.sign` with a self-consistent
    /// HD key, extract its body/witness/aux, and rebuild the envelope via
    /// `CardanoSignedTxBuilder`.
    ///
    /// The two envelopes differ ONLY in framing: `AnySigner` emits the 3-element
    /// Shelley array `[body, witness, aux]` (leading `0x83`, no `is_valid`),
    /// while the manual builder emits the modern SDK/mainnet-verified 4-element
    /// `[body, witness, is_valid=true(0xF5), aux]` (leading `0x84`). That
    /// framing byte does not enter the txid (`blake2b-256(body)`), so it does
    /// not affect signing or cross-device parity — the manual path (used because
    /// `compileWithSignatures` crashes on Cardano) matches the SDK format that
    /// `CardanoSignedTxBuilderTests` pins against the mainnet-verified vector.
    func testManualEnvelopeSharesBodyWitnessAndAuxWithAnySigner() throws {
        // Fixed BIP39 mnemonic ⇒ deterministic Cardano key + address. The key
        // must own the UTXO/change address for AnySigner to sign it.
        guard let wallet = HDWallet(
            mnemonic: "team engine square letter hero song dizzy scrub tornado fabric divert saddle",
            passphrase: ""
        ) else {
            return XCTFail("failed to derive HDWallet")
        }
        let ownerAddress = wallet.getAddressForCoin(coin: .cardano)
        let key = wallet.getKeyForCoin(coin: .cardano)

        let (auxDataCbor, auxDataHash) = CardanoCIP20.buildAuxData(memo: "hello world")
        let forcedFee: UInt64 = 180_000

        func makeInput(withKey: Bool) -> CardanoSigningInput {
            var input = CardanoSigningInput.with {
                $0.transferMessage = CardanoTransfer.with {
                    $0.toAddress = cardanoAddress
                    $0.changeAddress = ownerAddress
                    $0.amount = 2_000_000
                    $0.forceFee = forcedFee
                }
                $0.ttl = 190_000_000
                $0.auxiliaryData = auxDataCbor
            }
            input.utxos.append(CardanoTxInput.with {
                $0.outPoint = CardanoOutPoint.with {
                    $0.txHash = Data(hexString: utxoHash)!
                    $0.outputIndex = 0
                }
                $0.amount = 10_000_000
                $0.address = ownerAddress
            })
            if withKey { input.privateKey = [key.data] }
            return input
        }

        // 1) Native AnySigner envelope (3-element Shelley framing).
        let output: CardanoSigningOutput = AnySigner.sign(input: makeInput(withKey: true), coin: .cardano)
        XCTAssertEqual(output.error, .ok, output.errorMessage)
        let anySignerTx = output.encoded
        XCTAssertFalse(anySignerTx.isEmpty)
        XCTAssertEqual(anySignerTx[anySignerTx.startIndex], 0x83, "AnySigner frames as a 3-element array")

        // 2) Manual path body: compile the same input (no key) → pre-image body.
        var noKey = makeInput(withKey: false)
        let plan: CardanoTransactionPlan = AnySigner.plan(input: noKey, coin: .cardano)
        XCTAssertEqual(plan.error, .ok)
        noKey.plan = plan
        noKey.transferMessage.forceFee = plan.fee
        let inputData = try noKey.serializedData()
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let pre = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(pre.errorMessage.isEmpty, pre.errorMessage)
        let body = pre.data

        // The compiler body (what MPC signs) must equal AnySigner's element [0]
        // and carry the aux hash at key 7 — this is the parity-critical byte
        // range (it determines the txid = blake2b-256(body)).
        XCTAssertTrue(anySignerTx.count > 1 + body.count, "envelope shorter than its body")
        XCTAssertEqual(anySignerTx[anySignerTx.startIndex + 1 ..< anySignerTx.startIndex + 1 + body.count], body,
                       "compiler body must equal AnySigner's transaction body")
        XCTAssertTrue(body.hexString.contains("075820" + auxDataHash.hexString))

        // 3) Extract AnySigner's own witness `a1 00 81 82 5820 <vkey32> 5840 <sig64>`
        //    (104 bytes) and the aux element that follows it (3-element framing:
        //    the witness is directly followed by the aux, no is_valid byte).
        let witnessStart = anySignerTx.startIndex + 1 + body.count
        XCTAssertEqual(anySignerTx[witnessStart], 0xA1, "witness set must start with map(1)")
        let witness = Data(anySignerTx[witnessStart ..< witnessStart + 104])
        let anyAux = Data(anySignerTx[(witnessStart + 104)...])
        XCTAssertEqual(anyAux, auxDataCbor, "AnySigner embeds our CIP-20 aux CBOR verbatim")

        // AnySigner's whole envelope is exactly `83 | body | witness | aux`.
        XCTAssertEqual(anySignerTx, Data([0x83]) + body + witness + auxDataCbor)

        // 4) Rebuild via the production manual builder from AnySigner's own body
        //    + vkey + sig. It reproduces the SAME body/witness/aux, reframed as
        //    the 4-element `84 | body | witness | f5 | aux` SDK/mainnet format —
        //    i.e. byte-identical to AnySigner except the `is_valid` framing.
        let vkey = Data(witness[witness.startIndex + 6 ..< witness.startIndex + 38])
        let sig = Data(witness[witness.startIndex + 40 ..< witness.startIndex + 104])
        let manual = try CardanoSignedTxBuilder.build(
            txBody: body,
            publicKey: vkey,
            signature: sig,
            auxData: auxDataCbor
        )
        XCTAssertEqual(manual, Data([0x84]) + body + witness + Data([0xF5]) + auxDataCbor,
                       "manual envelope = AnySigner's body/witness/aux reframed as the 4-element SDK format")
    }

    // MARK: - Fee prices the aux bytes

    /// A memo enlarges the transaction (body key-7 field + the aux element), so
    /// the initiator's size-based dynamic fee must grow by at least the cost of
    /// the auxiliary-data bytes — otherwise the network rejects the memo tx with
    /// `FeeTooSmallUTxO`. Verifies WalletCore's 4.7.0 planner prices
    /// `auxiliaryData` (the SDK prices it explicitly via `auxDataCbor.length`).
    func testDynamicFeePricesCip20AuxiliaryDataBytes() throws {
        let coin = try makeCoin()
        let utxos = singleUtxo()
        let memo = String(repeating: "m", count: 500)
        let auxLen = CardanoCIP20.buildAuxData(memo: memo).auxDataCbor.count

        let feeNoMemo = CardanoHelper.estimateDynamicByteFee(
            keysignPayload: makePayload(coin: coin, toAmount: 2_000_000, utxos: utxos, byteFee: 0, memo: nil))
        let feeWithMemo = CardanoHelper.estimateDynamicByteFee(
            keysignPayload: makePayload(coin: coin, toAmount: 2_000_000, utxos: utxos, byteFee: 0, memo: memo))

        XCTAssertGreaterThanOrEqual(
            feeWithMemo - feeNoMemo, BigInt(minFeeA * auxLen),
            "the \(auxLen)-byte CIP-20 aux data must be priced into the dynamic fee"
        )
    }

    // MARK: - Helpers

    /// Drive the real pre-sign path and return the tx body (element [0]) that
    /// MPC hashes and signs.
    private func preSignBody(for payload: KeysignPayload) throws -> Data {
        let inputData = try CardanoHelper.getCardanoPreSignInputData(keysignPayload: payload)
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let pre = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(pre.errorMessage.isEmpty, pre.errorMessage)
        return pre.data
    }
}
