//
//  SuiSignSuiTests.swift
//  VultisigApp
//
//  Pins the SignSui (dApp Sui PTB) keysign path: the pre-built TransactionData
//  BCS bytes are forwarded verbatim to WalletCore's `signDirectMessage`, hashed
//  under the Sui transaction intent (parity with the native path's compiler),
//  and compiled into a Wallet Standard wire signature (flag(1)||sig(64)||
//  pubKey(32), base64). Mirrors vultisig-sdk PR #705.
//

@testable import VultisigApp
import BigInt
import Tss
import WalletCore
import XCTest

final class SuiSignSuiTests: XCTestCase {

    // Deterministic ed25519 key (32 bytes of 0x01) — matches the SDK #705
    // round-trip vector so the derived signer address lines up.
    private let signerPrivateKey = Data(repeating: 0x01, count: 32)

    // A real BCS-serialized Sui `TransactionData` (base64), the exact vector
    // from vultisig-sdk PR #705 (split + transfer with explicit gas data). The
    // signing path must treat these bytes as opaque.
    private let unsignedTxMsg =
        "AAACAAhkAAAAAAAAAAAgW4yMD3sdSyqcPk9QYXKDlKW2x9jp8KGyw9Tl9gcYKTACAgABAQAAAQEDAAAAAAEBAFuMjA97HUsqnD5PUGFyg5SltsfY6fChssPU5fYHGCkwARERERERERERERERERERERERERERERERERERERERERERAQAAAAAAAAAgBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwdbjIwPex1LKpw+T1BhcoOUpbbH2OnwobLD1OX2BxgpMOgDAAAAAAAAwMYtAAAAAAAA"

    // MARK: - Fixtures

    private func makeSignerKey() throws -> PrivateKey {
        return try XCTUnwrap(PrivateKey(data: signerPrivateKey))
    }

    private func makeCoin(privateKey: PrivateKey) -> Coin {
        let publicKey = privateKey.getPublicKeyEd25519()
        let meta = CoinMeta(
            chain: .sui,
            ticker: "SUI",
            logo: "sui",
            decimals: 9,
            priceProviderId: "sui",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(
            asset: meta,
            address: AnyAddress(publicKey: publicKey, coin: .sui).description,
            hexPublicKey: publicKey.data.hexString
        )
    }

    private func makeSignSuiPayload(privateKey: PrivateKey) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(privateKey: privateKey),
            toAddress: "",
            toAmount: 0,
            // A signSui payload carries no construction inputs — an empty
            // SuiSpecific stands in for the short-circuited RPC fetch.
            chainSpecific: .Sui(referenceGasPrice: 0, coins: [], gasBudget: 0),
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
            signData: .signSui(SignSui(unsignedTxMsg: unsignedTxMsg))
        )
    }

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

    // MARK: - Signing input

    /// The PTB bytes are forwarded verbatim through `signDirectMessage`; no
    /// Pay / PaySui input is synthesized.
    func testSigningInputForwardsBytesViaSignDirectMessage() throws {
        let key = try makeSignerKey()
        let payload = makeSignSuiPayload(privateKey: key)

        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SuiSigningInput(serializedBytes: inputData)

        guard case .signDirectMessage = input.transactionPayload else {
            return XCTFail("expected signDirectMessage transaction payload")
        }
        XCTAssertEqual(input.signDirectMessage.unsignedTxMsg, unsignedTxMsg)
        XCTAssertEqual(input.signer, payload.coin.address)
    }

    // MARK: - Digest parity

    /// The signSui pre-image hash is the intent-prefixed blake2b digest of the
    /// PTB bytes that WalletCore's Sui compiler produces — the same digest the
    /// native path signs (parity).
    func testPreSignedImageHashMatchesIntentDigest() throws {
        let key = try makeSignerKey()
        let payload = makeSignSuiPayload(privateKey: key)

        let hashes = try SuiHelper.getPreSignedImageHash(keysignPayload: payload)
        XCTAssertEqual(hashes.count, 1)

        // Recompute the intent-prefixed digest directly from the WalletCore
        // compiler to assert the helper didn't alter the bytes being signed.
        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let preImage = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: preImage)
        XCTAssertTrue(preSigningOutput.errorMessage.isEmpty)
        let expected = Hash.blake2b(data: preSigningOutput.data, size: 32).hexString

        XCTAssertEqual(hashes.first, expected)
    }

    // MARK: - Compile / Wallet Standard signature

    /// A full round-trip compiles to a Wallet Standard Ed25519 signature
    /// (flag(1)||sig(64)||pubKey(32), base64) that verifies against the vault
    /// key, and echoes the unsigned PTB bytes unchanged.
    func testSignedTransactionProducesWalletStandardSignature() throws {
        let key = try makeSignerKey()
        let payload = makeSignSuiPayload(privateKey: key)

        let hashes = try SuiHelper.getPreSignedImageHash(keysignPayload: payload)
        let signatures = try makeSignatures(preImageHashes: hashes, privateKey: key)

        let result = try SuiHelper.getSignedTransaction(
            keysignPayload: payload,
            signatures: signatures
        )

        // The unsigned tx echoed back is the same base64 PTB we signed.
        XCTAssertEqual(result.rawTransaction, unsignedTxMsg)

        // Wallet Standard wire signature: flag(1) || sig(64) || pubKey(32).
        let signatureBase64 = try XCTUnwrap(result.signature)
        let serialized = try XCTUnwrap(Data(base64Encoded: signatureBase64))
        XCTAssertEqual(serialized.count, 97)
        XCTAssertEqual(serialized.first, 0x00) // Ed25519 scheme flag

        let publicKey = key.getPublicKeyEd25519()
        let sigBytes = serialized.subdata(in: 1..<65)
        let pubKeyBytes = serialized.subdata(in: 65..<97)
        XCTAssertEqual(pubKeyBytes, publicKey.data)

        // The embedded signature verifies against the intent-prefixed digest.
        let inputData = try SuiHelper.getPreSignedInputData(keysignPayload: payload)
        let preImage = TransactionCompiler.preImageHashes(coinType: .sui, txInputData: inputData)
        let preSigningOutput = try TxCompilerPreSigningOutput(serializedBytes: preImage)
        let digest = Hash.blake2b(data: preSigningOutput.data, size: 32)
        XCTAssertTrue(publicKey.verify(signature: sigBytes, message: digest))
    }

    // MARK: - BCS summary (verify-screen decode)

    /// The verify-screen parser recovers sender / gas / command + input counts
    /// from the PTB BCS bytes for the human-readable summary.
    func testTransactionDataParserExtractsSummary() throws {
        let summary = try XCTUnwrap(
            SuiTransactionDataParser.parse(base64TransactionData: unsignedTxMsg)
        )

        // Vector: 2 inputs (a u64 amount + the recipient address), 2 commands
        // (SplitCoins + TransferObjects), and one gas payment object.
        XCTAssertEqual(summary.inputCount, 2)
        XCTAssertEqual(summary.commandCount, 2)
        XCTAssertEqual(summary.gasPaymentCount, 1)
        XCTAssertFalse(summary.sender.isEmpty)
        XCTAssertTrue(summary.sender.hasPrefix("0x"))
        XCTAssertGreaterThan(summary.gasBudget, 0)
        XCTAssertGreaterThan(summary.gasPrice, 0)
    }
}
