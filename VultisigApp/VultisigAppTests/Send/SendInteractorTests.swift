//
//  SendInteractorTests.swift
//  VultisigAppTests
//
//  Contract tests for `SendInteractor`. The protocol exists so VM tests can
//  mock it; the bug fix this protocol enables — threading `feeMode` through
//  EVM fee math — is verified here against a stub implementation.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendInteractorTests: XCTestCase {

    func testFetchChainSpecificForwardsFeeMode() async throws {
        let stub = StubSendInteractor()
        _ = try? await stub.fetchChainSpecific(SendChainSpecificRequest(
            coin: .example,
            toAddress: "to",
            amount: BigInt(1),
            memo: nil,
            sendMaxAmount: false,
            isDeposit: false,
            transactionType: .unspecified,
            gasLimit: nil,
            feeMode: .fast,
            fromAddress: "from"
        ))
        XCTAssertEqual(stub.lastFeeMode, .fast)
    }

    func testCalculateEVMFeeForwardsFeeMode() async throws {
        let stub = StubSendInteractor()
        _ = try? await stub.calculateEVMFee(SendFeeEstimateRequest(chainSpecific: SendChainSpecificRequest(
            coin: .example,
            toAddress: "to",
            amount: BigInt(1),
            memo: nil,
            sendMaxAmount: false,
            isDeposit: false,
            transactionType: .unspecified,
            gasLimit: nil,
            feeMode: .safeLow,
            fromAddress: "addr",
        )))
        XCTAssertEqual(stub.lastFeeMode, .safeLow)
    }

    func testCalculateEVMFeeForwardsGasLimit() async throws {
        let stub = StubSendInteractor()
        _ = try? await stub.calculateEVMFee(SendFeeEstimateRequest(chainSpecific: SendChainSpecificRequest(
            coin: .example,
            toAddress: "to",
            amount: BigInt(1),
            memo: nil,
            sendMaxAmount: false,
            isDeposit: false,
            transactionType: .unspecified,
            gasLimit: BigInt(75_000),
            feeMode: .default,
            fromAddress: "addr",
        )))
        XCTAssertEqual(stub.lastGasLimit, BigInt(75_000))
    }

    func testFeeResultEqualityComparesBothFields() {
        let a = SendInteractorFeeResult(fee: BigInt(100), gas: BigInt(10))
        let b = SendInteractorFeeResult(fee: BigInt(100), gas: BigInt(10))
        let c = SendInteractorFeeResult(fee: BigInt(100), gas: BigInt(99))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - fetchGasAndFee dispatch

    func testFetchGasAndFeeForEVMUsesCalculateEVMFee() async throws {
        let mock = MockSendInteractor()
        mock.calculateEVMFeeStub = { _ in
            SendInteractorFeeResult(fee: BigInt(stringLiteral: "630000000000000"),
                                    gas: BigInt(stringLiteral: "30000000000"))
        }
        let eth = SendFormFixture.makeETH()

        let result = try await mock.fetchGasAndFee(
            coin: eth, toAddress: "to", amount: .zero, memo: nil,
            sendMaxAmount: false, isDeposit: false,
            transactionType: .unspecified, gasLimit: nil,
            feeMode: .fast, fromAddress: eth.address
        )

        XCTAssertEqual(mock.calculateEVMFeeCalls.count, 1, "EVM path must dispatch to calculateEVMFee")
        XCTAssertEqual(mock.calculateEVMFeeCalls.first?.feeMode, .fast, "feeMode threaded")
        XCTAssertNil(mock.calculateEVMFeeCalls.first?.gasLimit)
        XCTAssertEqual(result.fee, BigInt(stringLiteral: "630000000000000"))
        XCTAssertEqual(result.gas, BigInt(stringLiteral: "30000000000"))
    }

    func testFetchGasAndFeeForUTXOUsesChainSpecificFee() async throws {
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in
            .UTXO(byteFee: BigInt(50), sendMaxAmount: false)
        }
        let btc = SendFormFixture.makeBTC()

        let result = try await mock.fetchGasAndFee(
            coin: btc, toAddress: "bc1q...", amount: BigInt(1_000), memo: nil,
            sendMaxAmount: false, isDeposit: false,
            transactionType: .unspecified, gasLimit: nil,
            feeMode: .default, fromAddress: btc.address
        )

        XCTAssertTrue(mock.calculateEVMFeeCalls.isEmpty, "UTXO must not hit EVM fee path")
        // For UTXO, BlockChainSpecific.fee falls through to gas (= byteFee).
        XCTAssertEqual(result.fee, BigInt(50))
        XCTAssertEqual(result.gas, BigInt(50))
    }

    func testFetchGasAndFeeForCosmosUsesChainSpecificGas() async throws {
        let mock = MockSendInteractor()
        mock.fetchChainSpecificStub = { _ in
            .Cosmos(accountNumber: 0, sequence: 0, gas: UInt64(7_500),
                    transactionType: 0, ibcDenomTrace: nil)
        }
        let atom = SendFormFixture.makeATOM()

        let result = try await mock.fetchGasAndFee(
            coin: atom, toAddress: "cosmos1...", amount: BigInt(1_000), memo: nil,
            sendMaxAmount: false, isDeposit: false,
            transactionType: .unspecified, gasLimit: nil,
            feeMode: .default, fromAddress: atom.address
        )

        XCTAssertTrue(mock.calculateEVMFeeCalls.isEmpty)
        XCTAssertEqual(result.fee, BigInt(7_500))
        XCTAssertEqual(result.gas, BigInt(7_500))
    }

    func testFetchGasAndFeeThreadsFeeModeToChainSpecificFetch() async throws {
        let mock = MockSendInteractor()
        let atom = SendFormFixture.makeATOM()

        _ = try await mock.fetchGasAndFee(
            coin: atom, toAddress: "cosmos1...", amount: BigInt(1_000), memo: nil,
            sendMaxAmount: false, isDeposit: false,
            transactionType: .unspecified, gasLimit: nil,
            feeMode: .fast, fromAddress: atom.address
        )

        XCTAssertEqual(mock.fetchChainSpecificCalls.first?.feeMode, .fast,
                       "feeMode must thread through to fetchChainSpecific for non-EVM chains too")
    }
}

/// Minimal stub recording the `feeMode` it last received. Lets us assert the
/// bug fix at the protocol level without hitting real services.
private final class StubSendInteractor: SendInteractor {
    var lastFeeMode: FeeMode?
    var lastGasLimit: BigInt?

    func fetchChainSpecific(_ request: SendChainSpecificRequest) async throws -> BlockChainSpecific {
        lastGasLimit = request.gasLimit
        lastFeeMode = request.feeMode
        throw NSError(domain: "stub", code: 0)
    }

    func calculateEVMFee(_ request: SendFeeEstimateRequest) async throws -> SendInteractorFeeResult {
        lastGasLimit = request.gasLimit
        lastFeeMode = request.feeMode
        throw NSError(domain: "stub", code: 0)
    }

    func calculatePlanFee(tx: SendTransaction, chainSpecific: BlockChainSpecific) async throws -> BigInt {
        throw NSError(domain: "stub", code: 0)
    }

    func validateUtxosIfNeeded(coin: Coin) async throws {}

    func buildKeysignPayload(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        chainSpecific: BlockChainSpecific,
        wasmExecuteContractPayload: WasmExecuteContractPayload?,
        vault: Vault
    ) async throws -> KeysignPayload {
        throw NSError(domain: "stub", code: 0)
    }

    func updateBalance(for coin: Coin) async {}
}
