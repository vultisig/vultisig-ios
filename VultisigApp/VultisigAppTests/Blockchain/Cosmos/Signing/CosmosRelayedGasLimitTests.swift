//
//  CosmosRelayedGasLimitTests.swift
//  VultisigAppTests
//
//  The relayed dynamic gas-limit contract (proto `CosmosSpecific.gas_limit`).
//  The read/honor side is ALWAYS-ON and hash-safe: when an initiator relays a
//  `gasLimit`, `CosmosHelperStruct.defaultFee` must build the signing input with
//  exactly that gas value on every co-signing device; when none is relayed it
//  must fall back to the static per-chain limit. These tests also pin the
//  proto round-trip so the relayed value survives marshalling between peers.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class CosmosRelayedGasLimitTests: XCTestCase {

    // MARK: - Builders

    private func makeCoin(chain: Chain) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: "AKT",
            logo: "akt",
            decimals: 6,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        // Valid 33-byte compressed-pubkey hex so `Data(hexString:)` succeeds.
        let hexPublicKey = "02" + String(repeating: "0", count: 64)
        return Coin(asset: meta, address: "akash1from", hexPublicKey: hexPublicKey)
    }

    private func makePayload(coin: Coin, gasLimit: UInt64?) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "akash1to",
            toAmount: 1_000,
            chainSpecific: .Cosmos(
                accountNumber: 7,
                sequence: 3,
                gas: 7_500,
                transactionType: 0,
                ibcDenomTrace: nil,
                gasLimit: gasLimit
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
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
            skipBroadcast: false,
            signData: nil
        )
    }

    private func signingInput(for payload: KeysignPayload) throws -> CosmosSigningInput {
        let helper = CosmosHelperStruct(config: try CosmosHelperConfig.getConfig(forChain: .akash))
        let inputData = try helper.getPreSignedInputData(keysignPayload: payload)
        return try CosmosSigningInput(serializedBytes: inputData)
    }

    // MARK: - defaultFee honors the relayed limit (hash-safe contract)

    func testRelayedGasLimitIsHonoredInSigningInput() throws {
        let coin = makeCoin(chain: .akash)
        let input = try signingInput(for: makePayload(coin: coin, gasLimit: 123_456))
        XCTAssertEqual(input.fee.gas, 123_456, "Relayed gas_limit must drive the signed fee.gas")
    }

    func testAbsentGasLimitFallsBackToStaticLimit() throws {
        let coin = makeCoin(chain: .akash)
        let input = try signingInput(for: makePayload(coin: coin, gasLimit: nil))
        // Akash static gas limit from CosmosHelperConfig.
        XCTAssertEqual(input.fee.gas, 200_000, "Absent gas_limit must use the static per-chain limit")
    }

    // MARK: - Bespoke helpers honor the relayed limit too (Terra)

    private func terraSigningInput(for payload: KeysignPayload) throws -> CosmosSigningInput {
        let inputData = try TerraHelperStruct.getPreSignedInputData(keysignPayload: payload, chain: .terra)
        return try CosmosSigningInput(serializedBytes: inputData)
    }

    func testTerraRelayedGasLimitIsHonoredInSigningInput() throws {
        let coin = makeCoin(chain: .terra)
        let input = try terraSigningInput(for: makePayload(coin: coin, gasLimit: 123_456))
        XCTAssertEqual(input.fee.gas, 123_456, "Relayed gas_limit must drive the signed fee.gas on Terra")
    }

    func testTerraAbsentGasLimitFallsBackToStaticLimit() throws {
        let coin = makeCoin(chain: .terra)
        let input = try terraSigningInput(for: makePayload(coin: coin, gasLimit: nil))
        XCTAssertEqual(input.fee.gas, TerraHelperStruct.GasLimit,
                       "Absent gas_limit must use Terra's static per-chain limit")
    }

    // MARK: - Bespoke helpers honor the relayed limit too (QBTC / ML-DSA)

    /// QBTC signs with a bespoke ML-DSA builder that manually encodes AuthInfo,
    /// where the static gas limit is `QBTCHelper.create().gasLimit` (300_000).
    /// The `gas_limit` varint is part of the SignDoc both devices hash, so the
    /// pre-image hash is a faithful witness: a relayed limit must change the
    /// hash, and an absent one must reproduce the static-limit hash exactly.
    private func qbtcCoin() -> Coin {
        let meta = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        let hexPublicKey = "02" + String(repeating: "0", count: 64)
        return Coin(asset: meta, address: "qbtc1from", hexPublicKey: hexPublicKey)
    }

    private func qbtcSendPayload(gasLimit: UInt64?) -> KeysignPayload {
        // A native MsgSend (signData == nil, transactionType == 0) routes through
        // `QBTCHelper.buildTxComponents` → `buildAuthInfo`, exercising the
        // relayed-vs-static gas-limit decision.
        KeysignPayload(
            coin: qbtcCoin(),
            toAddress: "qbtc1to",
            toAmount: 1_000,
            chainSpecific: .Cosmos(
                accountNumber: 7,
                sequence: 3,
                gas: 800,
                transactionType: 0,
                ibcDenomTrace: nil,
                gasLimit: gasLimit
            ),
            utxos: [],
            memo: nil,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.GG20.toString(),
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

    func testQBTCAbsentGasLimitReproducesStaticLimitHash() throws {
        let helper = QBTCHelper.create()
        let absentHash = try helper.getPreSignedImageHash(keysignPayload: qbtcSendPayload(gasLimit: nil))
        let staticHash = try helper.getPreSignedImageHash(keysignPayload: qbtcSendPayload(gasLimit: helper.gasLimit))
        XCTAssertEqual(
            absentHash, staticHash,
            "Absent gas_limit must fall back to QBTC's static limit (identical SignDoc)"
        )
    }

    func testQBTCRelayedGasLimitChangesSignDocHash() throws {
        let helper = QBTCHelper.create()
        let absentHash = try helper.getPreSignedImageHash(keysignPayload: qbtcSendPayload(gasLimit: nil))
        let relayedHash = try helper.getPreSignedImageHash(keysignPayload: qbtcSendPayload(gasLimit: 999_000))
        XCTAssertNotEqual(
            absentHash, relayedHash,
            "A relayed gas_limit must be honored, changing the signed SignDoc bytes"
        )
    }

    // MARK: - Proto round-trip

    func testGasLimitRoundTripsThroughProto() throws {
        let original: BlockChainSpecific = .Cosmos(
            accountNumber: 7,
            sequence: 3,
            gas: 7_500,
            transactionType: 0,
            ibcDenomTrace: nil,
            gasLimit: 123_456
        )
        let proto = original.mapToProtobuff()
        guard case .cosmosSpecific(let value) = proto else {
            return XCTFail("expected cosmosSpecific oneof")
        }
        XCTAssertTrue(value.hasGasLimit)
        XCTAssertEqual(value.gasLimit, 123_456)

        let roundTripped = try BlockChainSpecific(proto: proto)
        guard case .Cosmos(_, _, _, _, _, let gasLimit) = roundTripped else {
            return XCTFail("expected Cosmos case")
        }
        XCTAssertEqual(gasLimit, 123_456)
    }

    func testNilGasLimitRoundTripsAsUnset() throws {
        let original: BlockChainSpecific = .Cosmos(
            accountNumber: 7,
            sequence: 3,
            gas: 7_500,
            transactionType: 0,
            ibcDenomTrace: nil,
            gasLimit: nil
        )
        let proto = original.mapToProtobuff()
        guard case .cosmosSpecific(let value) = proto else {
            return XCTFail("expected cosmosSpecific oneof")
        }
        XCTAssertFalse(value.hasGasLimit, "nil gas_limit must leave the proto field unset")

        let roundTripped = try BlockChainSpecific(proto: proto)
        guard case .Cosmos(_, _, _, _, _, let gasLimit) = roundTripped else {
            return XCTFail("expected Cosmos case")
        }
        XCTAssertNil(gasLimit)
    }
}
