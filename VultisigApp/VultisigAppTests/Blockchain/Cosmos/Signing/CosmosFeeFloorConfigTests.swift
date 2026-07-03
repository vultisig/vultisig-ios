//
//  CosmosFeeFloorConfigTests.swift
//  VultisigAppTests
//
//  Pins the per-chain Cosmos fee-floor table. The send path
//  (BlockChainService), the feeDefault fallback (Coin) and the dApp-injected
//  signing path (CosmosSignDataBuilder / KeysignPayload) all route their fee
//  through `flooredFee` / `requiredFloor` / `meetsFloor`, so flooring here is
//  what guarantees the displayed and signed Akash fee can never fall below the
//  live network minimum.
//

@testable import VultisigApp
import XCTest

final class CosmosFeeFloorConfigTests: XCTestCase {

    // MARK: - Akash floor (display + signed share this function)

    func testAkashFloorRaisesSubFloorSendFeeToFloor() {
        // The old hard-coded 3000 uakt send fee was below Akash's minimum.
        XCTAssertEqual(
            CosmosFeeFloorConfig.flooredFee(for: .akash, computedFee: 3000, gasLimit: 200_000),
            25_000
        )
    }

    func testAkashFloorRaisesKeplrStakingFeeToFloor() {
        // Mirrors the vultisig-windows injectKeplrFeeIfMissing case: ~300k gas
        // at 0.025 uakt/gas computes only 7_500 uakt and must be floored.
        XCTAssertEqual(
            CosmosFeeFloorConfig.flooredFee(for: .akash, computedFee: 7_500, gasLimit: 300_000),
            25_000
        )
    }

    func testAkashFeeAlreadyAboveFloorPassesThrough() {
        XCTAssertEqual(
            CosmosFeeFloorConfig.flooredFee(for: .akash, computedFee: 30_000, gasLimit: 200_000),
            30_000
        )
    }

    func testAkashGasPriceArmDominatesForHugeGasLimit() {
        // ceil(2_000_000 × 0.025) = 50_000 > the flat 25_000 floor.
        XCTAssertEqual(
            CosmosFeeFloorConfig.flooredFee(for: .akash, computedFee: 0, gasLimit: 2_000_000),
            50_000
        )
    }

    func testAkashGasPriceArmRoundsUp() {
        // ceil(200_001 × 0.025) = ceil(5000.025) = 5001, still below the floor.
        XCTAssertEqual(
            CosmosFeeFloorConfig.requiredFloor(for: .akash, gasLimit: 200_001),
            25_000
        )
        // A gas limit large enough that the gas-price arm beats the flat floor
        // exercises the ceil rounding on the dominant arm.
        XCTAssertEqual(
            CosmosFeeFloorConfig.requiredFloor(for: .akash, gasLimit: 1_000_001),
            25_001
        )
    }

    func testMinFeeFloorAkash() {
        XCTAssertEqual(CosmosFeeFloorConfig.minFeeFloor(for: .akash), 25_000)
    }

    // MARK: - Osmosis (behavior-preserving fold of the old inline literal)

    func testOsmosisFloorPreservesInlineLiteral() {
        // Osmosis previously used a flat inline 25_000. minGasPrice 0 keeps the
        // gas-price arm inert, so the flat floor still wins.
        XCTAssertEqual(
            CosmosFeeFloorConfig.flooredFee(for: .osmosis, computedFee: 7_500, gasLimit: 300_000),
            25_000
        )
        XCTAssertEqual(CosmosFeeFloorConfig.minFeeFloor(for: .osmosis), 25_000)
    }

    // MARK: - Non-floored chains pass through unchanged (regression)

    func testNonFlooredCosmosChainsPassThrough() {
        let chains: [Chain] = [.gaiaChain, .kujira, .noble, .dydx, .terra, .terraClassic, .qbtc]
        for chain in chains {
            XCTAssertEqual(
                CosmosFeeFloorConfig.flooredFee(for: chain, computedFee: 7_500, gasLimit: 200_000),
                7_500,
                "Expected \(chain) to be unaffected by the fee floor"
            )
            XCTAssertEqual(CosmosFeeFloorConfig.minFeeFloor(for: chain), 0)
            XCTAssertEqual(CosmosFeeFloorConfig.requiredFloor(for: chain, gasLimit: 200_000), 0)
        }
    }

    // MARK: - meetsFloor (used to validate peer-shared signDirect fees)

    func testMeetsFloorAkash() {
        XCTAssertFalse(CosmosFeeFloorConfig.meetsFloor(for: .akash, fee: 24_999, gasLimit: 200_000))
        XCTAssertTrue(CosmosFeeFloorConfig.meetsFloor(for: .akash, fee: 25_000, gasLimit: 200_000))
        XCTAssertTrue(CosmosFeeFloorConfig.meetsFloor(for: .akash, fee: 100_000, gasLimit: 200_000))
    }

    func testMeetsFloorAlwaysTrueForNonFlooredChain() {
        // A non-floored chain has no minimum, so even a zero fee "meets" it
        // (this is what prevents the signDirect validation from rejecting
        // legitimate zero-fee chains like THORChain/Rujira).
        XCTAssertTrue(CosmosFeeFloorConfig.meetsFloor(for: .gaiaChain, fee: 0, gasLimit: 200_000))
        XCTAssertTrue(CosmosFeeFloorConfig.meetsFloor(for: .thorChain, fee: 0, gasLimit: 200_000))
    }
}
