//
//  SecurityScannerSwapTests.swift
//  VultisigAppTests
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

final class SecurityScannerSwapTests: XCTestCase {
    func testJupiterSolanaSwapUsesProviderTransactionBytes() throws {
        let wire = Data([0, 1, 2, 3, 254, 255])
        let transaction = makeTransaction(
            quote: .jupiter(
                makeSolanaQuote(base64: wire.base64EncodedString()),
                fee: nil,
                platformFee: .zero,
                feeOnInput: false
            )
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        XCTAssertEqual(scannerTransaction.chain, .solana)
        XCTAssertEqual(scannerTransaction.type.rawValue, SecurityTransactionType.swap.rawValue)
        XCTAssertEqual(scannerTransaction.from, transaction.fromCoin.address)
        XCTAssertEqual(scannerTransaction.to, transaction.recipientAddress)
        XCTAssertEqual(scannerTransaction.amount, .zero)
        XCTAssertEqual(scannerTransaction.data, Base58.encodeNoCheck(data: wire))
    }

    func testLiFiSolanaSwapUsesProviderTransactionBytes() throws {
        let wire = Data([4, 5, 6, 7])
        let transaction = makeTransaction(
            quote: .lifi(
                makeSolanaQuote(base64: wire.base64EncodedString()),
                fee: nil,
                integratorFee: nil
            )
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        XCTAssertEqual(scannerTransaction.data, Base58.encodeNoCheck(data: wire))
    }

    func testSwapKitSolanaSwapUsesTypedProviderTransactionBytes() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-sol-near-swap-fresh"
        )
        guard case let .solana(base64) = response.tx,
              let wire = Data(base64Encoded: base64) else {
            return XCTFail("Expected a valid typed Solana transaction fixture")
        }
        let transaction = makeTransaction(
            quote: .swapkit(response, fee: nil, subProvider: "NEAR")
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        XCTAssertEqual(scannerTransaction.data, Base58.encodeNoCheck(data: wire))
    }

    func testMalformedSolanaSwapPayloadThrowsInsteadOfScanningDifferentBytes() {
        let transaction = makeTransaction(
            quote: .jupiter(
                makeSolanaQuote(base64: "not-base64"),
                fee: nil,
                platformFee: .zero,
                feeOnInput: false
            )
        )

        XCTAssertThrowsError(
            try SecurityScannerTransactionFactory().createSecurityScanner(transaction: transaction)
        ) { error in
            guard case SecurityScannerTransactionFactoryError.invalidBlockchainSpecific = error else {
                return XCTFail("Expected invalid Solana transaction data, got \(error)")
            }
        }
    }

    func testUnsupportedSolanaSwapProviderThrowsInsteadOfScanningPlaceholder() {
        let transaction = makeTransaction(
            quote: .oneinch(makeSolanaQuote(base64: Data([1]).base64EncodedString()), fee: nil)
        )

        XCTAssertThrowsError(
            try SecurityScannerTransactionFactory().createSecurityScanner(transaction: transaction)
        ) { error in
            guard case SecurityScannerTransactionFactoryError.swapProviderNotSupported = error else {
                return XCTFail("Expected unsupported Solana swap provider, got \(error)")
            }
        }
    }

    func testShortBase58SolanaAddressThrowsInsteadOfScanning() {
        let transaction = makeTransaction(
            quote: .jupiter(
                makeSolanaQuote(base64: Data([1]).base64EncodedString()),
                fee: nil,
                platformFee: .zero,
                feeOnInput: false
            ),
            fromAddress: "1"
        )

        XCTAssertThrowsError(
            try SecurityScannerTransactionFactory().createSecurityScanner(transaction: transaction)
        ) { error in
            guard case SecurityScannerTransactionFactoryError.invalidAddress("1") = error else {
                return XCTFail("Expected invalid Solana source address, got \(error)")
            }
        }
    }

    func testOneInchTokenSourceSwapScansApproveThenSwap() throws {
        let quote = makeEVMQuote(value: "0")
        let transaction = makeEVMTransaction(
            quote: .oneinch(quote, fee: nil),
            sourceIsNative: false,
            approval: .approve
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        assertScansSwap(scannerTransaction, quote: quote)
        try assertApproveLegs(scannerTransaction, spender: Self.evmRouter, amounts: [Self.approveAmount])
    }

    func testKyberSwapTokenSourceSwapScansApproveThenSwap() throws {
        let quote = makeEVMQuote(value: "0")
        let transaction = makeEVMTransaction(
            quote: .kyberswap(quote, fee: nil),
            sourceIsNative: false,
            approval: .approve
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        assertScansSwap(scannerTransaction, quote: quote)
        try assertApproveLegs(scannerTransaction, spender: Self.evmRouter, amounts: [Self.approveAmount])
    }

    func testLiFiTokenSourceSwapScansApproveThenSwap() throws {
        let quote = makeEVMQuote(value: "0")
        let transaction = makeEVMTransaction(
            quote: .lifi(quote, fee: nil, integratorFee: nil),
            sourceIsNative: false,
            approval: .approve
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        assertScansSwap(scannerTransaction, quote: quote)
        try assertApproveLegs(scannerTransaction, spender: Self.evmRouter, amounts: [Self.approveAmount])
    }

    func testSwapKitTokenSourceSwapApprovesTheDecidedSpender() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        guard case let .evm(tx) = response.tx, let spender = response.meta.approvalAddress else {
            return XCTFail("Expected a typed EVM transaction fixture with an approval address")
        }
        XCTAssertNotEqual(spender.lowercased(), tx.to.lowercased())
        let transaction = makeEVMTransaction(
            quote: .swapkit(response, fee: nil, subProvider: "ONEINCH"),
            sourceIsNative: false,
            approval: .approve,
            spender: spender
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        XCTAssertEqual(scannerTransaction.chain, .ethereum)
        XCTAssertEqual(scannerTransaction.type.rawValue, SecurityTransactionType.swap.rawValue)
        XCTAssertEqual(scannerTransaction.from, tx.from)
        XCTAssertEqual(scannerTransaction.to, tx.to)
        XCTAssertEqual(scannerTransaction.amount, BigInt(tx.value))
        XCTAssertEqual(scannerTransaction.data, tx.data)
        try assertApproveLegs(scannerTransaction, spender: spender, amounts: [Self.approveAmount])
    }

    func testResetThenApproveScansBothApproveLegsInOrder() throws {
        let quote = makeEVMQuote(value: "0")
        let transaction = makeEVMTransaction(
            quote: .oneinch(quote, fee: nil),
            sourceIsNative: false,
            approval: .resetThenApprove
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        assertScansSwap(scannerTransaction, quote: quote)
        try assertApproveLegs(scannerTransaction, spender: Self.evmRouter, amounts: [.zero, Self.approveAmount])
    }

    func testSufficientAllowanceScansTheSwapAlone() throws {
        let quote = makeEVMQuote(value: "0")
        let transaction = makeEVMTransaction(
            quote: .oneinch(quote, fee: nil),
            sourceIsNative: false,
            approval: .notRequired
        )

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        assertScansSwap(scannerTransaction, quote: quote)
        XCTAssertTrue(scannerTransaction.precedingTransactions.isEmpty)
    }

    func testNativeSourceSwapScansTheSwapAlone() throws {
        let quote = makeEVMQuote(value: "1000000000000000000")
        let transaction = makeEVMTransaction(quote: .oneinch(quote, fee: nil), sourceIsNative: true, approval: nil)

        let scannerTransaction = try SecurityScannerTransactionFactory()
            .createSecurityScanner(transaction: transaction)

        assertScansSwap(scannerTransaction, quote: quote)
        XCTAssertEqual(scannerTransaction.amount, BigInt("1000000000000000000"))
        XCTAssertTrue(scannerTransaction.precedingTransactions.isEmpty)
    }

    func testFactoryFailureEndsInVisibleNotScannedState() async {
        let service = FailingSecurityScannerService()
        let viewModel = SecurityScannerViewModel(service: service)
        let transaction = makeTransaction(
            quote: .jupiter(
                makeSolanaQuote(base64: Data([1]).base64EncodedString()),
                fee: nil,
                platformFee: .zero,
                feeOnInput: false
            )
        )

        await viewModel.scan(transaction: transaction)

        XCTAssertEqual(viewModel.state, .notScanned(provider: "blockaid"))
        XCTAssertEqual(service.scanCallCount, 0)
    }
}

private extension SecurityScannerSwapTests {
    func makeTransaction(
        quote: SwapQuote,
        fromAddress: String? = nil
    ) -> SwapTransaction {
        let sol = makeCoin(
            chain: .solana,
            ticker: "SOL",
            decimals: 9,
            isNative: true,
            address: fromAddress ?? Self.solanaAddress
        )
        let usdc = makeCoin(
            chain: .solana,
            ticker: "USDC",
            decimals: 6,
            isNative: false,
            address: Self.solanaAddress
        )
        return SwapTransaction(
            fromCoin: sol,
            toCoin: usdc,
            fromAmount: 1,
            kind: .market(quote),
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: sol,
            advancedSettings: .default
        )
    }

    func makeEVMTransaction(
        quote: SwapQuote,
        sourceIsNative: Bool,
        approval: ERC20ApprovalRequirement?,
        spender: String = SecurityScannerSwapTests.evmRouter
    ) -> SwapTransaction {
        let eth = makeCoin(
            chain: .ethereum,
            ticker: "ETH",
            decimals: 18,
            isNative: true,
            address: Self.evmAddress
        )
        let usdc = makeCoin(
            chain: .ethereum,
            ticker: "USDC",
            decimals: 6,
            isNative: false,
            address: Self.evmAddress
        )
        let fromCoin = sourceIsNative ? eth : usdc
        let transaction = SwapTransaction(
            fromCoin: fromCoin,
            toCoin: sourceIsNative ? usdc : eth,
            fromAmount: 1,
            kind: .market(quote),
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,
            advancedSettings: .default
        )
        guard let approval else {
            return transaction
        }
        let query = ERC20ApprovalQuery(coin: fromCoin, spender: spender, amount: Self.approveAmount)
        return transaction.with(approvalDecision: ERC20ApprovalDecision(query: query, requirement: approval))
    }

    func makeEVMQuote(value: String) -> EVMQuote {
        EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(
                from: Self.evmAddress,
                to: Self.evmRouter,
                data: "0x12aa3caf0000000000000000000000000000000000000000000000000000000000000001",
                value: value,
                gasPrice: "0",
                gas: 0
            )
        )
    }

    func assertScansSwap(
        _ scannerTransaction: SecurityScannerTransaction,
        quote: EVMQuote,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(scannerTransaction.chain, .ethereum, file: file, line: line)
        XCTAssertEqual(
            scannerTransaction.type.rawValue,
            SecurityTransactionType.swap.rawValue,
            file: file,
            line: line
        )
        XCTAssertEqual(scannerTransaction.from, quote.tx.from, file: file, line: line)
        XCTAssertEqual(scannerTransaction.to, quote.tx.to, file: file, line: line)
        XCTAssertEqual(scannerTransaction.amount, BigInt(quote.tx.value), file: file, line: line)
        XCTAssertEqual(scannerTransaction.data, quote.tx.data, file: file, line: line)
    }

    func assertApproveLegs(
        _ scannerTransaction: SecurityScannerTransaction,
        spender: String,
        amounts: [BigInt],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let legs = scannerTransaction.precedingTransactions
        XCTAssertEqual(legs.count, amounts.count, file: file, line: line)
        for (leg, amount) in zip(legs, amounts) {
            XCTAssertEqual(leg.chain, .ethereum, file: file, line: line)
            XCTAssertEqual(leg.type.rawValue, SecurityTransactionType.approval.rawValue, file: file, line: line)
            XCTAssertEqual(leg.from, Self.evmAddress, file: file, line: line)
            XCTAssertEqual(leg.to, "USDC-contract", file: file, line: line)
            XCTAssertEqual(leg.amount, .zero, file: file, line: line)
            XCTAssertEqual(
                leg.data,
                try EthereumFunction.approvalErc20Encoder(address: spender, amount: amount),
                file: file,
                line: line
            )
        }
    }

    func makeSolanaQuote(base64: String) -> EVMQuote {
        EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(
                from: "provider-from",
                to: "provider-to",
                data: base64,
                value: "0",
                gasPrice: "0",
                gas: 0
            )
        )
    }

    func makeCoin(
        chain: Chain,
        ticker: String,
        decimals: Int,
        isNative: Bool,
        address: String
    ) -> Coin {
        let meta = CoinMeta.make(
            chain: chain,
            ticker: ticker,
            decimals: decimals,
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: address, hexPublicKey: "")
    }

    static let solanaAddress = "So11111111111111111111111111111111111111112"
    static let evmAddress = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    static let evmRouter = "0x111111125421cA6dc452d289314280a0f8842A65"
    static let approveAmount = BigInt(1_000_000)
}

private final class FailingSecurityScannerService: SecurityScannerServiceProtocol {
    private(set) var scanCallCount = 0

    func scanTransaction(
        _ transaction: SecurityScannerTransaction
    ) async throws -> SecurityScannerResult {
        _ = transaction
        await Task.yield()
        scanCallCount += 1
        throw StubError.unused
    }

    func isSecurityServiceEnabled() -> Bool {
        true
    }

    func createSecurityScannerTransaction(
        transaction: SendTransaction,
        vault: Vault
    ) async throws -> SecurityScannerTransaction {
        _ = transaction
        _ = vault
        await Task.yield()
        throw StubError.unused
    }

    func createSecurityScannerTransaction(
        transaction: SwapTransaction
    ) async throws -> SecurityScannerTransaction {
        _ = transaction
        await Task.yield()
        throw StubError.factoryFailure
    }

    func createRecipientSecurityScannerTransaction(
        transaction: SwapTransaction
    ) throws -> SecurityScannerTransaction {
        _ = transaction
        throw StubError.unused
    }

    func getSupportedChainsByFeature() -> [SecurityScannerSupport] {
        [
            SecurityScannerSupport(
                provider: "blockaid",
                feature: [
                    SecurityScannerSupport.Feature(
                        chains: [.solana],
                        featureType: .scanTransaction
                    )
                ]
            )
        ]
    }

    private enum StubError: Error {
        case factoryFailure
        case unused
    }
}
