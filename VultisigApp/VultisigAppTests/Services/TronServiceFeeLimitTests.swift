//
//  TronServiceFeeLimitTests.swift
//  VultisigAppTests
//
//  Pins the simulation-based `fee_limit` math behind the TRC20 / swap
//  OUT_OF_ENERGY fix (issue/PR #4131). The bug being addressed:
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

    /// `defaultContractFeeLimit` returns the docs-backed fallback budget
    /// used when simulation isn't possible. 50,000,000 energy × 420 sun =
    /// 21,000,000,000 sun (21 TRX). Mirrors the Android
    /// `TronFeeService.DEFAULT_MAX_ENERGY_USED` reference.
    func testDefaultContractFeeLimit_returnsTwentyOneTrxAtCurrentEnergyPrice() {
        XCTAssertEqual(
            TronService.defaultContractFeeLimit(energyPrice: 420),
            BigInt(21_000_000_000)
        )
    }

    /// `defaultContractFeeLimit` tracks the on-chain `energyFeePrice` —
    /// if TRON raises the energy unit price via governance proposal, the
    /// fallback budget scales accordingly without code change.
    func testDefaultContractFeeLimit_scalesWithEnergyPrice() {
        XCTAssertEqual(
            TronService.defaultContractFeeLimit(energyPrice: 100),
            BigInt(5_000_000_000)
        )
        XCTAssertEqual(
            TronService.defaultContractFeeLimit(energyPrice: 1_000),
            BigInt(50_000_000_000)
        )
    }

    // MARK: - Dispatch (TronService.getBlockInfo)

    /// Happy path: TRC20 transfer to an existing address with a successful
    /// simulation. `gasFeeEstimation` should be derived from the simulated
    /// energy_used (not the previous fixed 1 / 18 / 36 TRX ladder).
    func testGetBlockInfo_trc20Transfer_usesSimulationResult() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000)
        let service = TronService(httpClient: stub)

        let coin = makeTrc20Coin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil)
        let gasFee = extractGasFee(result)

        // 65,000 × 1.3 × 420 = 35,490,000 sun. memo and activation are 0
        // in this scenario (no memo, destination account "exists" per the
        // stub's getaccount response).
        XCTAssertEqual(gasFee, 35_490_000)
    }

    /// Simulation throws (network error / TRON gateway 5xx). Old behavior
    /// fell through to `BYTES_PER_CONTRACT_TX * 1000` (~0.345 TRX), which
    /// silently re-introduced OUT_OF_ENERGY. New behavior: fall back to
    /// the safe default budget (~21 TRX).
    func testGetBlockInfo_trc20Transfer_fallsBackOnSimulationError() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 65_000)
        stub.errors[TronAPI(.triggerConstantContract(ownerAddress: "", contractAddress: "", functionSelector: "", parameter: "")).path] = HTTPError.invalidResponse
        let service = TronService(httpClient: stub)

        let coin = makeTrc20Coin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(gasFee, UInt64(TronService.defaultContractFeeLimit(energyPrice: 420)))
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

        XCTAssertEqual(gasFee, UInt64(TronService.defaultContractFeeLimit(energyPrice: 420)))
    }

    /// Native TRX swap (`isSwap == true`). We don't yet have the contract
    /// function selector + parameter at fee-calc time, so use the default
    /// budget — better than the prior bandwidth-only fee that would
    /// trigger OUT_OF_ENERGY on the swap's `triggerSmartContract` path.
    func testGetBlockInfo_nativeSwap_usesDefaultContractBudget() async throws {
        let stub = TronStubHTTPClient()
        stub.stubDefaults(energyUsed: 0)
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil, isSwap: true)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(gasFee, UInt64(TronService.defaultContractFeeLimit(energyPrice: 420)))
    }

    /// Native TRX transfer with sufficient bandwidth — the daily free-net
    /// quota covers the 300-byte transfer, so the on-chain fee is genuinely
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

    /// Native TRX transfer *without* sufficient bandwidth — the account has no
    /// free-net quota, so the node consumes the 300-byte bandwidth fee. The
    /// displayed fee must be the REAL bandwidth cost, not `coin.feeDefault`:
    /// 300 bytes (`BYTES_PER_COIN_TX`) × 1000 sun (`getTransactionFee` /
    /// `bandwidthFeePrice`) = 300_000 sun. Memo is 0 (none) and activation is
    /// 0 (destination "exists" per the stub's getaccount response).
    func testGetBlockInfo_nativeTransfer_insufficientBandwidth_showsRealBandwidthFee() async throws {
        let stub = TronStubHTTPClient()
        // Default getaccountresource has zero available bandwidth.
        stub.stubDefaults(energyUsed: 0)
        let service = TronService(httpClient: stub)

        let coin = makeNativeCoin()
        let result = try await service.getBlockInfo(coin: coin, to: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", memo: nil, isSwap: false)
        let gasFee = extractGasFee(result)

        XCTAssertEqual(gasFee, 300_000)
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
        guard case .Tron(_, _, _, _, _, _, _, _, let gasFee) = specific else {
            XCTFail("expected .Tron, got \(specific)")
            return 0
        }
        return gasFee
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
    func stubDefaults(energyUsed: Int) {
        setResponse(path: "/wallet/getnowblock", json: """
        {"block_header":{"raw_data":{"timestamp":1700000000,"number":1,"version":0,"txTrieRoot":"00","parentHash":"00","witness_address":"00"}}}
        """)
        setResponse(path: "/wallet/getchainparameters", json: """
        {"chainParameter":[{"key":"getEnergyFee","value":420},{"key":"getTransactionFee","value":1000}]}
        """)
        setResponse(path: "/wallet/getaccountresource", json: """
        {"freeNetUsed":0,"freeNetLimit":0,"NetUsed":0,"NetLimit":0,"EnergyUsed":0,"EnergyLimit":1000000}
        """)
        // Destination "exists" => no activation fee charged.
        setResponse(path: "/wallet/getaccount", json: """
        {"address":"TGexisting","balance":1}
        """)
        setResponse(path: "/wallet/triggerconstantcontract", json: """
        {"result":{"result":true},"energy_used":\(energyUsed)}
        """)
    }
}
