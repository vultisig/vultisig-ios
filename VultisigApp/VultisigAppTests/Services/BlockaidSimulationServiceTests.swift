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

    func test_scan_nativeEvmTransferWithoutMemo_usesSignedValueAndEmptyCalldata() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "ETH", decimals: 18, rawAmount: "1"))
        let payload = Self.ethereumPayload(memo: nil, amount: 123)

        _ = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulateCallCount, 1)
        XCTAssertEqual(mock.simulatedMemos, ["0x"])
        XCTAssertEqual(mock.simulatedAmounts, ["0x7b"])
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

    func test_scan_evmDifferentRecipientsAndValuesHaveSeparateCacheEntries() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "ETH", decimals: 18, rawAmount: "1"))
        let first = Self.ethereumPayload(memo: nil, amount: 1)
        let second = Self.ethereumPayload(memo: nil, amount: 2)
        let third = Self.ethereumPayload(memo: nil, amount: 1, toAddress: "0xAnother")

        _ = await service.scan(keysignPayload: first)
        _ = await service.scan(keysignPayload: second)
        _ = await service.scan(keysignPayload: third)
        _ = await service.scan(keysignPayload: first)

        XCTAssertEqual(mock.simulateCallCount, 3)
    }

    func test_scan_genericEvmSwap_usesQuoteTransactionRatherThanPayloadTransfer() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "ETH", decimals: 18, rawAmount: "1"))
        let payload = Self.ethereumPayload(
            memo: nil,
            amount: 123,
            swapPayload: Self.genericSwapPayload()
        )

        _ = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulatedRecipients, ["0xrouter"])
        XCTAssertEqual(mock.simulatedAmounts, ["0x07"])
        XCTAssertEqual(mock.simulatedMemos, ["0xabcdef"])
    }

    func test_scan_plainErc20Transfer_usesContractAndSignedTransferCalldata() async {
        mock.simulateResult = .success(Self.transferResponse(symbol: "USDC", decimals: 6, rawAmount: "1"))
        let payload = Self.ethereumPayload(
            memo: nil,
            amount: 123,
            toAddress: "0x2222222222222222222222222222222222222222",
            isNative: false
        )

        _ = await service.scan(keysignPayload: payload)

        XCTAssertEqual(mock.simulatedRecipients, ["0x1111111111111111111111111111111111111111"])
        XCTAssertEqual(mock.simulatedAmounts, ["0x00"])
        XCTAssertTrue(mock.simulatedMemos.first?.hasPrefix("0xa9059cbb") == true)
    }

    func test_scan_nativeTransferSuccessTransitionsRingFromLoadingToSuccess() async {
        mock.simulateResult = .success(Self.riskResponse(resultType: "Benign"))
        let payload = Self.ethereumPayload(memo: nil, amount: 1)
        XCTAssertEqual(KeysignReviewScanRing(.idle).animationState, .loading)

        let result = await service.scan(keysignPayload: payload)

        XCTAssertEqual(result.scannerResult?.riskLevel, .noRisk)
        guard let scannerResult = result.scannerResult else { return XCTFail("Expected a Blockaid verdict") }
        XCTAssertEqual(KeysignReviewScanRing(.scanned(scannerResult), isScanComplete: true).animationState, .success)
    }

    func test_scan_nativeTransferRiskTransitionsRingToMediumRisk() async {
        mock.simulateResult = .success(Self.riskResponse(resultType: "Warning"))
        let payload = Self.ethereumPayload(memo: nil, amount: 1)

        let result = await service.scan(keysignPayload: payload)

        XCTAssertEqual(result.scannerResult?.riskLevel, .medium)
        guard let scannerResult = result.scannerResult else { return XCTFail("Expected a Blockaid verdict") }
        XCTAssertEqual(KeysignReviewScanRing(.scanned(scannerResult), isScanComplete: true).animationState, .mediumRisk)
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

    static func ethereumPayload(
        memo: String?,
        amount: BigInt = 0,
        toAddress: String = "0xTo",
        isNative: Bool = true,
        swapPayload: SwapPayload? = nil
    ) -> KeysignPayload {
        let asset = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: isNative ? "" : "0x1111111111111111111111111111111111111111",
            isNativeToken: isNative
        )
        let coin = Coin(asset: asset, address: "0xFrom", hexPublicKey: "hex")
        return KeysignPayload(
            coin: coin,
            toAddress: toAddress,
            toAmount: amount,
            chainSpecific: BlockChainSpecific.Ethereum(
                maxFeePerGasWei: BigInt(1),
                priorityFeeWei: BigInt(1),
                nonce: 0,
                gasLimit: BigInt(21000)
            ),
            utxos: [],
            memo: memo,
            swapPayload: swapPayload,
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

    static func genericSwapPayload() -> SwapPayload {
        let from = ethereumPayload(memo: nil).coin
        let to = Coin.example
        return .generic(GenericSwapPayload(
            fromCoin: from,
            toCoin: to,
            fromAmount: 123,
            toAmountDecimal: 456,
            quote: EVMQuote(
                dstAmount: "456",
                tx: EVMQuote.Transaction(
                    from: "0xFrom",
                    to: "0xRouter",
                    data: "0xabcdef",
                    value: "7",
                    gasPrice: "1",
                    gas: 100_000
                )
            ),
            provider: .oneInch
        ))
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
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
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
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
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

    static func riskResponse(resultType: String) -> BlockaidEvmSimulationResponseJson {
        BlockaidEvmSimulationResponseJson(
            simulation: nil,
            validation: .init(
                status: "Success",
                classification: resultType,
                resultType: resultType,
                description: nil,
                reason: nil,
                features: [],
                error: nil
            ),
            error: nil
        )
    }
}
