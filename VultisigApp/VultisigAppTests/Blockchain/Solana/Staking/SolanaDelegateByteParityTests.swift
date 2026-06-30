//
//  SolanaDelegateByteParityTests.swift
//  VultisigAppTests
//
//  MPC byte-parity contract for the Solana delegate (stake) flow. Two
//  independent builds of the same delegate input — built from a pinned recent
//  blockhash and the wallet-core-derived stake-account address — must produce
//  identical pre-image bytes, so both co-signing devices compute the same hash
//  and the TSS ceremony proceeds. Also pins the delegate signing input wiring
//  (oneof = delegateStakeTransaction, stake_account omitted).
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SolanaDelegateByteParityTests: XCTestCase {

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

    /// A structurally valid validator vote pubkey: a base58 ed25519 address
    /// derived from a deterministic key. Distinct from the signer.
    private func makeValidatorVotePubkey() throws -> String {
        let keyData = Data(repeating: 0x37, count: 32)
        let key = try XCTUnwrap(PrivateKey(data: keyData))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    private func makeDelegatePayload(privateKey: PrivateKey, votePubkey: String) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: privateKey),
            toAddress: votePubkey,
            toAmount: 2_000_000_000,
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
            solanaStakingPayload: .delegate(votePubkey: votePubkey, lamports: 2_000_000_000),
            skipBroadcast: false,
            signData: nil
        )
    }

    // MARK: - Byte parity

    /// The core MPC guarantee: two independent builds of the same delegate input
    /// produce identical pre-image bytes (the message both peers hash and sign).
    func testTwoIndependentBuildsProduceIdenticalPreImageBytes() throws {
        let privateKey = try makeSignerKey()
        let votePubkey = try makeValidatorVotePubkey()

        let payloadA = makeDelegatePayload(privateKey: privateKey, votePubkey: votePubkey)
        let payloadB = makeDelegatePayload(privateKey: privateKey, votePubkey: votePubkey)

        let hashesA = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadA)
        let hashesB = try SolanaHelper.getPreSignedImageHash(keysignPayload: payloadB)

        XCTAssertFalse(hashesA.isEmpty)
        XCTAssertEqual(hashesA, hashesB)
    }

    /// The relayed-bytes contract: the unsigned transaction the resolver builds
    /// (relayed via SignSolana) yields the SAME pre-image as the input-rebuild
    /// path. This is what makes a peer device — which has no
    /// `solanaStakingPayload`, only the relayed raw bytes — compute the same
    /// hash as the initiator.
    func testRelayedUnsignedTransactionMatchesInputRebuildPreImage() throws {
        let privateKey = try makeSignerKey()
        let votePubkey = try makeValidatorVotePubkey()
        let payload = makeDelegatePayload(privateKey: privateKey, votePubkey: votePubkey)

        // Initiator path: rebuild the input from the staking payload.
        let initiatorHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)

        // Peer path: only the relayed raw bytes, no staking payload.
        let rawTx = try SolanaHelper.buildDelegateUnsignedTransaction(keysignPayload: payload)
        let peerHashes = try SolanaHelper.getPreSignedImageHashForRaw(base64Transaction: rawTx)

        XCTAssertEqual(initiatorHashes, peerHashes)
    }

    // MARK: - Signing-input wiring

    /// Pins the delegate oneof and the omitted stake_account — wallet-core
    /// derives the stake-account address, so we must NOT set it.
    func testDelegateSigningInputSetsOneofAndOmitsStakeAccount() throws {
        let privateKey = try makeSignerKey()
        let votePubkey = try makeValidatorVotePubkey()
        let payload = makeDelegatePayload(privateKey: privateKey, votePubkey: votePubkey)

        let inputData = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SolanaSigningInput(serializedBytes: inputData)

        guard case .delegateStakeTransaction(let delegate)? = input.transactionType else {
            return XCTFail("expected delegateStakeTransaction oneof")
        }
        XCTAssertEqual(delegate.validatorPubkey, votePubkey)
        XCTAssertEqual(delegate.value, 2_000_000_000)
        XCTAssertTrue(delegate.stakeAccount.isEmpty, "stake_account must be omitted — wallet-core derives it")
        XCTAssertEqual(input.recentBlockhash, recentBlockHash)
        XCTAssertEqual(input.sender, payload.coin.address)
    }

    /// A different validator or amount must change the pre-image — guards
    /// against a build that ignores the staking payload.
    func testDistinctInputsProduceDistinctPreImages() throws {
        let privateKey = try makeSignerKey()
        let votePubkey = try makeValidatorVotePubkey()

        let payload = makeDelegatePayload(privateKey: privateKey, votePubkey: votePubkey)
        let baseHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)

        let otherPayload = payload.withSolanaStakingPayload(
            .delegate(votePubkey: votePubkey, lamports: 3_000_000_000)
        )
        let otherHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: otherPayload)

        XCTAssertNotEqual(baseHashes, otherHashes)
    }
}
