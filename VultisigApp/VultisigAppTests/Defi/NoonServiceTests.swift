//
//  NoonServiceTests.swift
//  VultisigAppTests
//
//  Golden calldata vectors for the Noon ERC-7540 vault. Each encoder is
//  byte-equal to the merged SDK reference (`noon.test.ts`): same selectors,
//  same head-only static-arg layout. The vault is a direct EOA call target —
//  there is no MSCA `execute()` wrapper (that is a Circle-only concern).
//

import BigInt
import XCTest
@testable import VultisigApp

final class NoonServiceTests: XCTestCase {

    private let sampleUser = "0x8b937c5395d95a8c8948c7c5b844e1541798d90c"
    private let owner = "0xecfe16242e796c853aa0132c06651626d54ee1e6"

    private func hex(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Calldata golden vectors

    func testDepositMatchesReferenceVector() throws {
        let data = try NoonService.shared.encodeDeposit(assets: BigInt(100_000_000), receiver: sampleUser)
        XCTAssertEqual(
            hex(data),
            "0x6e553f650000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c"
        )
    }

    func testRequestRedeemMatchesReferenceVector() throws {
        let data = try NoonService.shared.encodeRequestRedeem(shares: BigInt(98_333_202), receiver: owner, owner: owner)
        XCTAssertEqual(
            hex(data),
            "0x7d41c86e0000000000000000000000000000000000000000000000000000000005dc7212000000000000000000000000ecfe16242e796c853aa0132c06651626d54ee1e6000000000000000000000000ecfe16242e796c853aa0132c06651626d54ee1e6"
        )
    }

    func testWithdrawMatchesReferenceVector() throws {
        let data = try NoonService.shared.encodeWithdraw(assets: BigInt(97_617_839), receiver: sampleUser, owner: sampleUser)
        XCTAssertEqual(
            hex(data),
            "0xb460af940000000000000000000000000000000000000000000000000000000005d187af0000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c0000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c"
        )
    }

    func testUsdcApproveTargetsVaultAsSpender() throws {
        let data = try NoonService.shared.encodeUsdcApprove(amount: BigInt(100_000_000))
        XCTAssertEqual(
            hex(data),
            "0x095ea7b3000000000000000000000000a73424f1ac94b3ef0d0c9af4f2967c87d4af25d90000000000000000000000000000000000000000000000000000000005f5e100"
        )
    }

    func testInvalidAddressThrows() {
        XCTAssertThrowsError(try NoonService.shared.encodeDeposit(assets: BigInt(100_000_000), receiver: "not-an-address"))
    }

    // MARK: - Minimum guards

    func testDepositBelowMinimumThrows() {
        let minimum = BigInt(NoonConstants.minDepositAssets)!
        XCTAssertThrowsError(try NoonService.shared.assertDepositMinimum(assets: BigInt(100_000), minimum: minimum)) { error in
            XCTAssertEqual((error as? NoonServiceError)?.errorDescription, "Noon deposit assets must be at least 100000000")
        }
    }

    func testRedeemBelowMinimumThrows() {
        let minimum = BigInt(NoonConstants.minRedeemShares)!
        XCTAssertThrowsError(try NoonService.shared.assertRedeemMinimum(shares: BigInt(100_000), minimum: minimum)) { error in
            XCTAssertEqual((error as? NoonServiceError)?.errorDescription, "Noon redeem shares must be at least 95000000")
        }
    }

    func testDepositAtMinimumDoesNotThrow() {
        let minimum = BigInt(NoonConstants.minDepositAssets)!
        XCTAssertNoThrow(try NoonService.shared.assertDepositMinimum(assets: minimum, minimum: minimum))
    }
}

// MARK: - Read decoding

final class NoonReadServiceTests: XCTestCase {

    func testDecodeUIntFromHexWord() throws {
        let raw = "0x0000000000000000000000000000000000000000000000000000000005f5e100"
        XCTAssertEqual(try NoonReadService.decodeUInt(raw), BigInt(100_000_000))
    }

    func testDecodeUIntFailsClosedOnEmptyPayload() {
        // A reverted / empty `eth_call` must surface as an error, never decode to 0.
        XCTAssertThrowsError(try NoonReadService.decodeUInt("0x"))
    }

    func testDecodeUIntFailsClosedOnGarbagePayload() {
        XCTAssertThrowsError(try NoonReadService.decodeUInt("0xZZZZ"))
    }

    func testAbiWordsFailsClosedOnMisalignedPayload() {
        // 1 byte (not a whole 32-byte word) must throw, not yield [].
        XCTAssertThrowsError(try NoonReadService.abiWords("0x01"))
    }

    func testDecodeStateReadsMaxWithdrawRedeemSharesAndPending() throws {
        // 10-word tuple: maxMint, maxWithdraw, depositAssets, redeemShares,
        // depositPrice, mintPrice, redeemPrice, withdrawPrice,
        // pendingDepositRequest, pendingRedeemRequest.
        let words = [
            "0", "5f5e100", "0", "5dc7212", "0", "0", "0", "0", "0", "16e3600"
        ]
        let raw = "0x" + words.map { String($0).paddingLeft(toLength: 64, withPad: "0") }.joined()

        let state = try NoonReadService.decodeState(raw)
        XCTAssertEqual(state.maxWithdraw, BigInt(100_000_000))
        XCTAssertEqual(state.redeemShares, BigInt(98_333_202))
        XCTAssertEqual(state.pendingRedeemRequest, BigInt(24_000_000))
    }

    func testDecodeStateRejectsShortResponse() {
        XCTAssertThrowsError(try NoonReadService.decodeState("0x"))
    }

    func testRedemptionStateClaimableWhenAssetsAvailable() {
        let state = NoonRedemptionState.derive(claimableAssets: BigInt(1), claimableRedeemShares: .zero, pendingRedeemShares: BigInt(5))
        XCTAssertEqual(state, .claimable)
    }

    func testRedemptionStatePendingWhenOnlyPendingShares() {
        let state = NoonRedemptionState.derive(claimableAssets: .zero, claimableRedeemShares: .zero, pendingRedeemShares: BigInt(5))
        XCTAssertEqual(state, .pending)
    }

    func testRedemptionStateNoneWhenEmpty() {
        let state = NoonRedemptionState.derive(claimableAssets: .zero, claimableRedeemShares: .zero, pendingRedeemShares: .zero)
        XCTAssertEqual(state, .none)
    }
}

// MARK: - API parsing

final class NoonApiServiceTests: XCTestCase {

    func testApyReadsSevenDayNetUnderIr() throws {
        let response = NoonVaultsResponse(vaults: [
            NoonVaultEntry(
                loanAddress: NoonConstants.loanAddress,
                ir: NoonInterestRate(sevenDay: NoonRateWindow(net: NoonRateValue(apyPct: "11.9368")))
            )
        ])
        let apy = try NoonApiService.apy(from: response, loanAddress: NoonConstants.loanAddress)
        XCTAssertEqual(apy, Decimal(string: "11.9368"))
    }

    func testApyDecodesProductionShapeFromJson() throws {
        // Mirrors the live `back.noon.capital/api/v1/vaults` payload: apy_pct
        // lives under `ir.7d.net`, NOT a top-level `7d` key.
        let json = """
        {
          "vaults": [
            {
              "loan_address": "\(NoonConstants.loanAddress)",
              "current": { "net": { "apy_pct": "13.5808" } },
              "ir": { "7d": { "net": { "apy_pct": "11.9368" } }, "30d": { "net": { "apy_pct": "12.0" } } }
            }
          ]
        }
        """
        let response = try JSONDecoder().decode(NoonVaultsResponse.self, from: Data(json.utf8))
        let apy = try NoonApiService.apy(from: response, loanAddress: NoonConstants.loanAddress)
        XCTAssertEqual(apy, Decimal(string: "11.9368"))
    }

    func testApyThrowsWhenLoanMissing() {
        let response = NoonVaultsResponse(vaults: [])
        XCTAssertThrowsError(try NoonApiService.apy(from: response, loanAddress: NoonConstants.loanAddress))
    }

    func testTvlDecodesLoanComputed() throws {
        let json = """
        { "loan_computed": { "tvl": 151868815257.0, "tvl_in_usd": 151009.73819945095 } }
        """
        let response = try JSONDecoder().decode(NoonLoanResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.loanComputed.tvlInUsd, 151009.73819945095)
    }

    // MARK: - Product minimums (the authoritative deposit/redeem floor)

    func testMinimumsReadFromOnChainLoanTerms() throws {
        // Mirrors the live loan payload: the product floors live at
        // on_chain_loan.loan.loan.minDeposit / .minRedeem — NOT MIN_AMOUNT_WEI.
        let json = """
        {
          "loan_computed": { "tvl_in_usd": 151009.0 },
          "on_chain_loan": { "loan": { "loan": { "minDeposit": 100000000, "minRedeem": 95000000 } } }
        }
        """
        let response = try JSONDecoder().decode(NoonLoanResponse.self, from: Data(json.utf8))
        // A deliberately wrong fallback proves the parsed values win.
        let minimums = NoonApiService.minimums(
            from: response,
            fallback: NoonMinimums(minDeposit: BigInt(1), minRedeem: BigInt(1))
        )
        XCTAssertEqual(minimums.minDeposit, BigInt(100_000_000), "deposit floor must be 100 USDC")
        XCTAssertEqual(minimums.minRedeem, BigInt(95_000_000), "redeem floor must be 95 naccUSDC")
    }

    func testMinimumsParseStringEncodedValues() throws {
        // The API may serialize the base-unit integers as strings.
        let json = """
        {
          "loan_computed": { "tvl_in_usd": 1.0 },
          "on_chain_loan": { "loan": { "loan": { "minDeposit": "100000000", "minRedeem": "95000000" } } }
        }
        """
        let response = try JSONDecoder().decode(NoonLoanResponse.self, from: Data(json.utf8))
        let minimums = NoonApiService.minimums(from: response, fallback: NoonConstants.fallbackMinimums)
        XCTAssertEqual(minimums.minDeposit, BigInt(100_000_000))
        XCTAssertEqual(minimums.minRedeem, BigInt(95_000_000))
    }

    func testMinimumsFallBackWhenLoanTermsAbsent() throws {
        // No on_chain_loan ⇒ use the NoonConstants product floors, never zero and
        // never MIN_AMOUNT_WEI.
        let json = """
        { "loan_computed": { "tvl_in_usd": 1.0 } }
        """
        let response = try JSONDecoder().decode(NoonLoanResponse.self, from: Data(json.utf8))
        let minimums = NoonApiService.minimums(from: response, fallback: NoonConstants.fallbackMinimums)
        XCTAssertEqual(minimums.minDeposit, BigInt(NoonConstants.minDepositAssets))
        XCTAssertEqual(minimums.minRedeem, BigInt(NoonConstants.minRedeemShares))
    }
}
