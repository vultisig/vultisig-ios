//
//  CosmosGasEstimatorTests.swift
//  VultisigAppTests
//
//  Initiator-side dynamic gas estimation: the gas_used → padded gas limit →
//  floored fee pipeline, the simulate-tx-bytes construction, and the
//  fail-closed fallback (a simulation/build failure must yield nil so the
//  caller keeps the static gas limit and never blocks signing).
//

@testable import VultisigApp
import WalletCore
import XCTest

final class CosmosGasEstimatorTests: XCTestCase {

    /// Valid compressed secp256k1 pubkey (the generator point G) so WalletCore
    /// can derive the signer info and a real Akash address.
    private let pubKeyHex = "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"

    /// The Akash bech32 address WalletCore derives from `pubKeyHex`. WalletCore
    /// validates the sender/recipient addresses when assembling the tx, so the
    /// simulate body must use a real address rather than a placeholder string.
    private func akashAddress() throws -> String {
        let data = try XCTUnwrap(Data(hexString: pubKeyHex))
        let publicKey = try XCTUnwrap(PublicKey(data: data, type: .secp256k1))
        return AnyAddress(publicKey: publicKey, coin: .akash).description
    }

    // MARK: - Safety multiplier (gas_used → relayed gas limit)

    func testScaledGasLimitRoundsUp() {
        // 95_231 × 1.3 = 123_800.3 → ceil = 123_801.
        XCTAssertEqual(CosmosGasEstimator.scaledGasLimit(gasUsed: 95_231), 123_801)
    }

    func testScaledGasLimitExactValueIsNotInflated() {
        // 100_000 × 1.3 = 130_000 exactly → no extra ceil padding.
        XCTAssertEqual(CosmosGasEstimator.scaledGasLimit(gasUsed: 100_000), 130_000)
    }

    func testScaledGasLimitZero() {
        XCTAssertEqual(CosmosGasEstimator.scaledGasLimit(gasUsed: 0), 0)
    }

    // MARK: - simulate → gas → floored fee (Akash)

    func testSimulatedLimitProducesFlooredAkashFee() {
        // Small tx: gas-price fee stays below the absolute floor, so the
        // 25_000 uakt floor dominates.
        let limit = CosmosGasEstimator.scaledGasLimit(gasUsed: 95_231) // 123_801
        let fee = CosmosFeeFloorConfig.flooredFee(for: .akash, computedFee: 0, gasLimit: limit)
        XCTAssertEqual(fee, 25_000)
    }

    func testLargeSimulatedLimitDrivesFeeAboveFloor() {
        // Large tx: ceil(limit × 0.025 uakt/gas) exceeds the 25_000 floor.
        let limit = CosmosGasEstimator.scaledGasLimit(gasUsed: 5_000_000) // 6_500_000
        // ceil(6_500_000 × 0.025) = 162_500 > 25_000.
        let fee = CosmosFeeFloorConfig.flooredFee(for: .akash, computedFee: 0, gasLimit: limit)
        XCTAssertEqual(fee, 162_500)
    }

    // MARK: - tx_bytes construction (dummy-signature simulate body)

    func testBuildSimulateTxBytesProducesDecodableProtobuf() throws {
        let address = try akashAddress()
        let txBytes = try CosmosGasEstimator.buildSimulateTxBytes(
            chain: .akash,
            hexPublicKey: pubKeyHex,
            fromAddress: address,
            toAddress: address,
            amount: "1000",
            accountNumber: 0,
            sequence: 0
        )
        XCTAssertFalse(txBytes.isEmpty)
        XCTAssertNotNil(Data(base64Encoded: txBytes), "tx_bytes must be valid base64")
    }

    // MARK: - Fail-closed fallback

    func testEstimateReturnsNilOnInvalidPublicKey() async throws {
        // An invalid hex pubkey makes tx-bytes construction throw; the estimator
        // must swallow it and return nil so the caller keeps the static limit.
        let service = try CosmosService.getService(forChain: .akash)
        let result = await CosmosGasEstimator.estimateGasLimit(
            chain: .akash,
            hexPublicKey: "nothex",
            fromAddress: "akash1from",
            toAddress: "akash1to",
            amount: "1000",
            accountNumber: 0,
            sequence: 0,
            service: service
        )
        XCTAssertNil(result)
    }

    func testBuildSimulateTxBytesThrowsOnInvalidPublicKey() {
        XCTAssertThrowsError(
            try CosmosGasEstimator.buildSimulateTxBytes(
                chain: .akash,
                hexPublicKey: "nothex",
                fromAddress: "akash1from",
                toAddress: "akash1to",
                amount: "1000",
                accountNumber: 0,
                sequence: 0
            )
        )
    }

    // MARK: - Simulation scope

    func testShouldSimulateCoversSimulatableCosmosChainsOnly() {
        // Enabled for every Cosmos chain that WalletCore can simulate...
        for chain: Chain in [.akash, .osmosis, .gaiaChain, .kujira, .noble, .dydx, .terra, .terraClassic] {
            XCTAssertTrue(CosmosGasEstimationConfig.shouldSimulate(chain: chain),
                          "\(chain) should be simulatable")
        }
        // ...except QBTC, which signs with ML-DSA via a bespoke builder...
        XCTAssertFalse(CosmosGasEstimationConfig.shouldSimulate(chain: .qbtc))
        // ...and never for non-Cosmos chains.
        XCTAssertFalse(CosmosGasEstimationConfig.shouldSimulate(chain: .ethereum))
        XCTAssertFalse(CosmosGasEstimationConfig.shouldSimulate(chain: .thorChain))
    }
}
