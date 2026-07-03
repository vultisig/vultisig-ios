//
//  CardanoDynamicFeeTests.swift
//  VultisigApp
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

/// Covers the Cardano "shared dynamic fee" model:
///
/// 1. `byteFee` is a shared payload constant — every co-signing device forces it
///    verbatim into the signed body, so the body fee always equals the
///    transmitted `byteFee` (byte-identical bodies ⇒ Blake2b sighash parity).
/// 2. The INITIATOR computes that `byteFee` once via
///    `CardanoHelper.estimateDynamicByteFee` as a real size-based fee
///    (`minFeeA*size + minFeeB`), which scales with tx size and exceeds the old
///    flat 180k floor for large / multi-input bodies (the fix for
///    `FeeTooSmallUTxO` rejections).
final class CardanoDynamicFeeTests: XCTestCase {

    private let cardanoAddress = "addr1v9g9wnzsutrxt7vcg4efdfwhagwh3x2f6hjwykk7acdpsfgyt4h2j"
    private let utxoHash = "f074134aabbfb13b8aec7cf5465b1e5a862d1cadc175d431c1d9339150db8a1d"

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

    private func makePayload(coin: Coin, toAmount: BigInt, utxos: [UtxoInfo], byteFee: BigInt) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: cardanoAddress,
            toAmount: toAmount,
            chainSpecific: .Cardano(byteFee: byteFee, sendMaxAmount: false, ttl: 190_000_000),
            utxos: utxos,
            memo: nil,
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

    /// Drive the real signing path and return (fee baked into the body, body size in bytes).
    private func planFeeAndSize(for payload: KeysignPayload) throws -> (fee: UInt64, size: Int) {
        let inputData = try CardanoHelper.getCardanoPreSignInputData(keysignPayload: payload)
        let input = try CardanoSigningInput(serializedBytes: inputData)
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(preSigningOutput.errorMessage.isEmpty, preSigningOutput.errorMessage)
        return (input.transferMessage.forceFee, preSigningOutput.data.count)
    }

    // MARK: - byteFee is forced verbatim into the body (sighash parity)

    /// The fee baked into the signed body must equal the `byteFee` carried in the
    /// payload — every device forces the same shared value. This is what
    /// guarantees byte-identical bodies across iOS/SDK/Windows/Android.
    func testBodyFeeEqualsTransmittedByteFee() throws {
        let coin = try makeCoin()
        let utxos = [UtxoInfo(hash: utxoHash, amount: 10_000_000, index: 0)]

        for forced: BigInt in [165_000, 180_000, 240_000, 500_000] {
            let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: utxos, byteFee: forced)
            let (fee, _) = try planFeeAndSize(for: payload)
            XCTAssertEqual(BigInt(fee), forced, "body fee must equal the transmitted byteFee (\(forced))")
        }
    }

    /// A dynamic fee transmitted by an initiator (e.g. iOS computing a size-based
    /// value) is honored verbatim by the signing path — proving cross-platform
    /// co-signers will reproduce whatever `byteFee` the initiator chose.
    func testDynamicByteFeeIsHonored() throws {
        let coin = try makeCoin()
        let utxos: [UtxoInfo] = (0..<20).map { i in
            UtxoInfo(hash: String(format: "%064x", i), amount: 3_000_000, index: UInt32(i))
        }
        // Compute the dynamic fee the initiator would seed, then sign with it.
        let feePayload = makePayload(coin: coin, toAmount: 40_000_000, utxos: utxos, byteFee: 0)
        let dynamicFee = CardanoHelper.estimateDynamicByteFee(keysignPayload: feePayload)

        let signed = makePayload(coin: coin, toAmount: 40_000_000, utxos: utxos, byteFee: dynamicFee)
        let (fee, _) = try planFeeAndSize(for: signed)
        XCTAssertEqual(BigInt(fee), dynamicFee, "body fee must equal the initiator's dynamic byteFee")
    }

    // MARK: - Initiator-side dynamic fee computation

    /// A tiny 1-in/1-out ADA send computes a fee below the old flat 180k —
    /// proving the initiator's fee is size-derived, not a flat constant.
    func testInitiatorSmallTransferFeeBelowFlatFloor() throws {
        let coin = try makeCoin()
        let utxos = [UtxoInfo(hash: utxoHash, amount: 10_000_000, index: 0)]
        let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: utxos, byteFee: 0)

        let fee = CardanoHelper.estimateDynamicByteFee(keysignPayload: payload)

        XCTAssertLessThan(fee, 180_000, "small tx should cost less than the old flat 180k floor")
        // Sanity: still covers the mainnet fixed minimum (minFeeB = 155,381).
        XCTAssertGreaterThan(fee, 155_381, "fee must cover minFeeB")
    }

    /// A large multi-input consolidation produces a body well over the ~560B
    /// break-even, so the initiator's size-derived fee must EXCEED the old flat
    /// 180k that previously caused `FeeTooSmallUTxO` rejections.
    func testInitiatorLargeMultiInputFeeExceedsFlatFloor() throws {
        let coin = try makeCoin()
        let utxos: [UtxoInfo] = (0..<40).map { i in
            UtxoInfo(hash: String(format: "%064x", i), amount: 3_000_000, index: UInt32(i))
        }
        let payload = makePayload(coin: coin, toAmount: 80_000_000, utxos: utxos, byteFee: 0)

        let fee = CardanoHelper.estimateDynamicByteFee(keysignPayload: payload)

        XCTAssertGreaterThan(fee, 180_000, "large tx must pay more than the old flat 180k — this is the bug fix")
    }

    /// The initiator's fee must scale monotonically with tx size: the large tx
    /// pays strictly more than the small one.
    func testInitiatorFeeScalesWithSize() throws {
        let coin = try makeCoin()

        let small = makePayload(
            coin: coin,
            toAmount: 2_000_000,
            utxos: [UtxoInfo(hash: utxoHash, amount: 10_000_000, index: 0)],
            byteFee: 0
        )
        let large = makePayload(
            coin: coin,
            toAmount: 60_000_000,
            utxos: (0..<25).map { i in
                UtxoInfo(hash: String(format: "%064x", i), amount: 3_000_000, index: UInt32(i))
            },
            byteFee: 0
        )

        let smallFee = CardanoHelper.estimateDynamicByteFee(keysignPayload: small)
        let largeFee = CardanoHelper.estimateDynamicByteFee(keysignPayload: large)

        XCTAssertGreaterThan(largeFee, smallFee, "fee should grow with tx size")
    }

    /// The factory's transient fee-estimation payload must carry the memo, and
    /// the resulting fee must exceed the memo-less fee for the same transfer.
    /// A CIP-20 memo grows the signed tx (the 35-byte aux-hash entry in the
    /// body plus the aux CBOR in the envelope); a fee planned without it is
    /// below the network minimum for the tx that actually gets signed, so the
    /// node rejects the broadcast with `FeeTooSmallUTxO` — while the same send
    /// from the SDK/extension (which prices the aux bytes) goes through.
    func testFeeEstimationPayloadCarriesMemo() throws {
        let coin = try makeCoin()
        let utxos = [UtxoInfo(hash: utxoHash, amount: 10_000_000, index: 0)]
        let vault = Vault(name: "CardanoFeeTest")
        let factory = KeysignPayloadFactory()
        let memo = "hello world"

        let withMemo = factory.makeCardanoFeePayload(
            coin: coin,
            toAddress: cardanoAddress,
            amount: 2_000_000,
            memo: memo,
            ttl: 190_000_000,
            sendMaxAmount: false,
            utxos: utxos,
            vault: vault
        )
        let withoutMemo = factory.makeCardanoFeePayload(
            coin: coin,
            toAddress: cardanoAddress,
            amount: 2_000_000,
            memo: nil,
            ttl: 190_000_000,
            sendMaxAmount: false,
            utxos: utxos,
            vault: vault
        )

        XCTAssertEqual(withMemo.memo, memo, "fee-estimation payload must carry the memo")

        let memoFee = CardanoHelper.estimateDynamicByteFee(keysignPayload: withMemo)
        let plainFee = CardanoHelper.estimateDynamicByteFee(keysignPayload: withoutMemo)
        let auxLen = CardanoCIP20.buildAuxData(memo: memo).auxDataCbor.count
        XCTAssertGreaterThanOrEqual(
            memoFee, plainFee + 44 * BigInt(auxLen),
            "the initiator's byteFee must price the CIP-20 aux bytes (minFeeA = 44/byte)"
        )
    }
}
