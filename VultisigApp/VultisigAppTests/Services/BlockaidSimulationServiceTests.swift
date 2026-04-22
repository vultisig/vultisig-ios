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

        let result = await service.scan(keysignPayload: payload)

        XCTAssertNil(result.simulation)
        XCTAssertNil(result.scannerResult)
        XCTAssertEqual(mock.simulateCallCount, 0)
    }

    func test_simulate_returnsNil_whenMemoMissing() async {
        let payload = Self.ethereumPayload(memo: nil)

        let result = await service.scan(keysignPayload: payload)

        XCTAssertNil(result.simulation)
        XCTAssertNil(result.scannerResult)
        XCTAssertEqual(mock.simulateCallCount, 0)
    }

    func test_simulate_returnsNil_whenMemoNotHexPrefixed() async {
        let payload = Self.ethereumPayload(memo: "not-hex")

        let result = await service.scan(keysignPayload: payload)

        XCTAssertNil(result.simulation)
        XCTAssertNil(result.scannerResult)
        XCTAssertEqual(mock.simulateCallCount, 0)
    }

    // MARK: - Cache semantics

    func test_simulate_cachesSuccessResult() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "USDC", decimals: 6, rawAmount: "1000000"))
        let payload = Self.ethereumPayload(memo: "0xA9059CBB0000")

        _ = await service.scan(keysignPayload: payload)
        _ = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulateCallCount, 1, "cached success should not re-hit the RPC")
    }

    func test_simulate_doesNotCacheFailures() async {
        mock.simulateResult = .failure(MockBlockaidRpcClient.StubError.simulated)
        let payload = Self.ethereumPayload(memo: "0xA9059CBB0000")

        _ = await service.scan(keysignPayload: payload)
        _ = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulateCallCount, 2, "a network failure must allow the next screen to retry")
    }

    func test_simulate_differentMemosCacheIndependently() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "USDC", decimals: 6, rawAmount: "1000000"))
        let first = Self.ethereumPayload(memo: "0xA9059CBB0001")
        let second = Self.ethereumPayload(memo: "0xA9059CBB0002")

        _ = await service.scan(keysignPayload: first)
        _ = await service.scan(keysignPayload: second)
        _ = await service.scan(keysignPayload: first)

        XCTAssertEqual(mock.simulateCallCount, 2, "distinct memos get distinct cache entries; re-asking first is a hit")
    }

    func test_simulate_memoHashIsCaseInsensitive() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "USDC", decimals: 6, rawAmount: "1000000"))
        let lower = Self.ethereumPayload(memo: "0xa9059cbb0000")
        let upper = Self.ethereumPayload(memo: "0xA9059CBB0000")

        _ = await service.scan(keysignPayload: lower)
        _ = await service.scan(keysignPayload: upper)

        XCTAssertEqual(mock.simulateCallCount, 1, "casing differences must not split the cache entry")
    }

    // MARK: - Solana

    func test_scan_dispatchesToSolanaRpc_andDecodesRawTxsToBase58() async {
        mock.simulateSolanaResult = .success(Self.solanaTransferResponse(symbol: "USDC", decimals: 6, rawAmount: "1500000"))
        // base64("hello") = "aGVsbG8=", base58 of "hello" bytes = "Cn8eVZg"
        let payload = Self.solanaPayload(rawTransactionsBase64: ["aGVsbG8="])

        let result = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulateSolanaCallCount, 1)
        XCTAssertEqual(mock.simulateCallCount, 0, "Solana payload must not hit the EVM RPC")
        XCTAssertEqual(mock.simulatedSolanaRawTransactions.first, ["Cn8eVZg"])
        guard case let .transfer(coin, _) = result.simulation else {
            return XCTFail("expected .transfer from Solana parse")
        }
        XCTAssertEqual(coin.ticker, "USDC")
        XCTAssertEqual(coin.chain, .solana)
    }

    func test_scan_solana_returnsEmpty_whenSignSolanaMissing() async {
        let payload = Self.solanaPayload(rawTransactionsBase64: nil)

        let result = await service.scan(keysignPayload: payload)

        XCTAssertEqual(result, .empty)
        XCTAssertEqual(mock.simulateSolanaCallCount, 0, "no raw txs → no RPC call")
    }

    func test_scan_solana_cachesSuccessResult() async {
        mock.simulateSolanaResult = .success(Self.solanaTransferResponse(symbol: "USDC", decimals: 6, rawAmount: "1500000"))
        let payload = Self.solanaPayload(rawTransactionsBase64: ["aGVsbG8="])

        _ = await service.scan(keysignPayload: payload)
        _ = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulateSolanaCallCount, 1, "cached success should not re-hit the RPC")
    }

    func test_scan_solana_differentRawTxsCacheIndependently() async {
        mock.simulateSolanaResult = .success(Self.solanaTransferResponse(symbol: "USDC", decimals: 6, rawAmount: "1500000"))
        let a = Self.solanaPayload(rawTransactionsBase64: ["aGVsbG8="])
        let b = Self.solanaPayload(rawTransactionsBase64: ["d29ybGQ="]) // "world"

        _ = await service.scan(keysignPayload: a)
        _ = await service.scan(keysignPayload: b)
        _ = await service.scan(keysignPayload: a)

        XCTAssertEqual(mock.simulateSolanaCallCount, 2, "distinct raw txs → distinct cache entries; re-asking first is a hit")
    }

    func test_scan_solana_doesNotCacheFailures() async {
        mock.simulateSolanaResult = .failure(MockBlockaidRpcClient.StubError.simulated)
        let payload = Self.solanaPayload(rawTransactionsBase64: ["aGVsbG8="])

        _ = await service.scan(keysignPayload: payload)
        _ = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulateSolanaCallCount, 2, "network failure must allow the next screen to retry")
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

    static func solanaPayload(rawTransactionsBase64: [String]?) -> KeysignPayload {
        let asset = CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "solana",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: "SoAddress", hexPublicKey: "hex")
        let signData: SignData? = rawTransactionsBase64.map { txs in
            .signSolana(SignSolana(proto: .with { $0.rawTransactions = txs }))
        }
        return KeysignPayload(
            coin: coin,
            toAddress: "SoTo",
            toAmount: BigInt(0),
            chainSpecific: BlockChainSpecific.Solana(
                recentBlockHash: "hash",
                priorityFee: BigInt(0),
                priorityLimit: BigInt(0),
                fromAddressPubKey: nil,
                toAddressPubKey: nil,
                hasProgramId: false
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
            skipBroadcast: false,
            signData: signData
        )
    }

    static func solanaTransferResponse(
        symbol: String,
        decimals: Int,
        rawAmount: String
    ) -> BlockaidSolanaSimulationResponseJson {
        let asset = BlockaidSolanaSimulationJson.Asset(
            type: "TOKEN",
            name: symbol,
            symbol: symbol,
            address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            decimals: decimals,
            logo: nil
        )
        let diff = BlockaidSolanaSimulationJson.AccountAssetDiff(
            asset: asset,
            assetType: "TOKEN",
            in: nil,
            out: BlockaidSolanaSimulationJson.BalanceChange(rawValue: rawAmount)
        )
        return BlockaidSolanaSimulationResponseJson(
            result: BlockaidSolanaSimulationResponseJson.BlockaidSolanaSimulationResultJson(
                simulation: BlockaidSolanaSimulationJson(
                    accountSummary: BlockaidSolanaSimulationJson.AccountSummary(accountAssetsDiff: [diff])
                ),
                validation: nil
            ),
            status: "Success",
            error: nil
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
