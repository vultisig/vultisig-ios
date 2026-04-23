//
//  TonSendTransactionTests.swift
//  VultisigApp
//
//  Covers TonConnect sendTransaction multi-message assembly and validation
//  as well as the single-transfer regression path.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class TonSendTransactionTests: XCTestCase {
    private let hexPublicKey = "6c756400bac0b153b421df6e199302537d12f7d4a53447004485700a958e7571"
    private let fromAddress = "UQCc9iCgP_b5RMJcFE5XD8zStfjtNHLhDWfUqC5m1SjSer95"
    private let destA = "UQDmLe6ticcY_uLZsfurdYONshNuCn8IS81KcJ8p6M6ISMcB"
    private let destB = "EQCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDkpgJ"
    private let destC = "Ef8t6cZkqFuHjJ_a_ydEK_tu3LHWRA4JZXRyewLY4j8FZ6B5"

    private func makeCoin() -> Coin {
        let meta = CoinMeta(
            chain: .ton,
            ticker: "TON",
            logo: "ton",
            decimals: 9,
            priceProviderId: "the-open-network",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: fromAddress, hexPublicKey: hexPublicKey)
    }

    private func makePayload(
        toAddress: String,
        toAmount: BigInt,
        chainSpecific: BlockChainSpecific,
        signData: SignData?
    ) -> KeysignPayload {
        KeysignPayload(
            coin: makeCoin(),
            toAddress: toAddress,
            toAmount: toAmount,
            chainSpecific: chainSpecific,
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
            skipBroadcast: false,
            signData: signData
        )
    }

    private func tonSpecific(bounceable: Bool = false) -> BlockChainSpecific {
        .Ton(
            sequenceNumber: 0,
            expireAt: 1_753_579_977,
            bounceable: bounceable,
            sendMaxAmount: false
        )
    }

    // MARK: - Regression: native single transfer

    func testSingleNativeTransferStillProducesExpectedHash() throws {
        let payload = makePayload(
            toAddress: destA,
            toAmount: 50_000_000,
            chainSpecific: tonSpecific(bounceable: false),
            signData: nil
        )

        let hashes = try TonHelper.getPreSignedImageHash(keysignPayload: payload)

        XCTAssertEqual(hashes.count, 1)
        XCTAssertEqual(hashes[0], "aefa16a3825645bcfcf305be112bc2da400d213cb8c20d87e0e43d4eb214a5f8")
    }

    // MARK: - TonConnect: multi-message assembly

    func testTonConnectBuildsOneTransferPerMessage() throws {
        let messages = [
            TonMessage(to: destA, amount: "10000000"),
            TonMessage(to: destB, amount: "20000000"),
            TonMessage(to: destC, amount: "30000000")
        ]
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(bounceable: true),
            signData: .signTon(SignTon(tonMessages: messages))
        )

        let inputData = try TonHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try TheOpenNetworkSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.messages.count, 3)
        XCTAssertEqual(input.messages[0].amount, Data(hexString: BigInt(10_000_000).toEvenLengthHexString()))
        XCTAssertEqual(input.messages[1].amount, Data(hexString: BigInt(20_000_000).toEvenLengthHexString()))
        XCTAssertEqual(input.messages[2].amount, Data(hexString: BigInt(30_000_000).toEvenLengthHexString()))

        let expectedMode = UInt32(
            TheOpenNetworkSendMode.payFeesSeparately.rawValue |
            TheOpenNetworkSendMode.ignoreActionPhaseErrors.rawValue
        )
        for transfer in input.messages {
            XCTAssertEqual(transfer.mode, expectedMode)
        }

        // Per-address bounce intent derived from friendly-address prefix,
        // not the vault-wide flag: UQ → non-bounceable, EQ / Ef → bounceable.
        XCTAssertFalse(input.messages[0].bounceable, "UQ destination should be non-bounceable")
        XCTAssertTrue(input.messages[1].bounceable, "EQ destination should be bounceable")
        XCTAssertTrue(input.messages[2].bounceable, "Ef destination should be bounceable")
    }

    func testTonConnectBounceableIsDerivedPerAddress() throws {
        let messages = [
            TonMessage(to: destA, amount: "1000000"),
            TonMessage(to: destB, amount: "1000000"),
            TonMessage(to: destC, amount: "1000000")
        ]
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(bounceable: false),
            signData: .signTon(SignTon(tonMessages: messages))
        )

        let inputData = try TonHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try TheOpenNetworkSigningInput(serializedBytes: inputData)

        XCTAssertFalse(input.messages[0].bounceable)
        XCTAssertTrue(input.messages[1].bounceable)
        XCTAssertTrue(input.messages[2].bounceable)
    }

    func testTonConnectThreadsStateInitAndCustomPayload() throws {
        let stateInit = "te6cckEBAQEAAgAAAEysuc0="
        let customPayload = "te6cckEBAQEAAgAAABGw7yzH"
        let messages = [
            TonMessage(to: destA, amount: "10000000", payload: customPayload, stateInit: stateInit),
            TonMessage(to: destB, amount: "20000000")
        ]
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(bounceable: false),
            signData: .signTon(SignTon(tonMessages: messages))
        )

        let inputData = try TonHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try TheOpenNetworkSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.messages.count, 2)
        XCTAssertEqual(input.messages[0].stateInit, stateInit)
        XCTAssertEqual(input.messages[0].customPayload, customPayload)
        XCTAssertEqual(input.messages[1].stateInit, "")
        XCTAssertEqual(input.messages[1].customPayload, "")
    }

    func testTonConnectAcceptsUpToFourMessages() throws {
        let messages = (0..<4).map { index in
            TonMessage(to: destA, amount: String(1_000_000 + index))
        }
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(),
            signData: .signTon(SignTon(tonMessages: messages))
        )

        let inputData = try TonHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try TheOpenNetworkSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.messages.count, 4)
    }

    func testTonConnectPassesSequenceAndExpiryThrough() throws {
        let specific = BlockChainSpecific.Ton(
            sequenceNumber: 42,
            expireAt: 1_800_000_000,
            bounceable: false,
            sendMaxAmount: false
        )
        let messages = [TonMessage(to: destA, amount: "1000000")]
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: specific,
            signData: .signTon(SignTon(tonMessages: messages))
        )

        let inputData = try TonHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try TheOpenNetworkSigningInput(serializedBytes: inputData)

        XCTAssertEqual(input.sequenceNumber, 42)
        XCTAssertEqual(input.expireAt, 1_800_000_000)
    }

    // MARK: - Validation failures

    func testTonConnectRejectsEmptyMessages() {
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(),
            signData: .signTon(SignTon(tonMessages: []))
        )

        XCTAssertThrowsError(try TonHelper.getPreSignedInputData(keysignPayload: payload)) { error in
            XCTAssertTrue(String(describing: error).contains("tonMessages must not be empty"))
        }
    }

    func testTonConnectRejectsMoreThanFourMessages() {
        let messages = (0..<5).map { _ in TonMessage(to: destA, amount: "1000000") }
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(),
            signData: .signTon(SignTon(tonMessages: messages))
        )

        XCTAssertThrowsError(try TonHelper.getPreSignedInputData(keysignPayload: payload)) { error in
            XCTAssertTrue(String(describing: error).contains("at most"))
        }
    }

    func testTonConnectRejectsNonPositiveAmount() {
        let messages = [TonMessage(to: destA, amount: "0")]
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(),
            signData: .signTon(SignTon(tonMessages: messages))
        )

        XCTAssertThrowsError(try TonHelper.getPreSignedInputData(keysignPayload: payload)) { error in
            XCTAssertTrue(String(describing: error).contains("invalid TonConnect amount"))
        }
    }

    func testTonConnectRejectsInvalidDestination() {
        let messages = [TonMessage(to: "not-a-ton-address", amount: "1000000")]
        let payload = makePayload(
            toAddress: destA,
            toAmount: 0,
            chainSpecific: tonSpecific(),
            signData: .signTon(SignTon(tonMessages: messages))
        )

        XCTAssertThrowsError(try TonHelper.getPreSignedInputData(keysignPayload: payload)) { error in
            XCTAssertTrue(String(describing: error).contains("invalid TonConnect destination"))
        }
    }
}
