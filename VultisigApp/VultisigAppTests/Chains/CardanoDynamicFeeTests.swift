//
//  CardanoDynamicFeeTests.swift
//  VultisigApp
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

/// Verifies the Cardano fee baked into the signed body is derived from the
/// planned tx size (WalletCore `minFeeA*size + minFeeB`) rather than a flat
/// forced value. A flat 180k-lovelace fee underpays any body above ~560 bytes
/// (CNT / multi-input / metadata txs) and the network rejects it at broadcast
/// with `FeeTooSmallUTxO`.
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

    private func makePayload(coin: Coin, toAmount: BigInt, utxos: [UtxoInfo]) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: cardanoAddress,
            toAmount: toAmount,
            // byteFee seed is retained only as a display estimate; it must NOT
            // be what ends up in the signed body anymore.
            chainSpecific: .Cardano(byteFee: 180_000, sendMaxAmount: false, ttl: 190_000_000),
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
        // Re-decode the serialized signing input: `getCardanoPreSignInputData`
        // pins the planner's computed fee into `transferMessage.forceFee`.
        let input = try CardanoSigningInput(serializedBytes: inputData)
        let hashes = TransactionCompiler.preImageHashes(coinType: .cardano, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(preSigningOutput.errorMessage.isEmpty, preSigningOutput.errorMessage)
        return (input.transferMessage.forceFee, preSigningOutput.data.count)
    }

    /// A tiny 1-in/1-out ADA send must cost less than the old flat 180k —
    /// proving the fee is size-derived, not a coincidental match of the seed.
    func testSmallTransferFeeIsBelowFlatSeed() throws {
        let coin = try makeCoin()
        let utxos = [UtxoInfo(hash: utxoHash, amount: 10_000_000, index: 0)]
        let payload = makePayload(coin: coin, toAmount: 2_000_000, utxos: utxos)

        let (fee, size) = try planFeeAndSize(for: payload)

        XCTAssertLessThan(fee, 180_000, "small tx should cost less than the old flat 180k seed")
        // Sanity: still covers the mainnet fixed minimum (minFeeB = 155,381).
        XCTAssertGreaterThan(fee, 155_381, "fee must cover minFeeB")
        XCTAssertLessThan(size, 560, "small tx body should be under the ~560B break-even")
    }

    /// A large multi-input consolidation produces a body well over the ~560B
    /// break-even, so its size-derived fee must EXCEED the old flat 180k that
    /// previously caused `FeeTooSmallUTxO` rejections.
    func testLargeMultiInputFeeExceedsFlatSeed() throws {
        let coin = try makeCoin()
        let utxos: [UtxoInfo] = (0..<40).map { i in
            // Distinct 32-byte hashes so the planner treats them as separate inputs.
            let hash = String(format: "%064x", i)
            return UtxoInfo(hash: hash, amount: 3_000_000, index: UInt32(i))
        }
        let payload = makePayload(coin: coin, toAmount: 80_000_000, utxos: utxos)

        let (fee, size) = try planFeeAndSize(for: payload)

        XCTAssertGreaterThan(size, 560, "multi-input body should exceed the break-even size")
        XCTAssertGreaterThan(fee, 180_000, "large tx must pay more than the old flat 180k — this is the bug fix")
    }

    /// Fee must scale monotonically with tx size: the large tx pays strictly
    /// more than the small one.
    func testFeeScalesWithSize() throws {
        let coin = try makeCoin()

        let small = makePayload(
            coin: coin,
            toAmount: 2_000_000,
            utxos: [UtxoInfo(hash: utxoHash, amount: 10_000_000, index: 0)]
        )
        let large = makePayload(
            coin: coin,
            toAmount: 60_000_000,
            utxos: (0..<25).map { i in
                UtxoInfo(hash: String(format: "%064x", i), amount: 3_000_000, index: UInt32(i))
            }
        )

        let smallResult = try planFeeAndSize(for: small)
        let largeResult = try planFeeAndSize(for: large)

        XCTAssertGreaterThan(largeResult.size, smallResult.size)
        XCTAssertGreaterThan(largeResult.fee, smallResult.fee, "fee should grow with tx size")
    }
}
