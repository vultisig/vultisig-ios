//
//  BlockaidSimulationServiceTests.swift
//  VultisigAppTests
//

import BigInt
@testable import VultisigApp
import XCTest

@MainActor
final class BlockaidSimulationServiceTests: XCTestCase {

    private var mock: MockBlockaidRpcClient!
    private var service: BlockaidSimulationService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mock = MockBlockaidRpcClient()
        service = BlockaidSimulationService(rpcClient: mock)
    }

    override func tearDownWithError() throws {
        mock = nil
        service = nil
        try super.tearDownWithError()
    }

    // MARK: - Short-circuit paths

    func test_simulate_returnsNil_forNonEvmPayload() async {
        let payload = Self.bitcoinPayload(memo: "0xabcdef")

        let result = await service.simulate(keysignPayload: payload)

        XCTAssertNil(result)
        XCTAssertEqual(mock.simulateCallCount, 0)
    }

    func test_simulate_returnsNil_whenMemoMissing() async {
        let payload = Self.ethereumPayload(memo: nil)

        let result = await service.simulate(keysignPayload: payload)

        XCTAssertNil(result)
        XCTAssertEqual(mock.simulateCallCount, 0)
    }

    func test_simulate_returnsNil_whenMemoNotHexPrefixed() async {
        let payload = Self.ethereumPayload(memo: "not-hex")

        let result = await service.simulate(keysignPayload: payload)

        XCTAssertNil(result)
        XCTAssertEqual(mock.simulateCallCount, 0)
    }

    // MARK: - Cache semantics

    func test_simulate_cachesSuccessResult() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "USDC", decimals: 6, rawAmount: "1000000"))
        let payload = Self.ethereumPayload(memo: "0xA9059CBB0000")

        _ = await service.simulate(keysignPayload: payload)
        _ = await service.simulate(keysignPayload: payload)

        XCTAssertEqual(mock.simulateCallCount, 1, "cached success should not re-hit the RPC")
    }

    func test_simulate_doesNotCacheFailures() async {
        mock.simulateResult = .failure(MockBlockaidRpcClient.StubError.simulated)
        let payload = Self.ethereumPayload(memo: "0xA9059CBB0000")

        _ = await service.simulate(keysignPayload: payload)
        _ = await service.simulate(keysignPayload: payload)

        XCTAssertEqual(mock.simulateCallCount, 2, "a network failure must allow the next screen to retry")
    }

    func test_simulate_differentMemosCacheIndependently() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "USDC", decimals: 6, rawAmount: "1000000"))
        let first = Self.ethereumPayload(memo: "0xA9059CBB0001")
        let second = Self.ethereumPayload(memo: "0xA9059CBB0002")

        _ = await service.simulate(keysignPayload: first)
        _ = await service.simulate(keysignPayload: second)
        _ = await service.simulate(keysignPayload: first)

        XCTAssertEqual(mock.simulateCallCount, 2, "distinct memos get distinct cache entries; re-asking first is a hit")
    }

    func test_simulate_memoHashIsCaseInsensitive() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "USDC", decimals: 6, rawAmount: "1000000"))
        let lower = Self.ethereumPayload(memo: "0xa9059cbb0000")
        let upper = Self.ethereumPayload(memo: "0xA9059CBB0000")

        _ = await service.simulate(keysignPayload: lower)
        _ = await service.simulate(keysignPayload: upper)

        XCTAssertEqual(mock.simulateCallCount, 1, "casing differences must not split the cache entry")
    }
}

// MARK: - Fixtures

private extension BlockaidSimulationServiceTests {

    static func ethereumPayload(memo: String?) -> KeysignPayload {
        let asset = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: "0xFrom", hexPublicKey: "hex")
        return KeysignPayload(
            coin: coin,
            toAddress: "0xTo",
            toAmount: BigInt(0),
            chainSpecific: BlockChainSpecific.Ethereum(
                maxFeePerGasWei: BigInt(1),
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: BigInt(21000)
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
    }

    static func bitcoinPayload(memo: String?) -> KeysignPayload {
        KeysignPayload(
            coin: Coin.example,
            toAddress: "bc1q",
            toAmount: BigInt(0),
            chainSpecific: BlockChainSpecific.UTXO(byteFee: 100, sendMaxAmount: false),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            skipBroadcast: false,
            signData: nil
        )
    }

    static func transferResponse(
        symbol: String,
        decimals: Int,
        rawAmount: String
    ) -> BlockaidEvmSimulationResponseJson {
        let asset = BlockaidEvmSimulationJson.Asset(
            type: "ERC20",
            decimals: decimals,
            address: "0xAsset",
            logoUrl: "https://token.png",
            name: symbol,
            symbol: symbol
        )
        let diff = BlockaidEvmSimulationJson.AssetDiff(
            asset: asset,
            assetType: "ERC20",
            in: nil,
            out: [BlockaidEvmSimulationJson.BalanceChange(rawValue: rawAmount)]
        )
        return BlockaidEvmSimulationResponseJson(
            simulation: BlockaidEvmSimulationJson(
                status: "Success",
                accountSummary: BlockaidEvmSimulationJson.AccountSummary(assetsDiffs: [diff])
            ),
            validation: nil,
            error: nil
        )
    }
}
