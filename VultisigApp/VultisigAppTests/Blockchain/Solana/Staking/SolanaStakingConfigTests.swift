//
//  SolanaStakingConfigTests.swift
//  VultisigAppTests
//
//  Pins the Solana staking constants — Stake program id, account size, the
//  staker memcmp offset, and the documented min-delegation floor substitute.
//

@testable import VultisigApp
import XCTest

final class SolanaStakingConfigTests: XCTestCase {

    func testStakeProgramConstants() {
        XCTAssertEqual(SolanaStakingConfig.stakeProgramId, "Stake11111111111111111111111111111111111111")
        XCTAssertEqual(SolanaStakingConfig.stakeStateSize, 200)
        XCTAssertEqual(SolanaStakingConfig.stakerMemcmpOffset, 12)
        XCTAssertEqual(SolanaStakingConfig.voterMemcmpOffset, 124)
    }

    func testDelegationFloorAndLamports() {
        // 1 SOL substitute for the proxy-blocked min-delegation RPC.
        XCTAssertEqual(SolanaStakingConfig.minDelegationFloorLamports, 1_000_000_000)
        XCTAssertEqual(SolanaStakingConfig.lamportsPerSol, 1_000_000_000)
    }

    func testEpochSentinelIsUInt64Max() {
        XCTAssertEqual(SolanaStakingConfig.epochSentinel, UInt64.max)
        XCTAssertEqual(SolanaStakingConfig.slotsPerEpoch, 432_000)
    }

    func testStakingSupportedOnlyForSolana() {
        XCTAssertTrue(SolanaStakingConfig.isStakingSupported(.solana))
        XCTAssertTrue(Chain.solana.isSolanaStakingChain)
        XCTAssertFalse(SolanaStakingConfig.isStakingSupported(.ethereum))
        XCTAssertFalse(Chain.ethereum.isSolanaStakingChain)
        XCTAssertFalse(SolanaStakingConfig.isStakingSupported(.terra))
    }
}
