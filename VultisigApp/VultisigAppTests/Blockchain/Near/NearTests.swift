//
//  NearTests.swift
//  VultisigAppTests
//
//  Focused native-NEAR coverage: the account-ID grammar, the nearcore 2.13.4
//  gas/storage equation, the frozen nonce rule, the `NearSpecific` wire
//  round-trip, the native-only rejections, and the signing digest checked
//  against an INDEPENDENTLY encoded Borsh body (the same layout the SDK's
//  `near.native.integration.test.ts` builds, so the two platforms cannot agree
//  by both asking WalletCore).
//
//  No network: every number here is either a nearcore literal or computed
//  locally. The RPC-facing paths are covered by construction, not by test.
//
//  The class is named `Near`, not `NearTests`, because xcodebuild matches the
//  class component of `-only-testing:` EXACTLY: the focused run documented for
//  this path is `-only-testing:VultisigAppTests/Near`, and a `NearTests` class
//  makes that filter select nothing at all (a green exit with 0 tests run).
//

import BigInt
import CryptoKit
import Foundation
import Tss
import WalletCore
import XCTest

@testable import VultisigApp

final class Near: XCTestCase {

    // MARK: - Fixtures

    /// RFC 8032 §7.1 TEST 1 public key, which is also its own implicit account id.
    private static let sender = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    /// RFC 8032 §7.1 TEST 1 secret key, whose public key is `sender`.
    private static let senderSeed = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    private static let namedReceiver = "wrap.near"
    private static let implicitReceiver = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

    /// The SDK vector's block hash: `sha256` of a base58 string, so the vector
    /// carries 32 bytes without depending on a decoder.
    private static let blockHash = Data(SHA256.hash(data: Data("BB5kGq7xVbyw5kfMrRtYmbuUoWKqnNA6xeRU187RF7kx".utf8)))

    /// Above 2^53, where a `Double` would round it to a neighbouring value.
    private static let accessKeyNonce = BigInt("78000000000000001")
    private static let transactionNonce: UInt64 = 78_000_000_000_000_002
    private static let maxU64 = (BigInt(1) << 64) - 1

    // nearcore protocol 86 (2.13.4) literals, taken from the protocol config
    // the SDK's integration vector pins.
    private static let gasPrice = BigInt(100_000_000)
    private static let feeConfig = NearFees.FeeConfig(
        actionReceiptCreation: NearFees.ParameterCost(
            sendSir: 108_059_500_000,
            sendNotSir: 108_059_500_000,
            execution: 108_059_500_000
        ),
        transfer: NearFees.ParameterCost(
            sendSir: 115_123_062_500,
            sendNotSir: 115_123_062_500,
            execution: 115_123_062_500
        ),
        createAccount: NearFees.ParameterCost(
            sendSir: 500_000_000_000,
            sendNotSir: 500_000_000_000,
            execution: 7_200_000_000_000
        ),
        addFullAccessKey: NearFees.ParameterCost(
            sendSir: 101_765_125_000,
            sendNotSir: 101_765_125_000,
            execution: 101_765_125_000
        ),
        minGasPurchasePrice: BigInt(1_000_000_000),
        storageAmountPerByte: BigInt("10000000000000000000")
    )

    private static let namedGasFee = BigInt("245500818750000000000")
    private static let implicitGasFee = BigInt("7607442456250000000000")

    // MARK: - Account-id grammar

    func testAcceptsImplicitAndNamedAccountIds() {
        XCTAssertTrue(NearAccountId.isValid(Self.sender))
        XCTAssertTrue(NearAccountId.isValid(Self.implicitReceiver))
        XCTAssertTrue(NearAccountId.isValid("wrap.near"))
        XCTAssertTrue(NearAccountId.isValid("a-b_c.1near"))
        XCTAssertTrue(NearAccountId.isValid("ab"))

        XCTAssertTrue(NearAccountId.isImplicit(Self.sender))
        XCTAssertFalse(NearAccountId.isImplicit("wrap.near"))
    }

    func testRejectsTheAddressFamiliesANativeTransferCannotAddress() {
        // 0x… (NEP-518) and 0s… (NEP-616) are different account families, not
        // spellings of the implicit one, so they are refused rather than
        // normalized into an account the user did not name.
        XCTAssertFalse(NearAccountId.isValid("0x85f17cf997934a597031b2e18a9ab6ebd4b9f6a4"))
        XCTAssertFalse(NearAccountId.isValid("0s85f17cf997934a597031b2e18a9ab6ebd4b9f6a4"))

        // Case is part of the account id; an uppercase spelling is a different
        // string, not a case-insensitive match.
        XCTAssertFalse(NearAccountId.isValid("WRAP.NEAR"))
        XCTAssertFalse(NearAccountId.isValid(Self.sender.uppercased()))
    }

    func testRejectsGrammarViolations() {
        XCTAssertFalse(NearAccountId.isValid(""))
        XCTAssertFalse(NearAccountId.isValid("a"))                    // below the 2-char floor
        XCTAssertFalse(NearAccountId.isValid(String(repeating: "a", count: 65)))  // above the 64-char ceiling
        XCTAssertFalse(NearAccountId.isValid("wrap..near"))           // doubled separator
        XCTAssertFalse(NearAccountId.isValid(".wrap"))                // leading separator
        XCTAssertFalse(NearAccountId.isValid("wrap."))                // trailing separator
        XCTAssertFalse(NearAccountId.isValid("wrap-_near"))           // two separators in a row
        XCTAssertFalse(NearAccountId.isValid("wrap near"))            // not in the alphabet
        XCTAssertFalse(NearAccountId.isValid("wrap/near"))
    }

    // MARK: - Frozen nonce

    func testTransactionNonceIsTheAccessKeyNonceSuccessor() throws {
        // A brand-new access key starts at 0, and 0 is not a valid transaction
        // nonce: the first transaction carries 1.
        XCTAssertEqual(try NearHelper.transactionNonce(accessKeyNonce: 0), 1)
        XCTAssertEqual(try NearHelper.transactionNonce(accessKeyNonce: 41), 42)

        // Above 2^53, where the digits stop being representable as a Double.
        let nonce = try NearHelper.transactionNonce(accessKeyNonce: Self.accessKeyNonce)
        XCTAssertEqual(nonce, 78_000_000_000_000_002)
        XCTAssertEqual(nonce.description, "78000000000000002")
    }

    func testTransactionNonceFailsClosedAtTheTopOfTheUint64Field() {
        XCTAssertThrowsError(try NearHelper.transactionNonce(accessKeyNonce: Self.maxU64)) { error in
            XCTAssertTrue(error.localizedDescription.contains("no successor"))
        }
        XCTAssertEqual(try? NearHelper.transactionNonce(accessKeyNonce: Self.maxU64 - 1), UInt64.max)
    }

    // MARK: - Fee / storage equation

    func testReservesTheApprovedUpfrontGasForANamedReceiver() {
        let reservation = NearFees.gasReservation(
            config: Self.feeConfig,
            gasPrice: Self.gasPrice,
            senderIsReceiver: false,
            receiverIsImplicit: false
        )

        // (receipt creation + transfer) send gas at the block price plus the
        // same execution gas at max(block price, min purchase price).
        XCTAssertEqual(reservation.reserved, Self.namedGasFee)
        XCTAssertEqual(reservation.burntPrice, Self.gasPrice)
        XCTAssertEqual(reservation.receiptPrice, Self.feeConfig.minGasPurchasePrice)
    }

    func testReservesAccountCreationGasForAnImplicitReceiver() {
        let reservation = NearFees.gasReservation(
            config: Self.feeConfig,
            gasPrice: Self.gasPrice,
            senderIsReceiver: false,
            receiverIsImplicit: true
        )

        // An implicit receiver reserves create_account + add_full_access_key gas
        // whether or not the account already exists.
        XCTAssertEqual(reservation.reserved, Self.implicitGasFee)
    }

    func testSelfSendPaysTheCheaperSendGas() {
        let reservation = NearFees.gasReservation(
            config: Self.feeConfig,
            gasPrice: Self.gasPrice,
            senderIsReceiver: true,
            receiverIsImplicit: true
        )

        // `send_sir` on every send-gas term; the receipt gas is unchanged.
        let expectedBurntGas = BigInt(108_059_500_000) + BigInt(115_123_062_500) + BigInt(500_000_000_000) + BigInt(101_765_125_000)
        XCTAssertEqual(reservation.burntGas, expectedBurntGas)
        XCTAssertEqual(
            reservation.reserved,
            expectedBurntGas * Self.gasPrice
                + (BigInt(108_059_500_000) + BigInt(115_123_062_500) + BigInt(7_200_000_000_000) + BigInt(101_765_125_000))
                    * Self.feeConfig.minGasPurchasePrice
        )
    }

    func testStorageReserveExemptsZeroBalanceAccountsAtTheLimit() {
        // NEP-448: an account using at most 770 bytes is exempt, and an
        // implicit account uses 182 bytes.
        XCTAssertEqual(
            NearFees.storageReserve(storageUsage: 182, locked: 0, storageAmountPerByte: Self.feeConfig.storageAmountPerByte),
            0
        )
        XCTAssertEqual(
            NearFees.storageReserve(storageUsage: 770, locked: 0, storageAmountPerByte: Self.feeConfig.storageAmountPerByte),
            0
        )
        // One byte past the exemption, the whole usage is billable.
        XCTAssertEqual(
            NearFees.storageReserve(storageUsage: 771, locked: 0, storageAmountPerByte: Self.feeConfig.storageAmountPerByte),
            BigInt("7710000000000000000000")
        )
    }

    func testLockedStakeBacksStorageWithoutBecomingSpendable() {
        let amount = BigInt("1000000000000000000000000")
        let usage = BigInt(1000)
        let storageAmountPerByte = Self.feeConfig.storageAmountPerByte

        // Locked stake only relaxes the storage requirement …
        XCTAssertEqual(
            NearFees.storageReserve(storageUsage: usage, locked: BigInt("10000000000000000000000"), storageAmountPerByte: storageAmountPerByte),
            0
        )
        // … and more locked than required does not liberate the surplus: MAX can
        // never exceed the unlocked balance less what is left to reserve.
        let reserve = NearFees.storageReserve(storageUsage: usage, locked: 0, storageAmountPerByte: storageAmountPerByte)
        let maxSendable = NearFees.maxSendable(amount: amount, gasReservation: Self.namedGasFee, storageReserve: reserve)
        XCTAssertEqual(maxSendable, amount - Self.namedGasFee - reserve)
        XCTAssertEqual(
            NearFees.maxSendable(amount: Self.namedGasFee, gasReservation: Self.namedGasFee, storageReserve: reserve),
            0
        )
    }

    func testRequiredAmountAddsTheReservationAndTheStorageBacking() {
        let reserve = NearFees.storageReserve(storageUsage: 1000, locked: 0, storageAmountPerByte: Self.feeConfig.storageAmountPerByte)
        XCTAssertEqual(
            NearFees.requiredAmount(requestedAmount: 1000, gasReservation: Self.namedGasFee, storageReserve: reserve),
            1000 + Self.namedGasFee + reserve
        )
    }

    // MARK: - Signing digest against an independent Borsh encoding

    func testPreSigningHashMatchesAnIndependentlyEncodedBorshBody() throws {
        let payload = try makePayload()

        let hash = try XCTUnwrap(NearHelper.getPreSignedImageHash(keysignPayload: payload).first)

        // WalletCore's pre-image hash for NEAR is the signed digest:
        // sha256(borsh(TransactionV0)).
        let expectedBodyHash = Data(SHA256.hash(data: try Self.borshBody(
            signerId: Self.sender,
            publicKey: Data(hexString: Self.sender)!,
            nonce: Self.transactionNonce,
            receiverId: Self.namedReceiver,
            blockHash: Self.blockHash,
            deposit: 1000,
            actionCount: 1
        )))
        XCTAssertEqual(hash, expectedBodyHash.hexString)
    }

    func testSignedTransactionHashIsTheUnsignedBodyDigestNotTheSignedBytes() throws {
        let body = try Self.borshBody(
            signerId: Self.sender,
            publicKey: Data(hexString: Self.sender)!,
            nonce: Self.transactionNonce,
            receiverId: Self.namedReceiver,
            blockHash: Self.blockHash,
            deposit: 1000,
            actionCount: 1
        )
        // WalletCore's envelope: the TransactionV0 body, the Ed25519 key-type
        // byte, then the 64-byte signature.
        let signedTransaction = body + Data([0x00]) + Data(repeating: 0x11, count: 64)

        let expected = Base58.encodeNoCheck(data: Data(SHA256.hash(data: body)))
        XCTAssertEqual(try NearSignedTransaction.transactionHash(signedTransaction: signedTransaction), expected)
        XCTAssertNotEqual(
            Base58.encodeNoCheck(data: Data(SHA256.hash(data: signedTransaction))),
            expected,
            "the id is the digest that was signed, never the hash of the envelope"
        )
        XCTAssertEqual(try NearSignedTransaction.signerId(signedTransaction: signedTransaction), Self.sender)
    }

    /// The path a co-signed ceremony takes: every device signs the image hash,
    /// and the compiled transaction carries that signature over the body digest.
    func testCoSignedTransactionSignsTheBodyDigestAndCompiles() throws {
        let payload = try makePayload()
        let hash = try XCTUnwrap(NearHelper.getPreSignedImageHash(keysignPayload: payload).first)

        let key = try XCTUnwrap(PrivateKey(data: Data(hexString: Self.senderSeed)!))
        XCTAssertEqual(key.getPublicKeyEd25519().data.hexString, Self.sender)
        let signature = try XCTUnwrap(key.sign(digest: Data(hexString: hash)!, curve: .ed25519))

        // TSS hands Ed25519 back as big-endian R and S halves.
        let response = TssKeysignResponse()
        response.msg = hash
        response.r = Data(signature.prefix(32).reversed()).hexString
        response.s = Data(signature.suffix(32).reversed()).hexString

        let result = try NearHelper.getSignedTransaction(keysignPayload: payload, signatures: [hash: response])

        let body = try Self.borshBody(
            signerId: Self.sender,
            publicKey: Data(hexString: Self.sender)!,
            nonce: Self.transactionNonce,
            receiverId: Self.namedReceiver,
            blockHash: Self.blockHash,
            deposit: 1000,
            actionCount: 1
        )
        XCTAssertEqual(Data(base64Encoded: result.rawTransaction), body + Data([0x00]) + signature)
        XCTAssertEqual(result.transactionHash, Base58.encodeNoCheck(data: Data(SHA256.hash(data: body))))
    }

    // MARK: - SwapKit deposit swaps

    /// Golden `near.json` "Send NEAR to an implicit account": pinned from an
    /// independent Borsh encoding and reproduced by the TypeScript signer.
    private static let goldenImplicitTransferHash = "37c02cebc5c9db73a0a6d7740d5b15a563f1b6b0d43aa513f42574c3d79cbe86"
    private static let goldenImplicitAmount = BigInt("1000000000000000000000")

    private func swapKitDeposit(
        targetAddress: String = Near.implicitReceiver,
        fromAmount: BigInt = Near.goldenImplicitAmount,
        txType: String = "",
        txPayload: Data = Data(),
        memo: String? = nil
    ) -> SwapPayload {
        let near = Coin(asset: CoinMeta.make(chain: .near, ticker: "NEAR", decimals: 24), address: Self.sender, hexPublicKey: Self.sender)
        let eth = Coin(asset: CoinMeta.make(chain: .ethereum, ticker: "ETH", decimals: 18), address: "0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF", hexPublicKey: "")
        return .swapkit(SwapKitSwapPayload(
            fromCoin: near,
            toCoin: eth,
            fromAmount: fromAmount,
            toAmountDecimal: 0.0088,
            txType: txType,
            txPayload: txPayload,
            targetAddress: targetAddress,
            inboundAddress: targetAddress,
            memo: memo,
            subProvider: "NEAR",
            swapID: "3e4605fe-e640-4524-ba6a-a2541101b7f1"
        ))
    }

    private func implicitDepositPayload(swapPayload: SwapPayload) throws -> KeysignPayload {
        try makePayload(
            toAddress: Self.implicitReceiver,
            gasFee: Self.implicitGasFee.description,
            toAmount: Self.goldenImplicitAmount,
            swapPayload: swapPayload
        )
    }

    /// A deposit swap signs the plain transfer to the deposit address, so it
    /// hashes to the cross-platform golden vector for that transfer.
    func testSwapKitDepositSignsTheGoldenPlainTransfer() throws {
        let payload = try implicitDepositPayload(swapPayload: swapKitDeposit())
        XCTAssertEqual(try NearHelper.getPreSignedImageHash(keysignPayload: payload), [Self.goldenImplicitTransferHash])
    }

    func testRejectsASwapKitDepositThatDoesNotNameTheTransfer() throws {
        let cases: [(String, SwapPayload)] = [
            ("deposit address", swapKitDeposit(targetAddress: Self.namedReceiver)),
            ("amount", swapKitDeposit(fromAmount: 1)),
            ("pre-built", swapKitDeposit(txType: "NEAR")),
            ("pre-built", swapKitDeposit(txPayload: Data([1]))),
            ("memo", swapKitDeposit(memo: "deposit-tag"))
        ]
        for (expected, swap) in cases {
            let payload = try implicitDepositPayload(swapPayload: swap)
            XCTAssertThrowsError(try NearHelper.getPreSignedImageHash(keysignPayload: payload)) { error in
                XCTAssertTrue(error.localizedDescription.contains(expected), "\(expected): \(error.localizedDescription)")
            }
        }
    }

    func testRefusesToDeriveAHashFromMalformedSignedBytes() {
        XCTAssertThrowsError(try NearSignedTransaction.transactionHash(signedTransaction: Data(repeating: 0, count: 10)))
        let body = Data(repeating: 0x22, count: 32)
        let notEd25519 = body + Data([0x01]) + Data(repeating: 0, count: 64)
        XCTAssertThrowsError(try NearSignedTransaction.transactionHash(signedTransaction: notEd25519))
    }

    func testSignerAddressIsTheLowercaseHexOfTheEd25519Key() throws {
        // The implicit sender is derived, not accepted: this is the binding
        // between the account a transaction is funded by and the key the
        // ceremony signs with.
        let key = try XCTUnwrap(PublicKey(data: Data(hexString: Self.sender)!, type: .ed25519))
        XCTAssertEqual(CoinType.near.deriveAddressFromPublicKey(publicKey: key), Self.sender)
    }

    // MARK: - NearSpecific wire contract

    func testNearSpecificRoundTripsThroughProtoOnOneofTagSixteen() throws {
        let payload = try makePayload()
        let proto = payload.mapToProtobuff()

        guard case .nearSpecific(let specific)? = proto.blockchainSpecific else {
            return XCTFail("the payload's blockchain_specific is not a near_specific")
        }
        XCTAssertEqual(specific.nonce, Self.transactionNonce)
        XCTAssertEqual(specific.blockHash, Self.blockHash)
        XCTAssertEqual(specific.gasFee, Self.namedGasFee.description)

        // 16 is the oneof tag: field 16, wire type 2 encodes as varint
        // 0x82 0x01. Asserted on the bytes so a future renumbering cannot pass
        // by keeping the Swift case name.
        let encoded = try proto.serializedData()
        XCTAssertNotNil(
            encoded.range(of: Data([0x82, 0x01])),
            "near_specific must be KeysignPayload.blockchain_specific tag 16"
        )

        let decoded = try KeysignPayload(proto: proto)
        guard case let .Near(nonce, blockHash, gasFee, _) = decoded.chainSpecific else {
            return XCTFail("decoded payload is not a NEAR chain specific")
        }
        XCTAssertEqual(nonce, Self.transactionNonce)
        XCTAssertEqual(blockHash, Self.blockHash)
        XCTAssertEqual(gasFee, Self.namedGasFee.description)

        // The local-only storage reserve never travels; a co-signer re-reads it.
        XCTAssertNil(decoded.chainSpecific.nearStorageReserve)
    }

    // MARK: - Native-only rejections

    func testRejectsATokenCoinForTheNativeTransferPath() throws {
        let token = CoinMeta.make(chain: .near, ticker: "USDC", decimals: 24, isNativeToken: false)
        let payload = try makePayload(coin: Coin(asset: token, address: Self.sender, hexPublicKey: Self.sender))

        XCTAssertThrowsError(try NearHelper.getPreSignedInputData(keysignPayload: payload)) { error in
            XCTAssertTrue(error.localizedDescription.contains("native"), error.localizedDescription)
        }
    }

    func testAcceptsTheEmptyMemoAWireDecodedPayloadCarries() throws {
        XCTAssertNoThrow(try NearHelper.getPreSignedImageHash(keysignPayload: try makePayload(memo: "")))
    }

    func testRejectsAMemoOnANativeTransfer() throws {
        let payload = try makePayload(memo: "thanks")

        XCTAssertThrowsError(try NearHelper.getPreSignedInputData(keysignPayload: payload)) { error in
            XCTAssertTrue(error.localizedDescription.contains("memo"), error.localizedDescription)
        }
    }

    func testRejectsRecipientsOutsideTheAccountIdGrammar() throws {
        for recipient in ["WRAP.NEAR", "0x85f17cf997934a597031b2e18a9ab6ebd4b9f6a4", "wrap..near", ""] {
            let payload = try makePayload(toAddress: recipient)
            XCTAssertThrowsError(
                try NearHelper.getPreSignedInputData(keysignPayload: payload),
                "expected \(recipient.isEmpty ? "<empty>" : recipient) to be refused"
            )
        }
    }

    func testRejectsAZeroNonceAndAWrongWidthBlockHash() throws {
        let zeroNonce = try makePayload(nonce: 0)
        XCTAssertThrowsError(try NearHelper.getPreSignedInputData(keysignPayload: zeroNonce))

        let shortHash = try makePayload(blockHash: Data(repeating: 1, count: 31))
        XCTAssertThrowsError(try NearHelper.getPreSignedInputData(keysignPayload: shortHash)) { error in
            XCTAssertTrue(error.localizedDescription.contains("block hash"), error.localizedDescription)
        }
    }

    func testRejectsAGasReservationThatIsNotUnsignedDecimal() throws {
        for gasFee in ["", "1.5", "-1", "0x10"] {
            let payload = try makePayload(gasFee: gasFee)
            XCTAssertThrowsError(
                try NearHelper.getPreSignedInputData(keysignPayload: payload),
                "expected gas fee \(gasFee.isEmpty ? "<empty>" : gasFee) to be refused"
            )
        }
    }

    func testRejectsASenderThatIsNotTheKeysImplicitAccount() throws {
        let mismatched = try makePayload(coin: Coin(
            asset: CoinMeta.make(chain: .near, ticker: "NEAR", decimals: 24),
            address: Self.namedReceiver,
            hexPublicKey: Self.sender
        ))
        XCTAssertThrowsError(try NearHelper.getPreSignedInputData(keysignPayload: mismatched)) { error in
            XCTAssertTrue(error.localizedDescription.contains("implicit"), error.localizedDescription)
        }

        let wrongKey = try makePayload(coin: Coin(
            asset: CoinMeta.make(chain: .near, ticker: "NEAR", decimals: 24),
            address: Self.sender,
            hexPublicKey: Self.implicitReceiver
        ))
        XCTAssertThrowsError(try NearHelper.getPreSignedInputData(keysignPayload: wrongKey)) { error in
            XCTAssertTrue(error.localizedDescription.contains("does not match"), error.localizedDescription)
        }
    }

    // MARK: - Builders

    private func makePayload(
        coin: Coin? = nil,
        toAddress: String = Near.namedReceiver,
        memo: String? = nil,
        nonce: UInt64? = nil,
        blockHash: Data? = nil,
        gasFee: String? = nil,
        toAmount: BigInt = 1000,
        swapPayload: SwapPayload? = nil
    ) throws -> KeysignPayload {
        let native = Coin(
            asset: CoinMeta.make(chain: .near, ticker: "NEAR", decimals: 24),
            address: Self.sender,
            hexPublicKey: Self.sender
        )
        return KeysignPayload(
            coin: coin ?? native,
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: .Near(
                nonce: nonce ?? Self.transactionNonce,
                blockHash: blockHash ?? Self.blockHash,
                gasFee: gasFee ?? Self.namedGasFee.description
            ),
            utxos: [],
            memo: memo,
            swapPayload: swapPayload,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: true,
            signData: nil
        )
    }

    /// nearcore `TransactionV0` and `Action::Transfer`, laid out by hand so the
    /// assertion cannot silently agree with WalletCore's encoder.
    private static func borshBody(
        signerId: String,
        publicKey: Data,
        nonce: UInt64,
        receiverId: String,
        blockHash: Data,
        deposit: UInt64,
        actionCount: UInt32
    ) throws -> Data {
        var body = Data()
        body.append(try borshString(signerId))

        // PublicKey: key-type byte (0 = Ed25519) then the 32-byte key.
        body.append(0x00)
        body.append(publicKey)

        body.append(contentsOf: withUnsafeBytes(of: nonce.littleEndian, Array.init))
        body.append(try borshString(receiverId))
        body.append(blockHash)
        body.append(contentsOf: withUnsafeBytes(of: actionCount.littleEndian, Array.init))

        // Action::Transfer = variant 3, carrying a Borsh u128 deposit.
        body.append(0x03)
        body.append(borshU128(deposit))

        return body
    }

    private static func borshString(_ value: String) throws -> Data {
        let utf8 = Data(value.utf8)
        guard utf8.count <= UInt32.max else {
            throw NearError.malformedResponse("string too long for a Borsh length prefix")
        }
        var data = Data(withUnsafeBytes(of: UInt32(utf8.count).littleEndian, Array.init))
        data.append(utf8)
        return data
    }

    private static func borshU128(_ value: UInt64) -> Data {
        var bytes = Data(withUnsafeBytes(of: value.littleEndian, Array.init))
        bytes.append(Data(repeating: 0, count: 8))
        return bytes
    }
}
