//
//  SolanaMoveStakeResolverTests.swift
//  VultisigAppTests
//
//  Pins the move-stake resolver branches: the deactivate and re-delegate
//  sub-steps each emit a `SignSolana` with exactly one relayed raw transaction
//  whose pre-image matches the input-rebuild path (byte parity); the partial
//  split is rejected; and a non-move op-type / missing sub-step throws.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SolanaMoveStakeResolverTests: XCTestCase {

    private let recentBlockHash = "11111111111111111111111111111111"

    private func makeSignerKey() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: Data(hexString: "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63")!))
    }

    private func movedStakeAccount() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x42, count: 32)))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    private func validatorVotePubkey() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x37, count: 32)))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
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

    func testMoveDeactivateEmitsSingleRelayedTransactionWithMatchingPreImage() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeDeactivate(movedStakeAccount: account, votePubkey: vote)
        )

        let signSolana = try SolanaStakingSignDataResolver.resolveMoveStake(basePayload: payload, knownVotePubkeys: [])

        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        let relayedHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            base64Transaction: try XCTUnwrap(signSolana.rawTransactions.first)
        )
        let rebuildHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(relayedHashes, rebuildHashes)
    }

    // MARK: - Re-delegate sub-step

    func testMoveRedelegateEmitsSingleRelayedTransactionWithMatchingPreImage() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 2_000_000_000)
        )

        let signSolana = try SolanaStakingSignDataResolver.resolveMoveStake(
            basePayload: payload,
            knownVotePubkeys: [vote]
        )

        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        let relayedHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            base64Transaction: try XCTUnwrap(signSolana.rawTransactions.first)
        )
        let rebuildHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(relayedHashes, rebuildHashes)
    }

    func testMoveRedelegateRejectsUnknownValidatorWhenSetNonEmpty() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeRedelegate(movedStakeAccount: account, votePubkey: vote, lamports: 2_000_000_000)
        )

        XCTAssertThrowsError(
            try SolanaStakingSignDataResolver.resolveMoveStake(
                basePayload: payload,
                knownVotePubkeys: ["SomeOtherValidatorVotePubkey"]
            )
        )
    }

    // MARK: - Split + guards

    func testMovePartialSplitIsRejected() throws {
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

        XCTAssertThrowsError(
            try SolanaStakingSignDataResolver.resolveMoveStake(basePayload: payload, knownVotePubkeys: [])
        )
    }

    func testMoveStakeRejectsNonMoveOpType() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let payload = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: account))

        XCTAssertThrowsError(
            try SolanaStakingSignDataResolver.resolveMoveStake(basePayload: payload, knownVotePubkeys: [])
        )
    }

    func testMoveStakeRejectsMissingSubStep() throws {
        let privateKey = try makeSignerKey()
        let account = try movedStakeAccount()
        let vote = try validatorVotePubkey()
        // The legacy whole-payload factory leaves the sub-step nil.
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .moveStakeStep(
                stakeAccount: account, destinationStakeAccount: account, votePubkey: vote, lamports: 1
            )
        )

        XCTAssertThrowsError(
            try SolanaStakingSignDataResolver.resolveMoveStake(basePayload: payload, knownVotePubkeys: [])
        )
    }
}
