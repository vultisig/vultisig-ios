//
//  SolanaDeactivateWithdrawResolverTests.swift
//  VultisigAppTests
//
//  Pins the deactivate (unstake) and withdraw resolver branches: each emits a
//  `SignSolana` carrying exactly one relayed raw transaction whose pre-image
//  matches the input-rebuild path (byte parity), and rejects a payload whose
//  op-type doesn't match the branch.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SolanaDeactivateWithdrawResolverTests: XCTestCase {

    private let recentBlockHash = "11111111111111111111111111111111"

    private func makeSignerKey() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: Data(hexString: "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63")!))
    }

    private func stakeAccountAddress() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x42, count: 32)))
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
            toAddress: stakingPayload.stakeAccount ?? "",
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

    // MARK: - Deactivate

    func testDeactivateEmitsSingleRelayedTransactionWithMatchingPreImage() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))

        let signSolana = try SolanaStakingSignDataResolver.resolveDeactivate(basePayload: payload)

        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        let relayedHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            base64Transaction: try XCTUnwrap(signSolana.rawTransactions.first)
        )
        let rebuildHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(relayedHashes, rebuildHashes)
    }

    func testDeactivateRejectsWithdrawPayload() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )

        XCTAssertThrowsError(try SolanaStakingSignDataResolver.resolveDeactivate(basePayload: payload))
    }

    // MARK: - Withdraw

    func testWithdrawEmitsSingleRelayedTransactionWithMatchingPreImage() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 2_000_000_000)
        )

        let signSolana = try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: payload)

        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        let relayedHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            base64Transaction: try XCTUnwrap(signSolana.rawTransactions.first)
        )
        let rebuildHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(relayedHashes, rebuildHashes)
    }

    func testWithdrawRejectsDeactivatePayload() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(privateKey: privateKey, stakingPayload: .unstake(stakeAccount: stakeAccount))

        XCTAssertThrowsError(try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: payload))
    }

    func testWithdrawRejectsZeroAmount() throws {
        let privateKey = try makeSignerKey()
        let stakeAccount = try stakeAccountAddress()
        let payload = makePayload(
            privateKey: privateKey,
            stakingPayload: .withdraw(stakeAccount: stakeAccount, lamports: 0)
        )

        XCTAssertThrowsError(try SolanaStakingSignDataResolver.resolveWithdraw(basePayload: payload))
    }
}
