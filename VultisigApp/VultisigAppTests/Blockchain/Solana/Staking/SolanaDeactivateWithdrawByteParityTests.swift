//
//  SolanaDeactivateWithdrawByteParityTests.swift
//  VultisigAppTests
//
//  MPC byte-parity contract for the Solana deactivate (unstake) and withdraw
//  flows. Two independent builds of the same input — built from a pinned recent
//  blockhash and the stake-account address — must produce identical pre-image
//  bytes, so both co-signing devices compute the same hash and the TSS ceremony
//  proceeds. Also pins the signing-input wiring (oneof + stake_account/value).
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SolanaDeactivateWithdrawByteParityTests: XCTestCase {

    private let signerPrivateKeyHex = "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63"
    private let recentBlockHash = "11111111111111111111111111111111"

    // MARK: - Fixtures

    private func makeSignerKey() throws -> PrivateKey {
        let keyData = try XCTUnwrap(Data(hexString: signerPrivateKeyHex))
        return try XCTUnwrap(PrivateKey(data: keyData))
    }

    private func makeCoin(privateKey: PrivateKey) -> Coin {
        let publicKey = privateKey.getPublicKeyEd25519()
        let meta = CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "solana",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: AnyAddress(publicKey: publicKey, coin: .solana).description,
            hexPublicKey: publicKey.data.hexString
        )
    }

    /// A structurally valid stake-account address: a base58 ed25519 address from
    /// a deterministic key, distinct from the signer.
    private func makeStakeAccount() throws -> String {
        let keyData = Data(repeating: 0x42, count: 32)
        let key = try XCTUnwrap(PrivateKey(data: keyData))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    private func makePayload(
        privateKey: PrivateKey,
        stakingPayload: SolanaStakingPayload
    ) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: privateKey),
            toAddress: stakingPayload.stakeAccount ?? "",
            toAmount: BigInt(stakingPayload.lamports ?? 0),
            chainSpecific: .Solana(
                recentBlockHash: recentBlockHash,
                priorityFee: 1_000_000,
                priorityLimit: 100_000,
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b",
            vaultLocalPartyID: "localPartyID",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            solanaStakingPayload: stakingPayload,
            skipBroadcast: false,
            signData: nil
        )
    }

    // MARK: - Deactivate byte parity

    func testDeactivateTwoIndependentBuildsProduceIdenticalPreImageBytes() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try makeStakeAccount()
        let payloadA = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))
        let payloadB = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))

        let hashesA = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadA)
        let hashesB = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadB)

        XCTAssertFalse(hashesA.isEmpty)
        XCTAssertEqual(hashesA, hashesB)
    }

    func testDeactivateRelayedUnsignedTransactionMatchesInputRebuildPreImage() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try makeStakeAccount()
        let payload = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))

        let initiatorHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        let rawTx = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: payload)
        let peerHashes = try SolanaHelper.getPreSignedImageHashForRaw(base64Transaction: rawTx)

        XCTAssertEqual(initiatorHashes, peerHashes)
    }

    func testDeactivateSigningInputSetsOneofAndStakeAccount() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try makeStakeAccount()
        let payload = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))

        let inputData = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SolanaSigningInput(serializedBytes: inputData)

        guard case .deactivateStakeTransaction(let deactivate)? = input.transactionType else {
            return XCTFail("expected deactivateStakeTransaction oneof")
        }
        XCTAssertEqual(deactivate.stakeAccount, stakeAccount)
        XCTAssertEqual(input.recentBlockhash, recentBlockHash)
        XCTAssertEqual(input.sender, payload.coin.address)
    }

    // MARK: - Withdraw byte parity

    func testWithdrawTwoIndependentBuildsProduceIdenticalPreImageBytes() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try makeStakeAccount()
        let payloadA = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )
        let payloadB = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )

        let hashesA = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadA)
        let hashesB = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadB)

        XCTAssertFalse(hashesA.isEmpty)
        XCTAssertEqual(hashesA, hashesB)
    }

    func testWithdrawRelayedUnsignedTransactionMatchesInputRebuildPreImage() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try makeStakeAccount()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )

        let initiatorHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        let rawTx = try SolanaHelper.buildStakingUnsignedTransaction(keysignPayload: payload)
        let peerHashes = try SolanaHelper.getPreSignedImageHashForRaw(base64Transaction: rawTx)

        XCTAssertEqual(initiatorHashes, peerHashes)
    }

    func testWithdrawSigningInputSetsOneofStakeAccountAndValue() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try makeStakeAccount()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )

        let inputData = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SolanaSigningInput(serializedBytes: inputData)

        guard case .withdrawTransaction(let withdraw)? = input.transactionType else {
            return XCTFail("expected withdrawTransaction oneof")
        }
        XCTAssertEqual(withdraw.stakeAccount, stakeAccount)
        XCTAssertEqual(withdraw.value, 2_000_000_000)
        XCTAssertEqual(input.recentBlockhash, recentBlockHash)
        XCTAssertEqual(input.sender, payload.coin.address)
    }

    /// A different stake account or amount must change the withdraw pre-image —
    /// guards against a build that ignores the staking payload.
    func testWithdrawDistinctInputsProduceDistinctPreImages() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try makeStakeAccount()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )
        let baseHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)

        let otherPayload = payload.withSolanaStakingPayload(
            .withdraw(stakeAccount: stakeAccount, lamports: 3_000_000_000)
        )
        let otherHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: otherPayload)

        XCTAssertNotEqual(baseHashes, otherHashes)
    }
}
