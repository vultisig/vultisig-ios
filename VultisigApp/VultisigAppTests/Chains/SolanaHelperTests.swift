//
//  SolanaHelperTests.swift
//  VultisigApp
//
//  Pins the Solana signed-transaction encoding contract: WalletCore compiles
//  with the proto-default base58 output (txEncoding is never set on the
//  signing input), SignedTransactionResult.rawTransaction is normalized to
//  base64 for broadcast, and the transaction hash is the base58 of the fee
//  payer's signature (slot 0), empty while that slot is unsigned.
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

    /// An all-zero slot 0 is the fee payer's placeholder, not a transaction id,
    /// even when a later signer has already signed.
    func testGetHashFromRawTransactionIsEmptyWhileTheFeePayerSlotIsUnsigned() throws {
        let laterSignerSignature = Data((0..<64).map { UInt8($0) })
        var soleSlot = Data([0x01])
        soleSlot.append(Data(repeating: 0x00, count: 64))
        soleSlot.append(Data(repeating: 0xAB, count: 32))
        var laterSlotSigned = Data([0x02])
        laterSlotSigned.append(Data(repeating: 0x00, count: 64))
        laterSlotSigned.append(laterSignerSignature)
        laterSlotSigned.append(Data(repeating: 0xAB, count: 32))

        XCTAssertEqual(try SolanaHelper.getHashFromRawTransaction(txData: soleSlot), "")
        XCTAssertEqual(try SolanaHelper.getHashFromRawTransaction(txData: laterSlotSigned), "")
    }

    func testGetHashFromRawTransactionThrowsOnGarbageBytes() {
        // Unterminated shortvec (every byte has the continuation bit set).
        XCTAssertThrowsError(try SolanaHelper.getHashFromRawTransaction(txData: Data([0xFF, 0xFF, 0xFF])))
        // Declares two signatures but is far too short to contain them.
        XCTAssertThrowsError(try SolanaHelper.getHashFromRawTransaction(txData: Data([0x02, 0x00])))
        XCTAssertThrowsError(try SolanaHelper.getHashFromRawTransaction(txData: Data()))
    }

    // MARK: - Raw message fixtures

    /// The System Program id is 32 zero bytes.
    private let systemProgramKey = Data(repeating: 0x00, count: 32)
    private let transferRecipientKey = Data(repeating: 0x09, count: 32)

    /// A System Program `Transfer`: instruction tag 2 (u32 LE) then lamports (u64 LE).
    private func makeTransferInstruction(programIndex: UInt8, from: UInt8, to: UInt8, lamports: UInt64) -> Data {
        var data = Data([0x02, 0x00, 0x00, 0x00])
        withUnsafeBytes(of: lamports.littleEndian) { data.append(contentsOf: $0) }
        var instruction = Data([programIndex, 0x02, from, to, UInt8(data.count)])
        instruction.append(data)
        return instruction
    }

    /// Serializes a Solana message. `version == nil` is a legacy message; a
    /// version is written as the `0x80 | version` prefix and gets an empty
    /// address-table-lookup list. Counts stay below 128, so each compact-u16 is
    /// one byte.
    private func makeMessage(
        version: UInt8? = nil,
        header: [UInt8],
        accountKeys: [Data],
        instructions: [Data]
    ) -> Data {
        var message = Data()
        if let version {
            message.append(0x80 | version)
        }
        message.append(contentsOf: header)
        message.append(UInt8(accountKeys.count))
        accountKeys.forEach { message.append($0) }
        message.append(Data(repeating: 0x00, count: 32))
        message.append(UInt8(instructions.count))
        instructions.forEach { message.append($0) }
        if version != nil {
            message.append(0x00)
        }
        return message
    }

    /// A legacy System Program transfer paid for and signed by `feePayer` alone.
    private func makeLegacyTransferMessage(feePayer: Data, lamports: UInt64 = 1_000_000) -> Data {
        makeMessage(
            header: [1, 0, 1],
            accountKeys: [feePayer, transferRecipientKey, systemProgramKey],
            instructions: [makeTransferInstruction(programIndex: 2, from: 0, to: 1, lamports: lamports)]
        )
    }

    // MARK: - Raw (dApp) signing path

    func testSignRawTransactionSplicesSignatureAndKeepsBase64Encoding() throws {
        let privateKey = try makeSignerKey()
        let publicKey = privateKey.getPublicKeyEd25519()
        let message = makeLegacyTransferMessage(feePayer: publicKey.data)
        var unsigned = Data([0x01])
        unsigned.append(Data(repeating: 0x00, count: 64))
        unsigned.append(message)
        let base64Transaction = unsigned.base64EncodedString()

        let preImageHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            coinHexPubKey: publicKey.data.hexString,
            base64Transaction: base64Transaction
        )
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

    // MARK: - Raw signing: signer slot resolution

    private let emptySignatureSlot = Data(repeating: 0x00, count: 64)

    private struct SponsoredTransactionFixture {
        let transaction: Data
        let message: Data
        let cosignerSignature: Data
    }

    /// `[shortvec(slot count)][64-byte slots][message]`.
    private func makeRawTransaction(signatureSlots: [Data], message: Data) -> Data {
        var transaction = Data([UInt8(signatureSlots.count)])
        signatureSlots.forEach { transaction.append($0) }
        transaction.append(message)
        return transaction
    }

    private func makeKey(fill: UInt8) throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: Data(repeating: fill, count: 32)))
    }

    /// Slot `index` of a fixture transaction (every fixture here has a
    /// one-byte slot count).
    private func signatureSlot(_ index: Int, of transaction: Data) -> Data {
        let start = transaction.startIndex + 1 + index * 64
        return transaction.subdata(in: start..<(start + 64))
    }

    /// The sponsored shape: a v0 transaction with three required signers where
    /// the vault is signer 1, not the fee payer.
    ///
    ///     staticAccountKeys[0] = relayer    fee payer, signs later (slot left zero)
    ///     staticAccountKeys[1] = vault      the account this device signs for
    ///     staticAccountKeys[2] = co-signer  already signed
    private func makeSponsoredV0Transaction(vault: Data, relayer: Data, cosigner: PrivateKey) throws -> SponsoredTransactionFixture {
        let message = makeMessage(
            version: 0,
            header: [3, 0, 1],
            accountKeys: [relayer, vault, cosigner.getPublicKeyEd25519().data, transferRecipientKey, systemProgramKey],
            instructions: [
                makeTransferInstruction(programIndex: 4, from: 1, to: 3, lamports: 1_000_000),
                makeTransferInstruction(programIndex: 4, from: 2, to: 3, lamports: 1)
            ]
        )
        let cosignerSignature = try XCTUnwrap(cosigner.sign(digest: message, curve: .ed25519))
        return SponsoredTransactionFixture(
            transaction: makeRawTransaction(
                signatureSlots: [emptySignatureSlot, emptySignatureSlot, cosignerSignature],
                message: message
            ),
            message: message,
            cosignerSignature: cosignerSignature
        )
    }

    /// Runs `transaction` through the raw path the way keysign does:
    /// pre-image, TSS-shaped signature, splice.
    private func signRaw(_ transaction: Data, privateKey: PrivateKey) throws -> SignedTransactionResult {
        let base64Transaction = transaction.base64EncodedString()
        let vaultHexPubKey = privateKey.getPublicKeyEd25519().data.hexString
        let preImageHashes = try SolanaHelper.getPreSignedImageHashForRaw(
            coinHexPubKey: vaultHexPubKey,
            base64Transaction: base64Transaction
        )
        let signatures = try makeSignatures(preImageHashes: preImageHashes, privateKey: privateKey)
        return try SolanaHelper.signRawTransaction(
            coinHexPubKey: vaultHexPubKey,
            base64Transaction: base64Transaction,
            signatures: signatures
        )
    }

    private func assertThrows<T>(
        _ expression: @autoclosure () throws -> T,
        messageContaining expected: String,
        _ stage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), "\(stage) accepted it", file: file, line: line) { error in
            XCTAssertTrue(
                error.localizedDescription.contains(expected),
                "\(stage): \"\(error.localizedDescription)\" does not mention \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    /// Both raw-path stages refuse `transaction` for the same reason: the
    /// pre-image step before the ceremony, and the splice after it, reached
    /// here with a valid signature over the message as if the ceremony had run.
    private func assertRawSigningRefuses(
        _ transaction: Data,
        privateKey: PrivateKey,
        messageContaining expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let base64Transaction = transaction.base64EncodedString()
        let vaultHexPubKey = privateKey.getPublicKeyEd25519().data.hexString
        let slotCount = Int(try XCTUnwrap(transaction.first, file: file, line: line))
        let message = transaction.subdata(in: (1 + slotCount * 64)..<transaction.count)
        let signatures = try makeSignatures(preImageHashes: [message.hexString], privateKey: privateKey)

        assertThrows(
            try SolanaHelper.getPreSignedImageHashForRaw(coinHexPubKey: vaultHexPubKey, base64Transaction: base64Transaction),
            messageContaining: expected,
            "pre-image",
            file: file,
            line: line
        )
        assertThrows(
            try SolanaHelper.signRawTransaction(
                coinHexPubKey: vaultHexPubKey,
                base64Transaction: base64Transaction,
                signatures: signatures
            ),
            messageContaining: expected,
            "splice",
            file: file,
            line: line
        )
    }

    /// A vault that is the fee payer (signer 0) gets exactly what the old
    /// slot-0 splice produced, and a co-signer's slot is left alone.
    func testSignRawTransactionKeepsFeePayerSignatureInSlotZeroByteIdentical() throws {
        let privateKey = try makeSignerKey()
        let cosigner = try makeKey(fill: 0x03)
        let message = makeMessage(
            header: [2, 0, 1],
            accountKeys: [
                privateKey.getPublicKeyEd25519().data,
                cosigner.getPublicKeyEd25519().data,
                transferRecipientKey,
                systemProgramKey
            ],
            instructions: [
                makeTransferInstruction(programIndex: 3, from: 0, to: 2, lamports: 1_000_000),
                makeTransferInstruction(programIndex: 3, from: 1, to: 2, lamports: 1)
            ]
        )
        let cosignerSignature = try XCTUnwrap(cosigner.sign(digest: message, curve: .ed25519))
        let unsigned = makeRawTransaction(signatureSlots: [emptySignatureSlot, cosignerSignature], message: message)

        let result = try signRaw(unsigned, privateKey: privateKey)

        let vaultSignature = try XCTUnwrap(privateKey.sign(digest: message, curve: .ed25519))
        var expected = unsigned
        expected.replaceSubrange(1..<65, with: vaultSignature)
        XCTAssertEqual(Data(base64Encoded: result.rawTransaction), expected)
        XCTAssertEqual(result.transactionHash, Base58.encodeNoCheck(data: vaultSignature))
    }

    /// The in-app producers of raw transactions (native staking; WalletCore's
    /// own v0 transfer as the same shape) always make the vault the sole
    /// signer, so they keep landing in slot 0.
    func testSignRawTransactionSignsInAppWalletCoreTransactionsInSlotZero() throws {
        let privateKey = try makeSignerKey()
        let publicKey = privateKey.getPublicKeyEd25519()
        let payload = try makeNativeTransferPayload(privateKey: privateKey)
        let account = try makeRecipientAddress()

        let transfer = try XCTUnwrap(Base58.decodeNoCheck(string: SolanaHelper.getZeroSignedTransaction(keysignPayload: payload)))
        var unsignedTransactions = [transfer]
        for stakingPayload in [
            SolanaStakingPayload.delegate(votePubkey: account, lamports: 2_000_000_000),
            .unstake(stakeAccount: account),
            .withdraw(stakeAccount: account, lamports: 1_000_000_000)
        ] {
            let base64 = try SolanaHelper.buildStakingUnsignedTransaction(
                keysignPayload: payload.withSolanaStakingPayload(stakingPayload)
            )
            unsignedTransactions.append(try XCTUnwrap(Data(base64Encoded: base64)))
        }

        for unsigned in unsignedTransactions {
            let result = try signRaw(unsigned, privateKey: privateKey)
            let signed = try XCTUnwrap(Data(base64Encoded: result.rawTransaction))

            XCTAssertEqual(signed.first, 0x01)
            let message = unsigned.subdata(in: 65..<unsigned.count)
            XCTAssertTrue(publicKey.verify(signature: signatureSlot(0, of: signed), message: message))
            XCTAssertEqual(signed.subdata(in: 65..<signed.count), message)
        }
    }

    func testSignRawTransactionSplicesIntoVaultSlotOfSponsoredV0Transaction() throws {
        let privateKey = try makeSignerKey()
        let vaultKey = privateKey.getPublicKeyEd25519()
        let fixture = try makeSponsoredV0Transaction(
            vault: vaultKey.data,
            relayer: makeKey(fill: 0x02).getPublicKeyEd25519().data,
            cosigner: makeKey(fill: 0x03)
        )
        // The fixture is a well-formed v0 transaction with the vault at signer 1.
        let parsed = try SolanaV0Transaction(wireBytes: [UInt8](fixture.transaction))
        XCTAssertEqual(parsed.numRequiredSignatures, 3)
        XCTAssertEqual(parsed.staticAccountKeys[1], [UInt8](vaultKey.data))
        XCTAssertEqual(
            try SolanaHelper.getPreSignedImageHashForRaw(
                coinHexPubKey: vaultKey.data.hexString,
                base64Transaction: fixture.transaction.base64EncodedString()
            ),
            [fixture.message.hexString]
        )

        let result = try signRaw(fixture.transaction, privateKey: privateKey)
        let signed = try XCTUnwrap(Data(base64Encoded: result.rawTransaction))

        XCTAssertEqual(signatureSlot(0, of: signed), emptySignatureSlot, "the relayer's slot stays open")
        let vaultSignature = signatureSlot(1, of: signed)
        XCTAssertTrue(vaultKey.verify(signature: vaultSignature, message: fixture.message))
        XCTAssertEqual(signatureSlot(2, of: signed), fixture.cosignerSignature)
        // Nothing but the vault's slot changed, message included.
        var expected = fixture.transaction
        expected.replaceSubrange(65..<129, with: vaultSignature)
        XCTAssertEqual(signed, expected)
        // The transaction id is the fee payer's signature, and the relayer has not signed yet.
        XCTAssertEqual(result.transactionHash, "")
    }

    /// Once the relayer has signed slot 0, that signature is the transaction id
    /// the chain indexes, not the vault's own signature in slot 1.
    func testSignRawTransactionReportsTheRelayersSignatureAsTheIdOnceItHasSigned() throws {
        let privateKey = try makeSignerKey()
        let vaultKey = privateKey.getPublicKeyEd25519()
        let relayer = try makeKey(fill: 0x02)
        let fixture = try makeSponsoredV0Transaction(
            vault: vaultKey.data,
            relayer: relayer.getPublicKeyEd25519().data,
            cosigner: makeKey(fill: 0x03)
        )
        let relayerSignature = try XCTUnwrap(relayer.sign(digest: fixture.message, curve: .ed25519))
        var relayerSigned = fixture.transaction
        relayerSigned.replaceSubrange(1..<65, with: relayerSignature)

        let result = try signRaw(relayerSigned, privateKey: privateKey)
        let signed = try XCTUnwrap(Data(base64Encoded: result.rawTransaction))

        XCTAssertEqual(signatureSlot(0, of: signed), relayerSignature)
        XCTAssertTrue(vaultKey.verify(signature: signatureSlot(1, of: signed), message: fixture.message))
        XCTAssertEqual(result.transactionHash, Base58.encodeNoCheck(data: relayerSignature))
    }

    func testSignRawTransactionRejectsKeyThatIsNotARequiredSigner() throws {
        let privateKey = try makeSignerKey()
        let vaultKey = privateKey.getPublicKeyEd25519().data
        let payer = try makeKey(fill: 0x02).getPublicKeyEd25519().data

        // The vault is an account key the transaction pays into, not a signer.
        let vaultAsRecipient = makeMessage(
            header: [1, 0, 1],
            accountKeys: [payer, vaultKey, systemProgramKey],
            instructions: [makeTransferInstruction(programIndex: 2, from: 0, to: 1, lamports: 1_000_000)]
        )
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: vaultAsRecipient),
            privateKey: privateKey,
            messageContaining: "not a required signer"
        )

        // The vault is not in the transaction at all.
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: makeLegacyTransferMessage(feePayer: payer)),
            privateKey: privateKey,
            messageContaining: "not a required signer"
        )
    }

    func testSignRawTransactionRejectsSignatureSlotCountMismatch() throws {
        let privateKey = try makeSignerKey()
        let vaultKey = privateKey.getPublicKeyEd25519().data
        let relayer = try makeKey(fill: 0x02).getPublicKeyEd25519().data
        let fixture = try makeSponsoredV0Transaction(vault: vaultKey, relayer: relayer, cosigner: makeKey(fill: 0x03))

        // Too few: one slot for three required signers.
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: fixture.message),
            privateKey: privateKey,
            messageContaining: "declares 1 signature slot(s) but the message requires 3"
        )
        // Too many: four slots for three.
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: Array(repeating: emptySignatureSlot, count: 4), message: fixture.message),
            privateKey: privateKey,
            messageContaining: "declares 4 signature slot(s) but the message requires 3"
        )
        // Too few even where the vault's own slot would fit the envelope.
        let twoSigners = makeMessage(
            header: [2, 0, 1],
            accountKeys: [vaultKey, relayer, transferRecipientKey, systemProgramKey],
            instructions: [makeTransferInstruction(programIndex: 3, from: 0, to: 2, lamports: 1_000_000)]
        )
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: twoSigners),
            privateKey: privateKey,
            messageContaining: "declares 1 signature slot(s) but the message requires 2"
        )
    }

    func testSignRawTransactionRejectsUnsupportedMessageVersion() throws {
        let privateKey = try makeSignerKey()
        let versionOne = makeMessage(
            version: 1,
            header: [1, 0, 1],
            accountKeys: [privateKey.getPublicKeyEd25519().data, transferRecipientKey, systemProgramKey],
            instructions: [makeTransferInstruction(programIndex: 2, from: 0, to: 1, lamports: 1_000_000)]
        )

        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: versionOne),
            privateKey: privateKey,
            messageContaining: "Unsupported Solana message version 1"
        )
    }

    func testSignRawTransactionRejectsTruncatedMessage() throws {
        let privateKey = try makeSignerKey()
        let vaultKey = privateKey.getPublicKeyEd25519().data

        // A v0 prefix followed by a partial header.
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: Data([0x80, 0x01])),
            privateKey: privateKey,
            messageContaining: "too short for header"
        )

        // One required signer, two declared keys, only one present.
        var truncatedKeys = Data([1, 0, 1, 2])
        truncatedKeys.append(vaultKey)
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: truncatedKeys),
            privateKey: privateKey,
            messageContaining: "too short for declared account key count (2)"
        )

        // Two required signers but only one listed key.
        var underListed = Data([2, 0, 0, 1])
        underListed.append(vaultKey)
        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot, emptySignatureSlot], message: underListed),
            privateKey: privateKey,
            messageContaining: "requires 2 signatures but lists 1 account keys"
        )
    }

    /// `0x81 0x00` is a zero-padded encoding of 1 that the runtime rejects, so
    /// slot resolution must not read the keys behind it as if it were valid.
    func testSignRawTransactionRejectsNonCanonicalAccountKeyCount() throws {
        let privateKey = try makeSignerKey()
        var padded = Data([1, 0, 0, 0x81, 0x00])
        padded.append(privateKey.getPublicKeyEd25519().data)

        try assertRawSigningRefuses(
            makeRawTransaction(signatureSlots: [emptySignatureSlot], message: padded),
            privateKey: privateKey,
            messageContaining: "malformed compact-u16"
        )
    }

    /// Real v0 transactions with address lookup tables (the Kamino golden
    /// vectors) resolve their owner as the sole required signer.
    func testRequiredSignersOfKaminoVectorsIsTheOwnerAlone() throws {
        for vector in KaminoTransactionFixtures.all {
            let owner = try XCTUnwrap(Base58.decodeNoCheck(string: vector.feePayer), vector.name)
            for transaction in [vector.source, vector.injected] {
                let messageHex = try XCTUnwrap(
                    SolanaHelper.getPreSignedImageHashForRaw(
                        coinHexPubKey: owner.hexString,
                        base64Transaction: transaction
                    ).first,
                    vector.name
                )
                let message = try XCTUnwrap(Data(hexString: messageHex), vector.name)
                XCTAssertEqual(try SolanaHelper.requiredSigners(ofMessage: message), [owner], vector.name)
            }
        }
    }

    // MARK: - Raw signing: pre-ceremony signer check

    /// The keysign entry point refuses a transaction that does not list the
    /// vault's key among its required signers before any ceremony starts.
    func testPreImageRefusesATransactionTheVaultIsNotRequiredToSign() throws {
        let payer = try makeKey(fill: 0x02).getPublicKeyEd25519().data
        let transaction = makeRawTransaction(
            signatureSlots: [emptySignatureSlot],
            message: makeLegacyTransferMessage(feePayer: payer)
        )
        let payload = try makeSignSolanaPayload(rawTransactions: [transaction.base64EncodedString()])

        assertThrows(
            try SolanaHelper.getPreSignedImageHash(keysignPayload: payload),
            messageContaining: "not a required signer",
            "pre-image"
        )
    }

    func testPreImageRefusesASignatureSlotCountTheMessageDisagreesWith() throws {
        let fixture = try makeSponsoredV0Transaction(
            vault: makeSignerKey().getPublicKeyEd25519().data,
            relayer: makeKey(fill: 0x02).getPublicKeyEd25519().data,
            cosigner: makeKey(fill: 0x03)
        )
        let transaction = makeRawTransaction(signatureSlots: [emptySignatureSlot], message: fixture.message)
        let payload = try makeSignSolanaPayload(rawTransactions: [transaction.base64EncodedString()])

        assertThrows(
            try SolanaHelper.getPreSignedImageHash(keysignPayload: payload),
            messageContaining: "declares 1 signature slot(s) but the message requires 3",
            "pre-image"
        )
    }

    /// The check only adds a refusal: wherever the vault signs, the pre-image
    /// is still the message bytes verbatim, which is what every co-signing
    /// device hashes.
    func testPreImageIsStillTheMessageVerbatimWhereverTheVaultSigns() throws {
        let vaultKey = try makeSignerKey().getPublicKeyEd25519().data
        let cosignerKey = try makeKey(fill: 0x03).getPublicKeyEd25519().data
        let soleSigner = makeLegacyTransferMessage(feePayer: vaultKey)
        let feePayerWithCosigner = makeMessage(
            header: [2, 0, 1],
            accountKeys: [vaultKey, cosignerKey, transferRecipientKey, systemProgramKey],
            instructions: [makeTransferInstruction(programIndex: 3, from: 0, to: 2, lamports: 1_000_000)]
        )
        let sponsored = try makeSponsoredV0Transaction(
            vault: vaultKey,
            relayer: makeKey(fill: 0x02).getPublicKeyEd25519().data,
            cosigner: makeKey(fill: 0x03)
        )
        let cases: [(name: String, transaction: Data, message: Data)] = [
            ("sole signer", makeRawTransaction(signatureSlots: [emptySignatureSlot], message: soleSigner), soleSigner),
            (
                "fee payer beside a co-signer",
                makeRawTransaction(signatureSlots: [emptySignatureSlot, emptySignatureSlot], message: feePayerWithCosigner),
                feePayerWithCosigner
            ),
            ("sponsored, vault at signer 1", sponsored.transaction, sponsored.message)
        ]

        for testCase in cases {
            let payload = try makeSignSolanaPayload(rawTransactions: [testCase.transaction.base64EncodedString()])
            XCTAssertEqual(
                try SolanaHelper.getPreSignedImageHash(keysignPayload: payload),
                [testCase.message.hexString],
                testCase.name
            )
        }
    }

    // MARK: - signAllTransactions batch guard

    /// A single-signer raw transaction the test vault pays for, base64-encoded:
    /// the shape the dApp raw-signing path (SignSolana.rawTransactions) consumes.
    private func makeRawSolanaTransactionBase64(lamports: UInt64) throws -> String {
        let feePayer = try makeSignerKey().getPublicKeyEd25519().data
        return makeRawTransaction(
            signatureSlots: [emptySignatureSlot],
            message: makeLegacyTransferMessage(feePayer: feePayer, lamports: lamports)
        ).base64EncodedString()
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
        let tx1 = try makeRawSolanaTransactionBase64(lamports: 7)
        let tx2 = try makeRawSolanaTransactionBase64(lamports: 9)
        let payload = try makeSignSolanaPayload(rawTransactions: [tx1, tx2])

        XCTAssertThrowsError(try SolanaHelper.getPreSignedImageHash(keysignPayload: payload))
    }

    /// Regression: the single raw-transaction path is untouched and still
    /// yields exactly one non-empty pre-image hash.
    func testGetPreSignedImageHashAllowsSingleRawTransaction() throws {
        let tx = try makeRawSolanaTransactionBase64(lamports: 7)
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
