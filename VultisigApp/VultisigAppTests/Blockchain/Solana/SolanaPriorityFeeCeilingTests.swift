//
//  SolanaPriorityFeeCeilingTests.swift
//  VultisigAppTests
//
//  A relayed priority-fee price or compute-unit limit above the ceiling is
//  refused before the signing input is built, on every signer. The ceilings
//  match the Android signer so co-signers agree.
//

@testable import VultisigApp
import BigInt
import WalletCore
import XCTest

final class SolanaPriorityFeeCeilingTests: XCTestCase {

    private static let recentBlockHash = "11111111111111111111111111111111"

    private func makePayload(priorityFee: BigInt, priorityLimit: BigInt) throws -> KeysignPayload {
        let senderKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x11, count: 32)))
        let recipientKey = try XCTUnwrap(PrivateKey(data: Data(repeating: 0x42, count: 32)))
        let senderPublicKey = senderKey.getPublicKeyEd25519()
        let meta = CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "solana",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: AnyAddress(publicKey: senderPublicKey, coin: .solana).description,
            hexPublicKey: senderPublicKey.data.hexString
        )
        return KeysignPayload(
            coin: coin,
            toAddress: AnyAddress(publicKey: recipientKey.getPublicKeyEd25519(), coin: .solana).description,
            toAmount: 1_000_000,
            chainSpecific: .Solana(
                recentBlockHash: Self.recentBlockHash,
                priorityFee: priorityFee,
                priorityLimit: priorityLimit,
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
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

    func testPriceAndLimitAtCeilingsAreAccepted() throws {
        let payload = try makePayload(
            priorityFee: SolanaHelper.maxPriorityFeePrice,
            priorityLimit: SolanaHelper.maxComputeUnitLimit
        )
        let data = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SolanaSigningInput(serializedBytes: data)
        XCTAssertEqual(BigInt(input.priorityFeePrice.price), SolanaHelper.maxPriorityFeePrice)
        XCTAssertEqual(BigInt(input.priorityFeeLimit.limit), SolanaHelper.maxComputeUnitLimit)
    }

    func testTypicalValuesAreAccepted() throws {
        let payload = try makePayload(priorityFee: 1_000_000, priorityLimit: 100_000)
        XCTAssertNoThrow(try SolanaHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testUnsetValuesFallBackToDefaults() throws {
        let payload = try makePayload(priorityFee: 0, priorityLimit: 0)
        let data = try SolanaHelper.getPreSignedInputData(keysignPayload: payload)
        let input = try SolanaSigningInput(serializedBytes: data)
        XCTAssertEqual(input.priorityFeePrice.price, SolanaHelper.defaultPriorityFeePrice)
        XCTAssertEqual(BigInt(input.priorityFeeLimit.limit), SolanaHelper.priorityFeeLimit)
    }

    func testPriceAboveCeilingIsRefused() throws {
        let payload = try makePayload(
            priorityFee: SolanaHelper.maxPriorityFeePrice + 1,
            priorityLimit: 100_000
        )
        XCTAssertThrowsError(try SolanaHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testLimitAboveCeilingIsRefused() throws {
        let payload = try makePayload(
            priorityFee: 1_000_000,
            priorityLimit: SolanaHelper.maxComputeUnitLimit + 1
        )
        XCTAssertThrowsError(try SolanaHelper.getPreSignedInputData(keysignPayload: payload))
    }

    func testPriceBeyondUInt64IsRefusedNotTrapped() throws {
        let payload = try makePayload(priorityFee: BigInt(UInt64.max) + 1, priorityLimit: 100_000)
        XCTAssertThrowsError(try SolanaHelper.getPreSignedInputData(keysignPayload: payload))
    }
}
