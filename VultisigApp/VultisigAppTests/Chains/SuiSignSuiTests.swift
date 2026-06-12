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
        XCTAssertEqual(summary.gasBudget, 3_000_000)
        XCTAssertEqual(summary.gasPrice, 1000)
    }

    /// The parser fully decodes every input and command from the #705 vector:
    /// two Pure inputs, then SplitCoins(GasCoin, [Input 0]) and
    /// TransferObjects([NestedResult(0,0)], Input 1).
    func testTransactionDataParserDecodesInputsAndCommands() throws {
        let summary = try XCTUnwrap(
            SuiTransactionDataParser.parse(base64TransactionData: unsignedTxMsg)
        )

        // Inputs: both Pure. The first is the u64 split amount (8 bytes), the
        // second is the 32-byte recipient address.
        XCTAssertEqual(summary.inputs.count, 2)
        guard case let .pure(amountBytes) = summary.inputs[0] else {
            return XCTFail("expected input 0 to be a Pure value")
        }
        XCTAssertEqual(amountBytes.count, 8)
        guard case let .pure(addressBytes) = summary.inputs[1] else {
            return XCTFail("expected input 1 to be a Pure value")
        }
        XCTAssertEqual(addressBytes.count, 32)

        // Commands: SplitCoins then TransferObjects, with the exact argument
        // shapes (GasCoin / Input(u16) / NestedResult(u16,u16)).
        XCTAssertEqual(summary.commands.count, 2)
        guard case let .splitCoins(coin, amounts) = summary.commands[0] else {
            return XCTFail("expected command 0 to be SplitCoins")
        }
        XCTAssertEqual(coin, .gasCoin)
        XCTAssertEqual(amounts, [.input(index: 0)])

        guard case let .transferObjects(objects, address) = summary.commands[1] else {
            return XCTFail("expected command 1 to be TransferObjects")
        }
        XCTAssertEqual(objects, [.nestedResult(commandIndex: 0, resultIndex: 0)])
        XCTAssertEqual(address, .input(index: 1))
    }

    /// A hand-crafted PTB exercises a MoveCall with a type argument plus an
    /// object input, proving the decoder walks `String`, `TypeTag`, `u16`
    /// argument indices, and `ObjectArg` correctly across multiple commands.
    func testTransactionDataParserDecodesMoveCallAndObjectInput() throws {
        let summary = try XCTUnwrap(
            SuiTransactionDataParser.parse(base64TransactionData: Self.moveCallVector)
        )

        // One shared-object input.
        XCTAssertEqual(summary.inputs.count, 1)
        guard case let .object(kind, objectId, mutable) = summary.inputs[0] else {
            return XCTFail("expected a single object input")
        }
        XCTAssertEqual(kind, .sharedObject)
        XCTAssertEqual(mutable, true)
        XCTAssertTrue(objectId.hasPrefix("0x"))

        // One MoveCall command with package::module::function, a SUI type arg,
        // and two arguments: Input(0) and GasCoin.
        XCTAssertEqual(summary.commands.count, 1)
        guard case let .moveCall(package, module, function, typeArguments, arguments) = summary.commands[0] else {
            return XCTFail("expected a MoveCall command")
        }
        XCTAssertTrue(package.hasPrefix("0x"))
        XCTAssertEqual(module, "pool")
        XCTAssertEqual(function, "swap")
        // The decoder renders the struct's full 32-byte address verbatim (no
        // leading-zero normalization); the crafted vector uses an all-0x02
        // address for the type-tag struct.
        XCTAssertEqual(typeArguments.count, 1)
        XCTAssertEqual(
            typeArguments.first,
            "0x0202020202020202020202020202020202020202020202020202020202020202::sui::SUI"
        )
        XCTAssertEqual(arguments, [.input(index: 0), .gasCoin])
    }

    /// A base64 BCS `TransactionData::V1` built by hand exercising the
    /// MoveCall + TypeTag::struct + SharedObject input paths.
    private static let moveCallVector: String = {
        var bytes: [UInt8] = []
        func uleb(_ value: Int) { bytes.append(UInt8(value)) }      // single-byte values only
        func u16(_ value: UInt16) { bytes.append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8)]) }
        func u64(_ value: UInt64) {
            for i in 0..<8 { bytes.append(UInt8((value >> (8 * i)) & 0xff)) }
        }
        func address(_ byte: UInt8) { bytes.append(contentsOf: Array(repeating: byte, count: 32)) }
        func string(_ value: String) {
            let utf8 = Array(value.utf8)
            uleb(utf8.count)
            bytes.append(contentsOf: utf8)
        }

        // TransactionData::V1, kind = ProgrammableTransaction.
        uleb(0)
        uleb(0)

        // inputs: 1 × Object(SharedObject)
        uleb(1)
        uleb(1)          // CallArg::Object
        uleb(1)          // ObjectArg::SharedObject
        address(0xAB)    // objectId
        u64(7)           // initial_shared_version
        bytes.append(1)  // mutable = true

        // commands: 1 × MoveCall
        uleb(1)
        uleb(0)          // Command::MoveCall
        address(0xCD)    // package
        string("pool")   // module
        string("swap")   // function
        // typeArguments: [TypeTag::struct(0x2::sui::SUI)]
        uleb(1)
        uleb(7)          // TypeTag::struct
        address(0x02)    // struct address
        string("sui")
        string("SUI")
        uleb(0)          // struct typeParams: []
        // arguments: [Input(0), GasCoin]
        uleb(2)
        uleb(1); u16(0)  // Argument::Input(0)
        uleb(0)          // Argument::GasCoin

        // sender
        address(0xEF)

        // gasData: payment [1 × ObjectRef], owner, price, budget
        uleb(1)
        address(0x10)    // objectId
        u64(3)           // version
        uleb(3); bytes.append(contentsOf: [0x01, 0x02, 0x03]) // digest (vec<u8>)
        address(0xEF)    // owner
        u64(1000)        // price
        u64(5_000_000)   // budget

        // expiration: None
        uleb(0)

        return Data(bytes).base64EncodedString()
    }()
}
