//
//  SolanaStakingSignDataResolverTests.swift
//  VultisigAppTests
//
//  Pins the delegate resolver: preflight gating, rent-reserve accounting, and
//  that it emits a `SignSolana` carrying exactly one relayed raw transaction
//  whose pre-image matches the input-rebuild path (byte parity).
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SolanaStakingSignDataResolverTests: XCTestCase {

    private let recentBlockHash = "11111111111111111111111111111111"

    private func makeSignerKey() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: Data(hexString: "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63")!))
    }

    private func validatorVotePubkey() throws -> String {
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x37, count: 32)))
        return AnyAddress(publicKey: key.getPublicKeyEd25519(), coin: .solana).description
    }

    private func makeCoin(privateKey: PrivateKey, rawBalance: String) -> Coin {
        let publicKey = privateKey.getPublicKeyEd25519()
        let meta = CoinMeta(
            chain: .solana, ticker: "SOL", logo: "solana", decimals: 9,
            priceProviderId: "solana", contractAddress: "", isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: AnyAddress(publicKey: publicKey, coin: .solana).description,
            hexPublicKey: publicKey.data.hexString
        )
        coin.rawBalance = rawBalance
        return coin
    }

    private func makePayload(
        privateKey: PrivateKey,
        votePubkey: String,
        lamports: UInt64,
        rawBalance: String
    ) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: privateKey, rawBalance: rawBalance),
            toAddress: votePubkey,
            toAmount: BigInt(lamports),
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
            solanaStakingPayload: .delegate(votePubkey: votePubkey, lamports: lamports),
            skipBroadcast: false, signData: nil
        )
    }

    func testResolveEmitsSingleRelayedTransactionWithMatchingPreImage() throws {
        let privateKey = try makeSignerKey()
        let votePubkey = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey, votePubkey: votePubkey,
            lamports: 2_000_000_000, rawBalance: "5000000000"
        )

        let signSolana = try SolanaStakingSignDataResolver.resolve(
            basePayload: payload,
            rentReserve: 2_282_880,
            knownVotePubkeys: [votePubkey],
            balance: 5_000_000_000
        )

        XCTAssertEqual(signSolana.rawTransactions.count, 1)
        let relayedHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            base64Transaction: try XCTUnwrap(signSolana.rawTransactions.first)
        )
        let rebuildHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(relayedHashes, rebuildHashes)
    }

    func testRejectsWhenBalanceCannotCoverAmountPlusRentReserve() throws {
        let privateKey = try makeSignerKey()
        let votePubkey = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey, votePubkey: votePubkey,
            lamports: 2_000_000_000, rawBalance: "2000000000"
        )

        XCTAssertThrowsError(
            try SolanaStakingSignDataResolver.resolve(
                basePayload: payload,
                rentReserve: 2_282_880,
                knownVotePubkeys: [votePubkey],
                balance: 2_000_000_000 // exactly the amount, no room for rent reserve
            )
        )
    }

    func testRejectsUnknownValidator() throws {
        let privateKey = try makeSignerKey()
        let votePubkey = try validatorVotePubkey()
        let payload = makePayload(
            privateKey: privateKey, votePubkey: votePubkey,
            lamports: 2_000_000_000, rawBalance: "5000000000"
        )

        XCTAssertThrowsError(
            try SolanaStakingSignDataResolver.resolve(
                basePayload: payload,
                rentReserve: 2_282_880,
                knownVotePubkeys: ["SomeOtherValidator1111111111111111111111111"],
                balance: 5_000_000_000
            )
        )
    }
}
