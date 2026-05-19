//
//  QBTCClaimKeysignViewModelTests.swift
//  VultisigAppTests
//
//  Tests the new pure-orchestrator-driver view model used by
//  `QBTCClaimKeysignScreen`. Injects a stub orchestrator factory so
//  tests run without touching the relay, DKLS, or the proof service.
//

@testable import VultisigApp
import XCTest

@MainActor
final class QBTCClaimKeysignViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private static let validPubkeyHex = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    private func makeVault() -> Vault { Vault(name: "TestVault") }

    private func makeBtcCoin() -> Coin {
        let asset = CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", hexPublicKey: Self.validPubkeyHex)
    }

    private func makeQbtcCoin() -> Coin {
        let asset = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "qbtc",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "qbtc1abc", hexPublicKey: String(repeating: "ab", count: 32))
    }

    private static let utxos = [
        ClaimableUtxo(txid: String(repeating: "aa", count: 32), vout: 0, amount: 50_000, blockHeight: nil)
    ]

    private static let result = QBTCClaimRunResult(
        txHashHex: "DEADBEEF",
        totalSatsClaimed: 50_000
    )

    /// Builds an orchestrator that immediately publishes the supplied
    /// phase without doing any TSS / proof work. We achieve this by
    /// stubbing both DI closures so the run completes synchronously.
    private static func makeSuccessOrchestratorFactory() -> () -> QBTCClaimOrchestrator {
        {
            QBTCClaimOrchestrator(
                generateProof: { _ in
                    // Echo the locally-computed hashes back so the
                    // orchestrator's hash-mismatch guard passes.
                    let hashes = try QBTCClaimHashes.computeAll(
                        btcAddress: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                        // swiftlint:disable:next force_unwrapping
                        compressedPubkey: Data(hexString: validPubkeyHex)!,
                        qbtcAddress: "qbtc1abc",
                        chainId: QBTCClaimConfig.chainId
                    )
                    return ClaimProofResponse(
                        proof: String(repeating: "ff", count: 200),
                        messageHash: hashes.messageHash.toHexString(),
                        addressHash: hashes.addressHash.toHexString(),
                        qbtcAddressHash: hashes.qbtcAddressHash.toHexString(),
                        utxos: QBTCClaimKeysignViewModelTests.utxos.map { ClaimProofResponseUtxo(txid: $0.txid) },
                        claimerAddress: "qbtc1abc",
                        txHash: "DEADBEEF"
                    )
                },
                runBtcRound: { _ in
                    QBTCClaimBtcRoundResult(rHex: "01", sHex: "02")
                }
            )
        }
    }

    private static func makeFailingOrchestratorFactory(message: String) -> () -> QBTCClaimOrchestrator {
        {
            struct StubError: LocalizedError {
                let message: String
                var errorDescription: String? { message }
            }
            return QBTCClaimOrchestrator(
                generateProof: { _ in throw StubError(message: message) },
                runBtcRound: { _ in
                    QBTCClaimBtcRoundResult(rHex: "01", sHex: "02")
                }
            )
        }
    }

    // MARK: - Tests

    func testRunPublishesResultOnOrchestratorSuccess() async {
        let viewModel = QBTCClaimKeysignViewModel(
            vault: makeVault(),
            btcCoin: makeBtcCoin(),
            qbtcCoin: makeQbtcCoin(),
            selectedUtxos: Self.utxos,
            fastVaultPassword: "hunter2",
            session: nil,
            participants: [],
            orchestratorFactory: Self.makeSuccessOrchestratorFactory()
        )

        await viewModel.run()

        XCTAssertEqual(viewModel.runResult?.txHashHex, "DEADBEEF")
        XCTAssertFalse(viewModel.isError)
        XCTAssertNil(viewModel.errorTitle)
    }

    func testRunSurfacesErrorOnOrchestratorFailure() async {
        let viewModel = QBTCClaimKeysignViewModel(
            vault: makeVault(),
            btcCoin: makeBtcCoin(),
            qbtcCoin: makeQbtcCoin(),
            selectedUtxos: Self.utxos,
            fastVaultPassword: "hunter2",
            session: nil,
            participants: [],
            orchestratorFactory: Self.makeFailingOrchestratorFactory(message: "proof failed")
        )

        await viewModel.run()

        XCTAssertNil(viewModel.runResult)
        XCTAssertTrue(viewModel.isError)
        XCTAssertEqual(viewModel.errorTitle, "proof failed")
    }

    func testRetryClearsErrorAndRerunsTheRun() async {
        var callCount = 0
        let factory: () -> QBTCClaimOrchestrator = {
            callCount += 1
            if callCount == 1 {
                struct StubError: LocalizedError {
                    var errorDescription: String? { "first attempt failed" }
                }
                return QBTCClaimOrchestrator(
                    generateProof: { _ in throw StubError() },
                    runBtcRound: { _ in QBTCClaimBtcRoundResult(rHex: "01", sHex: "02") }
                )
            }
            return Self.makeSuccessOrchestratorFactory()()
        }

        let viewModel = QBTCClaimKeysignViewModel(
            vault: makeVault(),
            btcCoin: makeBtcCoin(),
            qbtcCoin: makeQbtcCoin(),
            selectedUtxos: Self.utxos,
            fastVaultPassword: "hunter2",
            session: nil,
            participants: [],
            orchestratorFactory: factory
        )

        await viewModel.run()
        XCTAssertTrue(viewModel.isError)

        await viewModel.retry()
        XCTAssertEqual(viewModel.runResult?.txHashHex, "DEADBEEF")
        XCTAssertFalse(viewModel.isError)
        XCTAssertNil(viewModel.errorTitle)
        XCTAssertEqual(callCount, 2)
    }
}
