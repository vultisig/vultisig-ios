//
//  LimitSwapInteractorTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class LimitSwapInteractorTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var quoteService: MockLimitSwapQuoteService!
    private var interactor: DefaultLimitSwapInteractor!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        quoteService = MockLimitSwapQuoteService()
        interactor = DefaultLimitSwapInteractor(
            quoteService: quoteService,
            storage: LimitOrderStorageService()
        )
    }

    override func tearDown() async throws {
        interactor = nil
        quoteService = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - fetchMarketPrice

    func testFetchMarketPriceDelegatesToQuoteService() async throws {
        quoteService.marketPriceResult = .success(Decimal(string: "16.5")!)

        let price = try await interactor.fetchMarketPrice(
            sourceAsset: "BTC.BTC",
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            targetDecimals: 18,
            destinationAddress: "0xabc"
        )

        XCTAssertEqual(price, Decimal(string: "16.5")!)
        XCTAssertEqual(quoteService.marketPriceCallCount, 1)
    }

    func testFetchMarketPriceErrorPropagates() async {
        struct UpstreamError: Error, Equatable {}
        quoteService.marketPriceResult = .failure(UpstreamError())

        do {
            _ = try await interactor.fetchMarketPrice(
                sourceAsset: "BTC.BTC",
                sourceAmount: BigInt(1),
                sourceDecimals: 8,
                targetAsset: "ETH.ETH",
                targetDecimals: 18,
                destinationAddress: "0xabc"
            )
            XCTFail("Expected throw")
        } catch is UpstreamError {
            // expected
        } catch {
            XCTFail("Expected UpstreamError, got \(error)")
        }
    }

    // MARK: - validateAndBuildMemo

    func testValidateAndBuildMemoReturnsExpectedMemoForValidInput() throws {
        let inputs = makeValidInputs()
        let memo = try interactor.validateAndBuildMemo(inputs: inputs, sourceChainKind: .EVM)

        XCTAssertEqual(
            memo,
            "=<:ETH.ETH:0x1234567890abcdef1234567890abcdef12345678:1600000000/14400/0:vi:50"
        )
    }

    func testValidateAndBuildMemoThrowsValidationFailedOnInvalidInputs() {
        // Multiple problems: zero source amount + bad asset format + bad expiry
        let invalid = LimitSwapInputs(
            sourceAsset: "BTC",
            sourceAmount: 0,
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0xabc",
            targetPrice: 16,
            expiryHours: 7,
            affiliate: "vi",
            affiliateBps: "50"
        )

        XCTAssertThrowsError(
            try interactor.validateAndBuildMemo(inputs: invalid, sourceChainKind: .EVM)
        ) { error in
            guard case let LimitSwapInteractorError.validationFailed(errors) = error else {
                return XCTFail("Expected validationFailed, got \(error)")
            }
            XCTAssertTrue(errors.contains(.sourceAmountNotPositive))
            XCTAssertTrue(errors.contains(.sourceAssetMalformed("BTC")))
            XCTAssertTrue(errors.contains(.expiryHoursUnsupported(7)))
        }
    }

    func testValidateAndBuildMemoRejectsOversizedMemoOnUtxoSource() {
        // Same realistic referred memo from LimitSwapByteCapTests: 87B > 80B cap.
        let inputs = LimitSwapInputs(
            sourceAsset: "BTC.BTC",
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0x1234567890abcdef1234567890abcdef12345678",
            targetPrice: 16,
            expiryHours: 24,
            affiliate: "myref/vi",
            affiliateBps: "10/35"
        )

        XCTAssertThrowsError(
            try interactor.validateAndBuildMemo(inputs: inputs, sourceChainKind: .UTXO)
        ) { error in
            guard case let LimitSwapMemoError.memoExceedsByteLimit(actual, limit) = error else {
                return XCTFail("Expected memoExceedsByteLimit, got \(error)")
            }
            XCTAssertEqual(actual, 87)
            XCTAssertEqual(limit, 80)
        }
    }

    func testValidateAndBuildMemoAcceptsLongMemoOnNonUtxoSource() throws {
        // Same input as the previous test but EVM source — 87B fits the 250B cap.
        let inputs = LimitSwapInputs(
            sourceAsset: "ETH.ETH",
            sourceAmount: BigInt("1000000000000000000"),
            sourceDecimals: 18,
            targetAsset: "BTC.BTC",
            destAddress: "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            targetPrice: Decimal(string: "0.0625")!,
            expiryHours: 24,
            affiliate: "myref/vi",
            affiliateBps: "10/35"
        )

        let memo = try interactor.validateAndBuildMemo(inputs: inputs, sourceChainKind: .EVM)
        XCTAssertTrue(memo.hasPrefix("=<:BTC.BTC:"))
    }

    // MARK: - fetchInboundAddress

    func testFetchInboundAddressDelegatesToQuoteService() async throws {
        quoteService.inboundAddressResult = .success("bc1qexampleinbound000000000000000000000000")

        let addr = try await interactor.fetchInboundAddress(forChainSymbol: "BTC")

        XCTAssertEqual(addr, "bc1qexampleinbound000000000000000000000000")
        XCTAssertEqual(quoteService.inboundAddressCallCount, 1)
        XCTAssertEqual(quoteService.inboundAddressChainSymbols, ["BTC"])
    }

    func testFetchInboundAddressNilWhenChainHaltedOrUnknown() async throws {
        quoteService.inboundAddressResult = .success(nil)

        let addr = try await interactor.fetchInboundAddress(forChainSymbol: "LTC")

        XCTAssertNil(addr)
    }

    // MARK: - persistPlacedOrder

    func testPersistPlacedOrderInsertsThroughStorageService() throws {
        let record = LimitOrderRecord(
            inboundTxHash: "abc123",
            sourceAsset: "BTC.BTC",
            sourceAmount: "100000000",
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0xabc",
            targetPrice: 16,
            expiryBlocks: 14400
        )

        let order = try interactor.persistPlacedOrder(record, for: vault)

        XCTAssertEqual(vault.limitOrders.count, 1)
        XCTAssertEqual(order.inboundTxHash, "abc123")
    }

    // MARK: - Fixture builder

    private func makeValidInputs() -> LimitSwapInputs {
        LimitSwapInputs(
            sourceAsset: "BTC.BTC",
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0x1234567890abcdef1234567890abcdef12345678",
            targetPrice: 16,
            expiryHours: 24,
            affiliate: "vi",
            affiliateBps: "50"
        )
    }
}
