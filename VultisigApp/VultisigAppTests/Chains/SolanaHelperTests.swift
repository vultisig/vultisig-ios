//
//  SolanaHelperTests.swift
//  VultisigApp
//
//  Pins the Solana signed-transaction encoding contract: WalletCore compiles
//  with the proto-default base58 output (txEncoding is never set on the
//  signing input), SignedTransactionResult.rawTransaction is normalized to
//  base64 for broadcast, and the transaction hash is the base58 of the first
//  64-byte signature.
//

@testable import VultisigApp
import BigInt
import Tss
import WalletCore
import XCTest

final class SolanaHelperTests: XCTestCase {

    // Deterministic test-only ed25519 key (from WalletCore's Solana tests).
    private let signerPrivateKeyHex = "8778cc93c6596387e751d2dc693bbd93e434bd233bc5b68a826c56131821cb63"
    // Base58 of 32 zero bytes — a structurally valid recent blockhash.
    private let recentBlockHash = "11111111111111111111111111111111"

    // MARK: - Fixtures

    private func makeSignerKey() throws -> PrivateKey {
        let keyData = try XCTUnwrap(Data(hexString: signerPrivateKeyHex))
        return try XCTUnwrap(PrivateKey(data: keyData))
    }

    private func makeRecipientAddress() throws -> String {
        let keyData = Data(repeating: 0x42, count: 32)
        let recipientKey = try XCTUnwrap(PrivateKey(data: keyData))
        return AnyAddress(publicKey: recipientKey.getPublicKeyEd25519(), coin: .solana).description
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

    private func makeNativeTransferPayload(privateKey: PrivateKey) throws -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: privateKey),
            toAddress: try makeRecipientAddress(),
            toAmount: 1_000_000,
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
            skipBroadcast: false,
            signData: nil
        )
    }

    /// Builds TSS keysign responses the same way the Schnorr keysign state
    /// does: r/s stored little-endian so `TssKeysignResponse.getSignature()`
    /// reverses them back into the 64-byte ed25519 signature.
    private func makeSignatures(
        preImageHashes: [String],
        privateKey: PrivateKey
    ) throws -> [String: TssKeysignResponse] {
        var signatures: [String: TssKeysignResponse] = [:]
        for hash in preImageHashes {
            let message = try XCTUnwrap(Data(hexString: hash))
            let signature = try XCTUnwrap(privateKey.sign(digest: message, curve: .ed25519))
            let response = TssKeysignResponse()
            response.msg = hash
            response.r = Data(signature.prefix(32).reversed()).hexString
            response.s = Data(signature.suffix(32).reversed()).hexString
            signatures[hash] = response
        }
        return signatures
    }

    // MARK: - Encoding contract

    /// Regression pin: WalletCore's `SolanaSigningOutput.encoded` is base58
    /// because the signing input never sets `txEncoding`. If a WalletCore bump
    /// changes that default, this test fails before users hit a broken decode
    /// after the TSS ceremony.
    func testZeroSignedTransactionEncodingIsBase58NotBase64() throws {
        let payload = try makeNativeTransferPayload(privateKey: makeSignerKey())

        let zeroSigned = try SolanaHelper.getZeroSignedTransaction(keysignPayload: payload)

        let base58Decoded = try XCTUnwrap(
            Base58.decodeNoCheck(string: zeroSigned),
            "WalletCore no longer emits base58 — the getSignedTransaction decode path must be revisited"
        )
        // The decoded bytes must parse as a Solana tx envelope (shortvec sig
        // count + 64-byte signature slots + message).
        XCTAssertNoThrow(try SolanaHelper.getHashFromRawTransaction(txData: base58Decoded))
        // Strict base64 must not silently decode the same string into the
        // same bytes — interpreting WalletCore's output as base64 either
        // fails outright or garbles the transaction.
        if let base64Decoded = Data(base64Encoded: zeroSigned) {
            XCTAssertNotEqual(base64Decoded, base58Decoded)
        }
    }

    // MARK: - Full signing path

    func testGetSignedTransactionReturnsBase64RawTransactionAndBase58Hash() throws {
        let privateKey = try makeSignerKey()
        let payload = try makeNativeTransferPayload(privateKey: privateKey)
        let preImageHashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)
        let signatures = try makeSignatures(preImageHashes: preImageHashes, privateKey: privateKey)

        let result = try SolanaHelper.getSignedTransaction(keysignPayload: payload, signatures: signatures)

        let txData = try XCTUnwrap(
            Data(base64Encoded: result.rawTransaction),
            "rawTransaction must be base64 for the sendTransaction RPC call"
        )
        // Single fee-payer signature: [0x01][64-byte sig][message].
        XCTAssertEqual(txData.first, 0x01)
        XCTAssertGreaterThan(txData.count, 65)
        let signatureBytes = txData.subdata(in: 1..<65)
        XCTAssertEqual(result.transactionHash, Base58.encodeNoCheck(data: signatureBytes))
        // The spliced signature must be the one our test key produced.
        let message = txData.subdata(in: 65..<txData.count)
        XCTAssertTrue(privateKey.getPublicKeyEd25519().verify(signature: signatureBytes, message: message))
    }

    // MARK: - Transaction hash extraction

    func testGetHashFromRawTransactionReturnsBase58OfFirstSignature() throws {
        let signature = Data((0..<64).map { UInt8($0) })
        var transaction = Data([0x01])
        transaction.append(signature)
        transaction.append(Data(repeating: 0xAB, count: 32))

        let hash = try SolanaHelper.getHashFromRawTransaction(txData: transaction)

        XCTAssertEqual(hash, Base58.encodeNoCheck(data: signature))
    }

    func testGetHashFromRawTransactionThrowsOnGarbageBytes() {
        // Unterminated shortvec (every byte has the continuation bit set).
        XCTAssertThrowsError(try SolanaHelper.getHashFromRawTransaction(txData: Data([0xFF, 0xFF, 0xFF])))
        // Declares two signatures but is far too short to contain them.
        XCTAssertThrowsError(try SolanaHelper.getHashFromRawTransaction(txData: Data([0x02, 0x00])))
        XCTAssertThrowsError(try SolanaHelper.getHashFromRawTransaction(txData: Data()))
    }

    // MARK: - Raw (dApp) signing path

    func testSignRawTransactionSplicesSignatureAndKeepsBase64Encoding() throws {
        let privateKey = try makeSignerKey()
        let publicKey = privateKey.getPublicKeyEd25519()
        let message = Data(repeating: 0x07, count: 80)
        var unsigned = Data([0x01])
        unsigned.append(Data(repeating: 0x00, count: 64))
        unsigned.append(message)
        let base64Transaction = unsigned.base64EncodedString()

        let preImageHashes = try SolanaHelper.getPreSignedImageHashForRaw(base64Transaction: base64Transaction)
        XCTAssertEqual(preImageHashes, [message.hexString])
        let signatures = try makeSignatures(preImageHashes: preImageHashes, privateKey: privateKey)

        let result = try SolanaHelper.signRawTransaction(
            coinHexPubKey: publicKey.data.hexString,
            base64Transaction: base64Transaction,
            signatures: signatures
        )

        let expectedSignature = try XCTUnwrap(privateKey.sign(digest: message, curve: .ed25519))
        var expectedSigned = Data([0x01])
        expectedSigned.append(expectedSignature)
        expectedSigned.append(message)
        XCTAssertEqual(Data(base64Encoded: result.rawTransaction), expectedSigned)
        XCTAssertEqual(result.transactionHash, Base58.encodeNoCheck(data: expectedSignature))
    }

    // MARK: - signAllTransactions batch guard

    /// Builds a minimal but structurally valid Solana raw-tx envelope —
    /// `[shortvec(1)][64-byte sig slot][32-byte message]`, base64-encoded —
    /// the same shape the dApp raw-signing path (SignSolana.rawTransactions)
    /// consumes.
    private func makeRawSolanaTransactionBase64(messageFill: UInt8) -> String {
        var tx = Data([0x01])
        tx.append(Data(repeating: 0x00, count: 64))
        tx.append(Data(repeating: messageFill, count: 32))
        return tx.base64EncodedString()
    }

    private func makeSignSolanaPayload(rawTransactions: [String]) throws -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: try makeSignerKey()),
            toAddress: try makeRecipientAddress(),
            toAmount: 0,
            chainSpecific: .Solana(
                recentBlockHash: recentBlockHash,
                priorityFee: 0,
                priorityLimit: 0,
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
            skipBroadcast: false,
            signData: .signSolana(SignSolana(proto: .with { $0.rawTransactions = rawTransactions }))
        )
    }

    /// A multi-transaction Solana batch (signAllTransactions, N>1) must be
    /// rejected here — the single pre-ceremony chokepoint reached on BOTH the
    /// initiator and the co-signer before peer discovery. getSignedTransaction
    /// only supports one raw transaction, so without this fail-fast guard the
    /// user would physically approve the entire multi-device keysign ceremony
    /// and only then hit an opaque post-ceremony failure.
    func testGetPreSignedImageHashRejectsMultipleRawTransactions() throws {
        let tx1 = makeRawSolanaTransactionBase64(messageFill: 0x07)
        let tx2 = makeRawSolanaTransactionBase64(messageFill: 0x09)
        let payload = try makeSignSolanaPayload(rawTransactions: [tx1, tx2])

        XCTAssertThrowsError(try SolanaHelper.getPreSignedImageHash(keysignPayload: payload))
    }

    /// Regression: the single raw-transaction path is untouched and still
    /// yields exactly one non-empty pre-image hash.
    func testGetPreSignedImageHashAllowsSingleRawTransaction() throws {
        let tx = makeRawSolanaTransactionBase64(messageFill: 0x07)
        let payload = try makeSignSolanaPayload(rawTransactions: [tx])

        let hashes = try SolanaHelper.getPreSignedImageHash(keysignPayload: payload)

        XCTAssertEqual(hashes.count, 1)
        XCTAssertFalse(try XCTUnwrap(hashes.first).isEmpty)
    }

    // MARK: - RPC request shape

    func testSendTransactionRequestPinsBase64Encoding() throws {
        let encodedTransaction = "dGVzdC10cmFuc2FjdGlvbg=="
        let api = SolanaAPI(
            baseURL: SolanaAPI.rpcBaseURL,
            usesProxyPath: true,
            rpcMethod: .sendTransaction(encodedTransaction: encodedTransaction)
        )

        guard case .requestParameters(let body, _) = api.task else {
            XCTFail("sendTransaction must use .requestParameters")
            return
        }
        XCTAssertEqual(body["method"] as? String, "sendTransaction")
        let params = try XCTUnwrap(body["params"] as? [Any])
        XCTAssertEqual(params.count, 2)
        XCTAssertEqual(params[0] as? String, encodedTransaction)
        // Encoding pinned to base64; preflight commitment pinned to `confirmed`
        // to match the commitment the blockhash is fetched at (avoids spurious
        // BlockhashNotFound on preflight — the default would be `finalized`).
        XCTAssertEqual(params[1] as? [String: String], ["encoding": "base64", "preflightCommitment": "confirmed"])
    }
}
