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
