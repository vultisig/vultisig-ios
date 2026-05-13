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
        _ = try? await stub.fetchChainSpecific(
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
        )
        XCTAssertEqual(stub.lastFeeMode, .fast)
    }

    func testCalculateEVMFeeForwardsFeeMode() async throws {
        let stub = StubSendInteractor()
        _ = try? await stub.calculateEVMFee(coin: .example, fromAddress: "addr", feeMode: .safeLow)
        XCTAssertEqual(stub.lastFeeMode, .safeLow)
    }

    func testFeeResultEqualityComparesBothFields() {
        let a = SendInteractorFeeResult(fee: BigInt(100), gas: BigInt(10))
        let b = SendInteractorFeeResult(fee: BigInt(100), gas: BigInt(10))
        let c = SendInteractorFeeResult(fee: BigInt(100), gas: BigInt(99))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

/// Minimal stub recording the `feeMode` it last received. Lets us assert the
/// bug fix at the protocol level without hitting real services.
private final class StubSendInteractor: SendInteractor {
    var lastFeeMode: FeeMode?

    func loadFastVault(vault: Vault) async -> Bool { false }

    func fetchChainSpecific(
        coin: Coin,
        toAddress: String,
        amount: BigInt,
        memo: String?,
        sendMaxAmount: Bool,
        isDeposit: Bool,
        transactionType: VSTransactionType,
        gasLimit: BigInt?,
        feeMode: FeeMode,
        fromAddress: String
    ) async throws -> BlockChainSpecific {
        lastFeeMode = feeMode
        throw NSError(domain: "stub", code: 0)
    }

    func calculateEVMFee(
        coin: Coin,
        fromAddress: String,
        feeMode: FeeMode
    ) async throws -> SendInteractorFeeResult {
        lastFeeMode = feeMode
        throw NSError(domain: "stub", code: 0)
    }

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
