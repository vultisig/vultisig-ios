//
//  EVMSwapPreflightTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class EVMSwapPreflightTests: XCTestCase {
    private let walletAddress = "0xEe36b9c09FB9c17cCc5a6ac1BD30E152A5faB1c0"
    private let routerAddress = "0x1111111254EEB25477B68fb85Ed929f73A960582"

    func testEligibleProvidersBuildExactEthCall() async throws {
        for provider in [SwapProviderId.oneInch, .kyberSwap, .lifi] {
            var captured: EVMSwapPreflightCall?
            let preflight = EVMSwapPreflight { call in captured = call }
            let transactionFrom = provider == .kyberSwap ? "" : walletAddress

            try await preflight.validate(
                makePayload(provider: provider, transactionFrom: transactionFrom),
                localCoinAddress: walletAddress
            )

            XCTAssertEqual(
                captured,
                EVMSwapPreflightCall(
                    chain: .ethereum,
                    from: walletAddress,
                    to: routerAddress,
                    data: "0xdeadbeef",
                    valueHex: "0x38d7ea4c68000"
                )
            )
        }
    }

    func testRPCTransactionContainsOnlyExecutableFields() {
        let call = EVMSwapPreflightCall(
            chain: .ethereum,
            from: walletAddress,
            to: routerAddress,
            data: "0xdeadbeef",
            valueHex: "0x38d7ea4c68000"
        )

        XCTAssertEqual(
            EvmServiceStruct.swapSimulationTransaction(call),
            [
                "from": walletAddress,
                "to": routerAddress,
                "data": "0xdeadbeef",
                "value": "0x38d7ea4c68000"
            ]
        )
    }

    func testNonTargetProvidersDoNotCallRPC() async throws {
        for provider in [SwapProviderId.swapkit, .jupiter, .unknown("future")] {
            var callCount = 0
            let preflight = EVMSwapPreflight { _ in callCount += 1 }

            try await preflight.validate(makePayload(provider: provider), localCoinAddress: walletAddress)

            XCTAssertEqual(callCount, 0)
        }
    }

    func testApprovalBearingSwapDoesNotFalseFailAgainstPreApprovalState() async throws {
        var callCount = 0
        let preflight = EVMSwapPreflight { _ in callCount += 1 }

        try await preflight.validate(
            makePayload(provider: .oneInch, hasApproval: true),
            localCoinAddress: walletAddress
        )

        XCTAssertEqual(callCount, 0)
    }

    func testNonEVMGenericPayloadDoesNotCallRPC() async throws {
        var callCount = 0
        let preflight = EVMSwapPreflight { _ in callCount += 1 }

        try await preflight.validate(makePayload(provider: .lifi, chain: .solana), localCoinAddress: nil)

        XCTAssertEqual(callCount, 0)
    }

    func testMalformedTransactionFailsClosed() async {
        let payload = makePayload(provider: .oneInch, transactionFrom: routerAddress)
        do {
            try await EVMSwapPreflight().validate(payload, localCoinAddress: walletAddress)
            XCTFail("Expected a mismatched sender to fail before RPC or keysign")
        } catch let error as SwapError {
            XCTAssertEqual(error, .routeUnavailable)
        } catch {
            XCTFail("Expected SwapError.routeUnavailable, got \(error)")
        }
    }

    func testRevertMarkersCoverObservedAggregatorFailures() {
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: -32000, message: "execution reverted"))
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: -32000, message: "Insufficient output"))
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: 3, message: "Return amount is not enough"))
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: 3, message: "execution error"))
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: -32000, message: "0x08c379a0deadbeef"))
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: -32015, message: "0x4e487b71deadbeef"))
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: -32000, message: "0x275c273c"))
        XCTAssertTrue(EVMSwapPreflightError.isExecutionRevert(code: -32000, message: "0x"))
        XCTAssertFalse(EVMSwapPreflightError.isExecutionRevert(code: -32000, message: "0xnothexdata"))
        XCTAssertFalse(EVMSwapPreflightError.isExecutionRevert(code: -32000, message: "header not found"))
        XCTAssertFalse(EVMSwapPreflightError.isExecutionRevert(code: -32603, message: "upstream unavailable"))
    }

    func testKeysignViewModelBlocksRevertBeforeCeremony() async {
        let viewModel = KeysignViewModel()
        viewModel.keysignPayload = makePayload(provider: .kyberSwap)
        viewModel.evmSwapPreflight = StubPreflight(error: EVMSwapPreflightError.reverted(detail: "Insufficient output"))

        let allowed = await viewModel.validateEVMSwapPreflight()

        XCTAssertFalse(allowed)
        XCTAssertEqual(viewModel.status, .KeysignFailed)
        XCTAssertEqual(viewModel.keysignError, SwapError.slippageToleranceTooTight.localizedDescription)
    }

    func testKeysignViewModelFailsClosedOnTransportErrorWithoutCallingItSlippage() async {
        let viewModel = KeysignViewModel()
        viewModel.keysignPayload = makePayload(provider: .lifi)
        let transport = URLError(.notConnectedToInternet)
        viewModel.evmSwapPreflight = StubPreflight(error: transport)

        let allowed = await viewModel.validateEVMSwapPreflight()

        XCTAssertFalse(allowed)
        XCTAssertEqual(viewModel.status, .KeysignFailed)
        XCTAssertEqual(viewModel.keysignError, transport.localizedDescription)
        XCTAssertNotEqual(viewModel.keysignError, SwapError.slippageToleranceTooTight.localizedDescription)
    }

    func testLocalVaultSenderMismatchFailsClosed() async {
        let differentLocalAddress = "0x2222222254EEB25477B68fb85Ed929f73A960582"
        do {
            try await EVMSwapPreflight().validate(
                makePayload(provider: .oneInch),
                localCoinAddress: differentLocalAddress
            )
            XCTFail("Expected a local vault sender mismatch to fail before RPC or keysign")
        } catch let error as SwapError {
            XCTAssertEqual(error, .routeUnavailable)
        } catch {
            XCTFail("Expected SwapError.routeUnavailable, got \(error)")
        }
    }

    private func makePayload(
        provider: SwapProviderId,
        chain: Chain = .ethereum,
        hasApproval: Bool = false,
        transactionFrom: String? = nil
    ) -> KeysignPayload {
        let fromCoin = makeCoin(chain: chain, ticker: chain == .solana ? "SOL" : "ETH", isNative: true)
        let toCoin = makeCoin(chain: chain, ticker: "USDC", isNative: false)
        let quote = EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(
                from: transactionFrom ?? walletAddress,
                to: routerAddress,
                data: "0xdeadbeef",
                value: "1000000000000000",
                gasPrice: "1000000000",
                gas: 300_000
            )
        )
        let swap = GenericSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: BigInt(1_000_000_000_000_000),
            toAmountDecimal: 1,
            quote: quote,
            provider: provider
        )
        return KeysignPayload(
            coin: fromCoin,
            toAddress: routerAddress,
            toAmount: BigInt(1_000_000_000_000_000),
            chainSpecific: chain == .solana
                ? .Solana(recentBlockHash: "hash", priorityFee: 0, priorityLimit: 0, fromAddressPubKey: nil, toAddressPubKey: nil, hasProgramId: false)
                : .Ethereum(maxFeePerGasWei: 1_000_000_000, priorityFeeWei: 0, nonce: 1, gasLimit: 300_000),
            utxos: [],
            memo: nil,
            swapPayload: .generic(swap),
            approvePayload: hasApproval ? ERC20ApprovePayload(amount: swap.fromAmount, spender: routerAddress) : nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
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

    private func makeCoin(chain: Chain, ticker: String, isNative: Bool) -> Coin {
        let meta = CoinMeta.make(
            chain: chain,
            ticker: ticker,
            decimals: chain == .solana ? 9 : 18,
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: walletAddress, hexPublicKey: "")
    }
}

private struct StubPreflight: EVMSwapPreflightChecking {
    let error: Error

    func validate(_: KeysignPayload, localCoinAddress _: String?) async throws {
        await Task.yield()
        throw error
    }
}
