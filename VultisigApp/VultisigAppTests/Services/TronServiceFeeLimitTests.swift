//
//  TronServiceFeeLimitTests.swift
//  VultisigAppTests
//
//  Pins the simulation-based `fee_limit` math behind the TRC20 / swap
//  OUT_OF_ENERGY fix. The bug being addressed:
//  `Vault.fee_limit` is a strict upper bound on the energy budget the TVM
//  is willing to use for a contract call (`max_energy = fee_limit /
//  energy_unit_price`). The pre-fix code returned a 1 TRX / 18 TRX / 36 TRX
//  ladder, capping a typical USDT transfer at ~2,400 / ~43,000 / ~86,000
//  energy — below the ~65,000 energy a TRC20 transfer actually consumes,
//  triggering `OUT_OF_ENERGY` even when the user had staked enough free
//  energy to cover the call. See:
//
//  - https://developers.tron.network/docs/set-feelimit
//  - https://developers.tron.network/docs/resource-model#dynamic-energy-model
//

@testable import VultisigApp
import XCTest
import BigInt
import WalletCore

@MainActor
final class TronServiceFeeLimitTests: XCTestCase {

    // MARK: - Math helpers (pure)

    /// `contractFeeLimit` applies the 30% safety multiplier and translates
    /// energy units into a sun-denominated `fee_limit`. 65,000 energy ×
    /// 1.3 × 420 sun/energy = 35,490,000 sun (~35 TRX).
    func testContractFeeLimit_appliesSafetyMultiplierToEnergyAtChainPrice() {
        XCTAssertEqual(
            TronService.contractFeeLimit(energyUsed: 65_000, energyPrice: 420),
            BigInt(35_490_000)
        )
    }

    /// The 30% safety multiplier survives integer division (e.g. odd
    /// numerators don't collapse to a smaller value via truncation).
    func testContractFeeLimit_safetyMultiplierRoundsDownButStaysAboveBare() {
        let bare = BigInt(65_000 * 420) // 27,300,000 — what the user would pay without safety
        let withSafety = TronService.contractFeeLimit(energyUsed: 65_000, energyPrice: 420)
        XCTAssertGreaterThan(withSafety, bare)
    }

    /// `defaultContractFeeLimit` returns the opaque-swap estimate used before
    /// pre-built transaction bytes reach the fee layer. 50,000 energy × 420 sun =
    /// 21,000,000 sun (21 TRX).
    func testDefaultContractFeeLimitReturnsTwentyOneTrxAt420Sun() {
        XCTAssertEqual(
            TronService.defaultContractFeeLimit(energyPrice: 420),
            BigInt(21_000_000)
        )
    }

    /// `defaultContractFeeLimit` tracks the on-chain `energyFeePrice` —
    /// if TRON raises the energy unit price via governance proposal, the
    /// fallback budget scales accordingly without code change.
    func testDefaultContractFeeLimit_scalesWithEnergyPrice() {
        XCTAssertEqual(
            TronService.defaultContractFeeLimit(energyPrice: 100),
            BigInt(5_000_000)
        )
        XCTAssertEqual(
            TronService.defaultContractFeeLimit(energyPrice: 1_000),
            BigInt(50_000_000)
        )
    }

    func testEnergyFeePriceFallsBackToCurrentBaselineWhenParameterMissing() throws {
        let response = try JSONDecoder().decode(
            TronChainParametersResponse.self,
            from: Data(#"{"chainParameter":[]}"#.utf8)
        )

        XCTAssertEqual(response.energyFeePrice, 100)
        XCTAssertEqual(response.dynamicEnergyMaxFactor, 34_000)
        XCTAssertEqual(response.maxFeeLimit, 15_000_000_000)
    }

    func testEnergyFeePriceFallsBackToCurrentBaselineWhenParameterInvalid() throws {
        let response = try JSONDecoder().decode(
            TronChainParametersResponse.self,
            from: Data(#"{"chainParameter":[{"key":"getEnergyFee","value":0}]}"#.utf8)
        )

        XCTAssertEqual(response.energyFeePrice, 100)
    }

    func testTrc20FallbackUsesMaximumDynamicEnergyFactor() {
        let observedTransferWithHeadroom = TronService.contractFeeLimit(
            energyUsed: 130_285,
            energyPrice: 100
        )
        let fallback = TronService.defaultTrc20FeeLimit(
            energyPrice: 100,
            dynamicEnergyMaxFactor: 34_000,
            maxFeeLimit: 15_000_000_000
        )

        XCTAssertEqual(
            fallback,
            BigInt(28_600_000)
        )
        XCTAssertGreaterThan(fallback, observedTransferWithHeadroom)
    }

    func testContractFeeLimitNeverExceedsChainMaximum() {
        XCTAssertEqual(
            TronService.cappedFeeLimit(BigInt(21_000_000_000), maxFeeLimit: 15_000_000_000),
            BigInt(15_000_000_000)
        )
    }

    // MARK: - Dispatch (TronService.getBlockInfo)

    /// A successful simulation keeps two figures: the user's staked Energy
    /// reduces the displayed burn to zero, while the signed ceiling remains the
    /// gross simulated total plus headroom.
    func testGetBlockInfo_trc20Transfer_usesSimulationResult() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000, energyPenalty: 50_000)
        let service = TronService(httpClient: stub)

        let coin = makeTrc20Coin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil)

        XCTAssertEqual(extractGasFee(result), 0)
        XCTAssertEqual(extractFeeLimit(result), 35_490_000)
    }

    func testPenaltyPortionRemainsInGrossAndDisplayedEnergy() async throws {
        let stub = TronStubHTTPClient()
        // Official TRON semantics: energy_used is the 65k TOTAL and
        // energy_penalty is the 50k Dynamic Energy subset inside it. The fee
        // must use 65k, not the 15k base and not a double-counted 115k.
        stub.stubDefaults(energyUsed: 65_000, energyPenalty: 50_000)
        stub.setAvailableEnergy(0)
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeTrc20Coin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )

        XCTAssertEqual(extractGasFee(result), 27_300_000)
        XCTAssertEqual(extractFeeLimit(result), 35_490_000)
    }

    func testFullStakedEnergyOnlyDiscountsDisplayedBurn() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000, energyPenalty: 50_000)
        stub.setAvailableEnergy(65_000)
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeTrc20Coin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )

        XCTAssertEqual(extractGasFee(result), 0)
        XCTAssertEqual(extractFeeLimit(result), 35_490_000)
    }

    func testPartialStakedEnergyOnlyDiscountsUncoveredBurn() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000, energyPenalty: 50_000)
        stub.setAvailableEnergy(30_000)
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeTrc20Coin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )

        XCTAssertEqual(extractGasFee(result), 14_700_000)
        XCTAssertEqual(extractFeeLimit(result), 35_490_000)
    }

    func testResourceFetchFailureShowsFullBurnWithoutLoweringCeiling() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000, energyPenalty: 50_000)
        stub.errors["/wallet/getaccountresource"] = HTTPError.invalidResponse
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeTrc20Coin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )

        XCTAssertEqual(extractGasFee(result), 27_300_000)
        XCTAssertEqual(extractFeeLimit(result), 35_490_000)
    }

    /// Simulation throws (network error / TRON gateway 5xx). Old behavior
    /// fell through to a 345-byte bandwidth charge (~0.345 TRX), which
    /// silently re-introduced OUT_OF_ENERGY. New behavior: fall back to
    /// the max-factor fallback (120.12 TRX at the test chain price).
    func testGetBlockInfo_trc20Transfer_fallsBackOnSimulationError() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000)
        stub.errors[TronAPI(.triggerConstantContract(ownerAddress: "", contractAddress: "", functionSelector: "", parameter: "")).path] = HTTPError.invalidResponse
        let service = TronService(httpClient: stub)

        let coin = makeTrc20Coin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(
            gasFee,
            UInt64(TronService.defaultTrc20FeeLimit(
                energyPrice: 420,
                dynamicEnergyMaxFactor: 34_000,
                maxFeeLimit: 15_000_000_000
            ))
        )
    }

    /// Simulation returns `result.result = false` (e.g. insufficient TRC20
    /// balance — common when estimating before the user funds the account).
    /// Same fallback as the error path.
    func testGetBlockInfo_trc20Transfer_fallsBackWhenSimulationResultFalse() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000)
        stub.setResponse(path: "/wallet/triggerconstantcontract", json: """
        {"result":{"result":false,"message":"REVERT"},"energy_used":0}
        """)
        let service = TronService(httpClient: stub)

        let coin = makeTrc20Coin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(
            gasFee,
            UInt64(TronService.defaultTrc20FeeLimit(
                energyPrice: 420,
                dynamicEnergyMaxFactor: 34_000,
                maxFeeLimit: 15_000_000_000
            ))
        )
    }

    func testSuccessfulSimulationWithMessageFallsBack() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 10, energyPenalty: 0)
        stub.setResponse(path: "/wallet/triggerconstantcontract", json: """
        {"result":{"result":true,"message":"REVERT opcode executed"},"energy_used":10,"energy_penalty":0}
        """)
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeTrc20Coin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )
        let fallback = UInt64(TronService.defaultTrc20FeeLimit(
            energyPrice: 420,
            dynamicEnergyMaxFactor: 34_000,
            maxFeeLimit: 15_000_000_000
        ))

        XCTAssertEqual(extractGasFee(result), fallback)
        XCTAssertEqual(extractFeeLimit(result), fallback)
    }

    func testDisplayedAndSignedFeesRespectChainMaximum() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000, energyPenalty: 50_000)
        stub.setAvailableEnergy(0)
        stub.setResponse(path: "/wallet/getchainparameters", json: """
        {"chainParameter":[
            {"key":"getEnergyFee","value":420},
            {"key":"getTransactionFee","value":1000},
            {"key":"getDynamicEnergyMaxFactor","value":34000},
            {"key":"getMaxFeeLimit","value":10000000}
        ]}
        """)
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeTrc20Coin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )

        XCTAssertEqual(extractGasFee(result), 10_000_000)
        XCTAssertEqual(extractFeeLimit(result), 10_000_000)
    }

    func testProtoKeepsGrossCeilingWithoutNewWireField() throws {
        let local = makeTronSpecific(displayFee: 1_000_000, feeLimit: 35_490_000)
        guard case .tronSpecific(let proto) = local.mapToProtobuff() else {
            return XCTFail("expected tron proto")
        }

        XCTAssertEqual(local.gas, 1_000_000)
        XCTAssertEqual(local.tronFeeLimit, 35_490_000)
        XCTAssertEqual(proto.gasEstimation, 35_490_000)

        let legacy = makeTronSpecific(displayFee: 35_490_000)
        guard case .tronSpecific(let legacyProto) = legacy.mapToProtobuff() else {
            return XCTFail("expected legacy tron proto")
        }
        XCTAssertEqual(proto, legacyProto)

        let peer = try BlockChainSpecific(proto: .tronSpecific(proto))
        XCTAssertEqual(peer.gas, 35_490_000)
        XCTAssertEqual(peer.tronFeeLimit, local.tronFeeLimit)
    }

    func testLocalAndProtoRoundTripSignIdenticalGrossFeeLimit() throws {
        let localSpecific = makeTronSpecific(displayFee: 1_000_000, feeLimit: 35_490_000)
        guard case .tronSpecific(let proto) = localSpecific.mapToProtobuff() else {
            return XCTFail("expected tron proto")
        }
        let peerSpecific = try BlockChainSpecific(proto: .tronSpecific(proto))
        let coin = SigningGoldenFactory.coin(
            chain: .tron,
            ticker: "USDT",
            decimals: 6,
            contractAddress: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            isNativeToken: false,
            curve: .secp256k1,
            uncompressedSecp: true
        )
        let recipient = SigningGoldenFactory.recipient(.tron)
        let localPayload = SigningGoldenFactory.payload(
            coin: coin,
            toAddress: recipient,
            toAmount: 1,
            chainSpecific: localSpecific
        )
        let peerPayload = SigningGoldenFactory.payload(
            coin: coin,
            toAddress: recipient,
            toAmount: 1,
            chainSpecific: peerSpecific
        )

        let localBytes = try TronHelper.getPreSignedInputData(keysignPayload: localPayload)
        let peerBytes = try TronHelper.getPreSignedInputData(keysignPayload: peerPayload)
        let localInput = try TronSigningInput(serializedBytes: localBytes)
        let peerInput = try TronSigningInput(serializedBytes: peerBytes)

        XCTAssertEqual(localInput.transaction.feeLimit, 35_490_000)
        XCTAssertEqual(peerInput.transaction.feeLimit, 35_490_000)
        XCTAssertEqual(localBytes, peerBytes)
    }

    func testLegacyTronSpecificCodableWithoutFeeLimitStillDecodes() throws {
        let legacy = makeTronSpecific(displayFee: 35_490_000)
        let encoded = try JSONEncoder().encode(legacy)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(json.contains("feeLimit"))

        let decoded = try JSONDecoder().decode(BlockChainSpecific.self, from: encoded)
        XCTAssertEqual(decoded.gas, 35_490_000)
        XCTAssertEqual(decoded.tronFeeLimit, 35_490_000)
    }

    /// Opaque native TRX swap (`isSwap == true`). The pre-built transaction
    /// reaches the signer later, so this layer uses its smaller UI estimate.
    func testGetBlockInfo_nativeSwap_usesDefaultContractBudget() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil, isSwap: true)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(gasFee, UInt64(TronService.defaultContractFeeLimit(energyPrice: 420)))
    }

    func testNativeSwapUsesCurrentFallbackWhenChainParametersUnavailable() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        stub.errors["/wallet/getchainparameters"] = HTTPError.invalidResponse
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeNativeCoin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
            memo: nil,
            isSwap: true
        )

        XCTAssertEqual(extractGasFee(result), 5_000_000)
    }

    func testTrc20SimulationFailureNeverUsesOpaqueSwapEstimate() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        stub.errors["/wallet/getchainparameters"] = HTTPError.invalidResponse
        stub.errors["/wallet/triggerconstantcontract"] = HTTPError.invalidResponse
        let service = TronService(httpClient: stub)

        let result = try await service.getBlockInfo(
            coin: makeTrc20Coin(),
            to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )

        XCTAssertEqual(extractGasFee(result), 28_600_000)
    }

    /// Native TRX transfer with sufficient bandwidth — the daily free-net
    /// quota covers the whole serialized transfer, so the on-chain fee is genuinely
    /// 0. `gasFeeEstimation` must report that true 0 (Android parity), not a
    /// fabricated `coin.feeDefault`. This case is the *only* one where
    /// `calculateTronFee` returns 0: TRC20 / native-swap / bandwidth-shortfall
    /// / memo / inactive-destination paths all yield a non-zero fee.
    func testGetBlockInfo_nativeTransfer_sufficientBandwidth_showsZeroFee() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        // Generous bandwidth — discount kicks in.
        stub.setResponse(path: "/wallet/getaccountresource", json: """
        {"freeNetUsed":0,"freeNetLimit":600,"NetUsed":0,"NetLimit":10000,"EnergyUsed":0,"EnergyLimit":0}
        """)
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil, isSwap: false)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(gasFee, 0)
    }

    /// `WITHDRAW_EXPIRE_UNFREEZE` is an app-local routing marker, not TRON
    /// transaction data. The claim builder omits it from the signed bytes, so
    /// the fee estimate must not charge getMemoFee for it either.
    func testWithdrawExpireUnfreezeDoesNotChargeRoutingMemoFee() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        stub.setResponse(path: "/wallet/getaccountresource", json: """
        {"freeNetUsed":0,"freeNetLimit":600,"NetUsed":0,"NetLimit":10000,"EnergyUsed":0,"EnergyLimit":0}
        """)
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(
            coin: coin,
            to: coin.address,
            memo: TronHelper.withdrawExpireUnfreezeMemo
        )

        XCTAssertEqual(extractGasFee(result), 0)
    }

    func testFreezeAndUnfreezeDoNotChargeRoutingMemoFee() async throws {
        for memo in ["FREEZE:BANDWIDTH", "FREEZE:ENERGY", "UNFREEZE:BANDWIDTH", "UNFREEZE:ENERGY"] {
            let stub = TronStubHTTPClient()
            stub.stubDefaults(energyUsed: 0)
            stub.setResponse(path: "/wallet/getaccountresource", json: """
            {"freeNetUsed":0,"freeNetLimit":600,"NetUsed":0,"NetLimit":10000,"EnergyUsed":0,"EnergyLimit":0}
            """)
            let service = TronService(httpClient: stub)
            let coin = makeNativeCoin()

            let result = try await service.getBlockInfo(
                coin: coin,
                to: coin.address,
                memo: memo
            )

            XCTAssertEqual(extractGasFee(result), 0, "Unexpected memo fee for \(memo)")
        }
    }

    /// A real memo still pays the chain's getMemoFee parameter; the routing-
    /// marker exception above must not weaken ordinary TRON fee estimation.
    func testNativeTransferRealMemoStillChargesMemoFee() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        stub.setResponse(path: "/wallet/getaccountresource", json: """
        {"freeNetUsed":0,"freeNetLimit":600,"NetUsed":0,"NetLimit":10000,"EnergyUsed":0,"EnergyLimit":0}
        """)
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(coin: coin, to: coin.address, memo: "hello")

        XCTAssertEqual(extractGasFee(result), 1_000_000)
    }

    /// Native TRX transfer *without* sufficient bandwidth — the account has no
    /// free-net quota, so the node charges for every byte of the signed
    /// transaction at 1000 sun (`getTransactionFee` / `bandwidthFeePrice`).
    /// The displayed fee must be the REAL bandwidth cost, not `coin.feeDefault`.
    /// Memo is 0 (none) and activation is 0 (destination "exists" per the
    /// stub's getaccount response).
    func testGetBlockInfoNativeTransferInsufficientBandwidthPricesMeasuredBytes() async throws {
        let stub = TronStubHTTPClient()
        // Default getaccountresource has zero available bandwidth.
        stub.stubDefaults(energyUsed: 0)
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(coin: coin, to: Self.recipient, memo: nil, isSwap: false)

        XCTAssertEqual(extractGasFee(result), Self.memolessBandwidthBytes * 1000)
    }

    /// The defect this replaced: bandwidth was reserved from a 300-byte
    /// constant, so a memo — which is serialized into the transaction — could
    /// push the real transfer past the free bandwidth the account holds while
    /// the app still displayed it as free. At the same available bandwidth the
    /// memo-less send is free and the memo-bearing one is not.
    func testGetBlockInfoMemoPushesTransferPastTheFreeBandwidthItFitsWithout() async throws {
        let coin = makeNativeCoin()
        let memo = String(repeating: "a", count: Self.memoLength)
        let freeBandwidth = Int64(Self.memolessBandwidthBytes)

        let bare = try await gasFee(coin: coin, memo: nil, availableBandwidth: freeBandwidth)
        XCTAssertEqual(bare, 0)

        let withMemo = try await gasFee(coin: coin, memo: memo, availableBandwidth: freeBandwidth)
        // The flat `getMemoFee` chain parameter is charged on top of bandwidth.
        XCTAssertEqual(withMemo, Self.memo100BandwidthBytes * 1000 + 1_000_000)
    }

    /// Routing markers select a WalletCore system-contract builder and never
    /// reach the wire, so they must not inflate the bandwidth reserve either.
    func testGetBlockInfoRoutingMemoDoesNotInflateTheBandwidthReserve() async throws {
        let coin = makeNativeCoin()
        let freeBandwidth = Int64(Self.memolessBandwidthBytes)

        let fee = try await gasFee(
            coin: coin,
            memo: TronHelper.withdrawExpireUnfreezeMemo,
            availableBandwidth: freeBandwidth,
            to: coin.address
        )

        XCTAssertEqual(fee, 0)
    }

    /// Native TRX transfer where the account-resource fetch FAILS — the true
    /// bandwidth availability is unknown, so we must not collapse to a false 0
    /// (which would render a real transfer as free and mislead the max-amount
    /// calc). The error path falls back to the coin's conservative static fee
    /// (`coin.feeDefault` = 100_000 sun for TRX), distinct from the genuinely
    /// free case above which reports a true 0.
    func testGetBlockInfo_nativeTransfer_resourceFetchError_fallsBackToStaticFee() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        stub.errors["/wallet/getaccountresource"] = HTTPError.invalidResponse
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil, isSwap: false)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(gasFee, 100_000)
    }

    // MARK: - Helpers

    private static let recipient = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

    /// Hand-derived byte counts for the transfer these tests build, so the
    /// expectations do not come from the production helper they are checking.
    /// The derivation is spelled out field by field in
    /// `TronBandwidthEstimateTests`; the only difference is that `getBlockInfo`
    /// is called with no amount here, so `TransferContract.amount` stays at its
    /// proto3 default and its 4 bytes are not serialized: 267 - 4 = 263. Both
    /// millisecond timestamps are fixed-width for the next several decades, so
    /// neither count depends on when the test runs.
    private static let memolessBandwidthBytes: UInt64 = 263

    /// The same transfer carrying a 100-byte memo, whose `data` field adds
    /// 1 tag + 1 length + 100 = 102 bytes.
    private static let memo100BandwidthBytes: UInt64 = 365

    /// Length of the memo `memo100BandwidthBytes` was derived for.
    private static let memoLength = 100

    private func gasFee(
        coin: Coin,
        memo: String?,
        availableBandwidth: Int64,
        to: String? = nil
    ) async throws -> UInt64 {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        stub.setResponse(path: "/wallet/getaccountresource", json: """
        {"freeNetUsed":0,"freeNetLimit":\(availableBandwidth),"NetUsed":0,"NetLimit":0,"EnergyUsed":0,"EnergyLimit":0}
        """)
        let service = TronService(httpClient: stub)
        let result = try await service.getBlockInfo(
            coin: coin,
            to: to ?? Self.recipient,
            memo: memo,
            isSwap: false
        )
        return extractGasFee(result)
    }

    private func makeTrc20Coin() -> Coin {
        let asset = CoinMeta.make(
            chain: .tron,
            ticker: "USDT",
            decimals: 6,
            isNativeToken: false,
            contractAddress: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
        )
        return Coin(asset: asset, address: "TKt9bGgWeFFu2yRgULxRhmiBADuoEoadq8", hexPublicKey: "")
    }

    private func makeNativeCoin() -> Coin {
        let asset = CoinMeta.make(
            chain: .tron,
            ticker: "TRX",
            decimals: 6,
            isNativeToken: true
        )
        return Coin(asset: asset, address: "TKt9bGgWeFFu2yRgULxRhmiBADuoEoadq8", hexPublicKey: "")
    }

    private func extractGasFee(_ specific: BlockChainSpecific) -> UInt64 {
        guard case .Tron(_, _, _, _, _, _, _, _, let gasFee, _) = specific else {
            XCTFail("expected .Tron, got \(specific)")
            return 0
        }
        return gasFee
    }

    private func extractFeeLimit(_ specific: BlockChainSpecific) -> UInt64 {
        guard let feeLimit = specific.tronFeeLimit else {
            XCTFail("expected .Tron, got \(specific)")
            return 0
        }
        return feeLimit
    }

    private func makeTronSpecific(displayFee: UInt64, feeLimit: UInt64? = nil) -> BlockChainSpecific {
        .Tron(
            timestamp: 1,
            expiration: 2,
            blockHeaderTimestamp: 3,
            blockHeaderNumber: 4,
            blockHeaderVersion: 5,
            blockHeaderTxTrieRoot: String(repeating: "06", count: 32),
            blockHeaderParentHash: String(repeating: "07", count: 32),
            blockHeaderWitnessAddress: "41" + String(repeating: "08", count: 20),
            gasFeeEstimation: displayFee,
            feeLimit: feeLimit
        )
    }
}

// MARK: - CoinMeta convenience

private extension CoinMeta {
    static func make(
        chain: Chain,
        ticker: String,
        decimals: Int = 6,
        isNativeToken: Bool,
        contractAddress: String = ""
    ) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: decimals,
            priceProviderId: "",
            contractAddress: contractAddress,
            isNativeToken: isNativeToken
        )
    }
}

// MARK: - Stub HTTPClient

/// Path-keyed JSON stub. Tests register canned responses (or errors) by
/// URL path; the stub dispatches on `target.path` so test ordering doesn't
/// matter and chain-parameter caching inside `TronService` works
/// transparently.
private final class TronStubHTTPClient: HTTPClientProtocol {

    var responses: [String: Data] = [:]
    var errors: [String: Error] = [:]

    // Protocol requires `async`; the body is sync. Silence the lint here.
    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        let path = target.path
        if let error = errors[path] { throw error }
        guard let data = responses[path] else {
            XCTFail("TronStubHTTPClient has no stub for path '\(path)'")
            throw HTTPError.invalidResponse
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: data, response: response)
    }

    func setResponse(path: String, json: String) {
        responses[path] = Data(json.utf8)
    }

    /// Wires up a baseline of valid responses for every endpoint the fee
    /// path touches. Individual tests override specific entries.
    func stubDefaults(energyUsed: Int, energyPenalty: Int = 0) {
        setResponse(path: "/wallet/getnowblock", json: """
        {"block_header":{"raw_data":{"timestamp":1700000000,"number":1,"version":0,"txTrieRoot":"00","parentHash":"00","witness_address":"00"}}}
        """)
        setResponse(path: "/wallet/getchainparameters", json: """
        {"chainParameter":[
            {"key":"getEnergyFee","value":420},
            {"key":"getTransactionFee","value":1000},
            {"key":"getDynamicEnergyMaxFactor","value":34000},
            {"key":"getMaxFeeLimit","value":15000000000}
        ]}
        """)
        setResponse(path: "/wallet/getaccountresource", json: """
        {"freeNetUsed":0,"freeNetLimit":0,"NetUsed":0,"NetLimit":0,"EnergyUsed":0,"EnergyLimit":1000000}
        """)
        // Destination "exists" => no activation fee charged.
        setResponse(path: "/wallet/getaccount", json: """
        {"address":"TGexisting","balance":1}
        """)
        setResponse(path: "/wallet/triggerconstantcontract", json: """
        {"result":{"result":true},"energy_used":\(energyUsed),"energy_penalty":\(energyPenalty)}
        """)
    }

    func setAvailableEnergy(_ energy: Int64) {
        setResponse(path: "/wallet/getaccountresource", json: """
        {"freeNetUsed":0,"freeNetLimit":0,"NetUsed":0,"NetLimit":0,"EnergyUsed":0,"EnergyLimit":\(energy)}
        """)
    }
}
