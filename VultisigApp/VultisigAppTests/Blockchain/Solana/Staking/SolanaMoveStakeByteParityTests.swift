//
//  SolanaMoveStakeByteParityTests.swift
//  VultisigAppTests
//
//  MPC byte-parity contract for the guided Solana move-stake (redelegate A → B)
//  sub-steps. Each sub-step is signed independently, so each must satisfy the
//  same parity guarantee as delegate/deactivate/withdraw: two independent builds
//  of the same input — from a pinned recent blockhash and the moved-account
//  address — produce identical pre-image bytes. Also pins the signing-input
//  wiring per sub-step (deactivate oneof on the moved account; delegate oneof
//  with the moved account set EXPLICITLY for the re-delegate).
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SolanaMoveStakeByteParityTests: XCTestCase {

    private let signerPrivateKeyHex = "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63"
    private let recentBlockHash = "11111111111111111111111111111111"

    private func makeSignerKey() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: Data(hexString: signerPrivateKeyHex)!))
    }

    private func makeCoin(privateKey: PrivateKey) -> Coin {
        let publicKey = privateKey.getPublicKeyEd25519()
        let meta = CoinMeta(
            chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
            priceProviderId: "solana", contractAddress: "", isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: AnyAddress(publicKey: publicKey, coin: .solana).description,
            hexPublicKey: publicKey.data.hexString
        )
    }

    private func movedStakeAccount() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x42, count: 32)))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    private func validatorVotePubkey() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x37, count: 32)))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    private func makePayload(
        privateKey: PrivateKey,
        stakingPayload: SolanaStakingPayload
    ) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: privateKey),
            toAddress: stakingPayload.votePubkey ?? stakingPayload.stakeAccount ?? "",
            toAmount: BigInt(stakingPayload.lamports ?? 0),
            chainSpecific: .Solana(
                recentBlockHash: recentBlockHash, priorityFee: 1_000_000, priorityLimit: 100_000,
                fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false
            ),
            utxos: [], memo: nil, swapPayload: nil, approvePayload: nil,
            vaultPubKeyECDSA: "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b",
            vaultLocalPartyID: "localPartyID", libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil, tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil, tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil, isQbtcClaim: false,
            solanaStakingPayload: stakingPayload,
            skipBroadcast: false, signData: nil
        )
    }

    // MARK: - Deactivate sub-step

    func testMoveDeactivateTwoIndependentBuildsProduceIdenticalPreImageBytes() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payloadA = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeDeactivate(movedStakeAccount: account, votePubkey: vote)
        )
        let payloadB = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeDeactivate(movedStakeAccount: account, votePubkey: vote)
        )

        let hashesA = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadA)
        let hashesB = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadB)

        XCTAssertFalse(hashesA.isEmpty)
        XCTAssertEqual(hashesA, hashesB)
    }

    func testMoveDeactivateRelayedUnsignedTransactionMatchesInputRebuildPreImage() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeDeactivate(movedStakeAccount: account, votePubkey: vote)
        )

        let initiatorHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        let rawTx = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: payload)
        let peerHashes = try SolanaHelper.getPreSignedImageHashForRaw(base64Transaction: rawTx)

        XCTAssertEqual(initiatorHashes, peerHashes)
    }

    func testMoveDeactivateSigningInputSetsDeactivateOneofOnMovedAccount() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeDeactivate(movedStakeAccount: account, votePubkey: vote)
        )

        let inputData = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SolanaSigningInput(serializedBytes: inputData)

        guard case .deactivateStakeTransaction(let deactivate)? = input.transactionType else {
            return XCTFail("expected deactivateStakeTransaction oneof")
        }
        XCTAssertEqual(deactivate.stakeAccount, account)
        XCTAssertEqual(input.recentBlockhash, recentBlockHash)
        XCTAssertEqual(input.sender, payload.coin.address)
    }

    // MARK: - Re-delegate sub-step

    func testMoveRedelegateTwoIndependentBuildsProduceIdenticalPreImageBytes() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payloadA = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 2_000_000_000)
        )
        let payloadB = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 2_000_000_000)
        )

        let hashesA = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadA)
        let hashesB = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadB)

        XCTAssertFalse(hashesA.isEmpty)
        XCTAssertEqual(hashesA, hashesB)
    }

    func testMoveRedelegateRelayedUnsignedTransactionMatchesInputRebuildPreImage() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 2_000_000_000)
        )

        let initiatorHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        let rawTx = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: payload)
        let peerHashes = try SolanaHelper.getPreSignedImageHashForRaw(base64Transaction: rawTx)

        XCTAssertEqual(initiatorHashes, peerHashes)
    }

    /// Pins the re-delegate oneof: unlike a fresh delegate, the moved account is
    /// set EXPLICITLY so wallet-core re-delegates the existing account rather
    /// than deriving a new one.
    func testMoveRedelegateSigningInputSetsDelegateOneofWithExplicitStakeAccount() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 2_000_000_000)
        )

        let inputData = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SolanaSigningInput(serializedBytes: inputData)

        guard case .delegateStakeTransaction(let delegate)? = input.transactionType else {
            return XCTFail("expected delegateStakeTransaction oneof")
        }
        XCTAssertEqual(delegate.validatorPubkey, vote)
        XCTAssertEqual(delegate.value, 2_000_000_000)
        XCTAssertEqual(delegate.stakeAccount, account, "move re-delegate must target the existing moved account")
        XCTAssertEqual(input.recentBlockhash, recentBlockHash)
        XCTAssertEqual(input.sender, payload.coin.address)
    }

    /// A different destination validator or amount must change the re-delegate
    /// pre-image — guards against a build that ignores the staking payload.
    func testMoveRedelegateDistinctInputsProduceDistinctPreImages() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 2_000_000_000)
        )
        let baseHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)

        let otherPayload = payload.withSolanaStakingPayload(
            .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 3_000_000_000)
        )
        let otherHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: otherPayload)

        XCTAssertNotEqual(baseHashes, otherHashes)
    }

    // MARK: - Split sub-step

    /// A partial move's split needs a Stake-program Split instruction wallet-core
    /// does not expose — the build must reject it rather than emit a wrong tx.
    func testMoveSplitBuildRejectsPartialSplit() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeSplit(
                sourceStakeAccount: account,
                splitStakeAccount: account,
                votePubkey: vote,
                lamports: 1_000_000_000
            )
        )

        XCTAssertThrowsError(try SolanaHelper.getPreSignedInputData(keysignPayload: payload))
    }
}
