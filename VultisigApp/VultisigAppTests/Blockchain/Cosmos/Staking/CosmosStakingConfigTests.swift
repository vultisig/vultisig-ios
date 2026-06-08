//
//  CosmosStakingConfigTests.swift
//  VultisigAppTests
//
//  Pins the per-chain Cosmos staking config table against the cross-platform
//  contract documented in the LUNA / LUNC staking design doc — same chain
//  IDs, gas budgets, fee amounts, valoper prefixes, and unbonding periods
//  the Android + Windows siblings will ship against.
//

@testable import VultisigApp
import XCTest

final class CosmosStakingConfigTests: XCTestCase {

    // MARK: - Allowlist

    func testIsStakingSupportedTrueForTerraAndTerraClassic() {
        XCTAssertTrue(CosmosStakingConfig.isStakingSupported(.terra))
        XCTAssertTrue(CosmosStakingConfig.isStakingSupported(.terraClassic))
    }

    func testIsStakingSupportedFalseForThorchainAndMaya() {
        // THORChain + Maya are Cosmos-SDK chains but use vault-bond models,
        // not x/staking. The allowlist must exclude them so generic staking
        // calls don't accidentally fire at vault bond nodes.
        XCTAssertFalse(CosmosStakingConfig.isStakingSupported(.thorChain))
        XCTAssertFalse(CosmosStakingConfig.isStakingSupported(.mayaChain))
    }

    func testIsStakingSupportedFalseForOtherCosmosChains() {
        // Gaia, Osmosis, etc. could support generic x/staking but we haven't
        // landed the per-chain entries yet. The allowlist must default to
        // "not supported" until each chain gets verified gas / fee values.
        XCTAssertFalse(CosmosStakingConfig.isStakingSupported(.gaiaChain))
        XCTAssertFalse(CosmosStakingConfig.isStakingSupported(.osmosis))
        XCTAssertFalse(CosmosStakingConfig.isStakingSupported(.dydx))
        XCTAssertFalse(CosmosStakingConfig.isStakingSupported(.kujira))
        XCTAssertFalse(CosmosStakingConfig.isStakingSupported(.noble))
    }

    func testEntryThrowsForUnsupportedChain() {
        XCTAssertThrowsError(try CosmosStakingConfig.entry(for: .thorChain)) { error in
            guard case CosmosStakingConfigError.unsupportedChain(let chain) = error else {
                XCTFail("Expected unsupportedChain error, got \(error)")
                return
            }
            XCTAssertEqual(chain, .thorChain)
        }
    }

    // MARK: - Terra (phoenix-1) contract

    func testTerraEntryMatchesContract() throws {
        let entry = try CosmosStakingConfig.entry(for: .terra)
        XCTAssertEqual(entry.chainId, "phoenix-1")
        XCTAssertEqual(entry.bondDenom, "uluna")
        XCTAssertEqual(entry.feeDenom, "uluna")
        XCTAssertEqual(entry.valoperHrp, "terravaloper")
        // Bumped from 300_000 -> 400_000 after observed OoG on redelegate
        // (vultisig-android tx 44A3CE6C…EAF31, gasUsed 300_140 against the
        // prior 300_000 floor). MsgBeginRedelegate writes two validator
        // records; fee scaled proportionally to preserve 0.025 uluna/gas.
        XCTAssertEqual(entry.gasLimit, 400_000)
        XCTAssertEqual(entry.feeAmount, 10_000)
        XCTAssertEqual(entry.unbondingDays, 21)
    }

    // MARK: - TerraClassic (columbus-5) contract

    func testTerraClassicEntryMatchesContract() throws {
        let entry = try CosmosStakingConfig.entry(for: .terraClassic)
        XCTAssertEqual(entry.chainId, "columbus-5")
        XCTAssertEqual(entry.bondDenom, "uluna")
        XCTAssertEqual(entry.feeDenom, "uluna")
        XCTAssertEqual(entry.valoperHrp, "terravaloper")
        // LUNC redelegate hits the dual-record path too. Bumped 1.5M -> 2M
        // for headroom; fee scaled to preserve the ~66.6667 uluna/gas ratio
        // (100M / 1.5M -> 133_333_334 / 2M, rounded up by 1).
        XCTAssertEqual(entry.gasLimit, 2_000_000)
        XCTAssertEqual(entry.feeAmount, 133_333_334)
        XCTAssertEqual(entry.unbondingDays, 21)
    }

    // MARK: - QBTC (qbtc-testnet) contract

    func testIsStakingSupportedTrueForQBTC() {
        XCTAssertTrue(CosmosStakingConfig.isStakingSupported(.qbtc))
    }

    func testQBTCEntryMatchesContract() throws {
        let entry = try CosmosStakingConfig.entry(for: .qbtc)
        XCTAssertEqual(entry.chainId, "qbtc-testnet")
        // `qbtc` is lowercase and NOT a micro-denom (8 decimals) — verified on
        // the live qbtc-testnet LCD `staking/params.bond_denom`.
        XCTAssertEqual(entry.bondDenom, "qbtc")
        XCTAssertEqual(entry.feeDenom, "qbtc")
        XCTAssertEqual(entry.valoperHrp, "qbtcvaloper")
        // gasLimit 400_000 matches Terra's post-OoG floor (live MsgDelegate
        // simulate burned 278_759; redelegate is heavier). feeAmount 800 is the
        // qbtc-testnet `min_tx_fee` floor; since `min_gas_price` is 0 the higher
        // gas budget does not raise the fee.
        XCTAssertEqual(entry.gasLimit, 400_000)
        XCTAssertEqual(entry.feeAmount, 800)
        // Live LCD `unbonding_time` = 1814400s = 21 days.
        XCTAssertEqual(entry.unbondingDays, 21)
    }

    func testTerraClassicGasIsFiveTimesPhoenix() throws {
        // Empirical fact pinned by agent-app on-chain measurements — the
        // columbus-5 stability-tax / value-per-byte module bills extra gas
        // and the 5x multiplier is the smallest budget that lands txs.
        // Smaller budgets OoG.
        let phoenix = try CosmosStakingConfig.gasLimit(for: .terra)
        let classic = try CosmosStakingConfig.gasLimit(for: .terraClassic)
        XCTAssertEqual(classic, phoenix * 5)
    }

    // MARK: - Per-field accessor parity

    func testFieldAccessorsAgreeWithEntry() throws {
        for chain: Chain in [.terra, .terraClassic] {
            let entry = try CosmosStakingConfig.entry(for: chain)
            XCTAssertEqual(try CosmosStakingConfig.chainId(for: chain), entry.chainId)
            XCTAssertEqual(try CosmosStakingConfig.bondDenom(for: chain), entry.bondDenom)
            XCTAssertEqual(try CosmosStakingConfig.feeDenom(for: chain), entry.feeDenom)
            XCTAssertEqual(try CosmosStakingConfig.valoperHrp(for: chain), entry.valoperHrp)
            XCTAssertEqual(try CosmosStakingConfig.gasLimit(for: chain), entry.gasLimit)
            XCTAssertEqual(try CosmosStakingConfig.feeAmount(for: chain), entry.feeAmount)
            XCTAssertEqual(try CosmosStakingConfig.unbondingDays(for: chain), entry.unbondingDays)
        }
    }
}
