//
//  ERC20ApproveLegsTests.swift
//  VultisigAppTests
//
//  The ERC20 approve legs every signer derives from a shared payload: how many
//  there are, the amount and nonce of each, and the nonce the dependent
//  transaction moves to. Co-signers rebuild this list independently, so a
//  device that derives a different one hashes a different message set and the
//  ceremony stalls instead of failing loudly.
//

import BigInt
import VultisigCommonData
import XCTest
@testable import VultisigApp

final class ERC20ApproveLegsTests: XCTestCase {

    // MARK: - Without the reset: today's messages, byte for byte

    /// Maya EVM route, signed by the `THORChainSwaps` leaf (router deposit).
    /// Hashes are the committed cross-platform corpus values.
    func testApproveSwapWithoutResetKeepsCommittedHashesOnMayaEvmRoute() throws {
        let payload = try fixturePayload(file: "mayaswap", name: "Swap ARB.USDC to CACAO")
        XCTAssertEqual(payload.approvePayload?.amount, BigInt(7_160_000))

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages, [
            "8fc58a393062400da51d6f16d97763008ebf807e8a4e03ae530faf94a7d593c7",
            "5abefbff1d10fc36063e075d2b92e1664129c2c04fc3db7d5bcf1dbcc0737acd"
        ])
    }

    /// Generic EVM route (1inch), signed by the `OneInchSwaps` leaf.
    func testApproveSwapWithoutResetKeepsCommittedHashesOnGenericRoute() throws {
        let payload = try fixturePayload(file: "arb", name: "Swap from ARB.ARB to ARB.ETH via 1inch")
        XCTAssertNotNil(payload.approvePayload)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages, [
            "cbec83beda9f91c7c6ce4283131e6eb4cd52dfa64dfa471efe38023ddc4a5a92",
            "d38e251e526ff07a695d2f91e4a7a1314c33e3b837ddcabf1ab67ae4ecbd12fa"
        ])
    }

    // MARK: - Payload

    func testLegAmountsFollowTheResetFlag() {
        XCTAssertEqual(approve(reset: false).legAmounts, [Self.amount])
        XCTAssertEqual(approve(reset: true).legAmounts, [BigInt(0), Self.amount])
    }

    func testResetFlagSurvivesKeysignPayloadProtoRoundTrip() throws {
        let payload = oneInchApproveSwapPayload(reset: true)

        let wire = try payload.mapToProtobuff().serializedData()
        let decoded = try KeysignPayload(proto: VSKeysignPayload(serializedBytes: wire))

        XCTAssertEqual(decoded.approvePayload, approve(reset: true))
    }

    /// Older senders never write the field. It has to read as false, and a
    /// payload without the reset has to serialize exactly as it did before the
    /// field existed, or every co-signer on an older build sees different bytes.
    func testUnsetResetFlagDecodesFalseAndAddsNoBytes() throws {
        let legacy = VSErc20ApprovePayload.with {
            $0.amount = "5000000"
            $0.spender = Self.spender
        }

        let decoded = ERC20ApprovePayload(proto: legacy)

        XCTAssertFalse(decoded.resetAllowanceFirst)
        XCTAssertEqual(try decoded.mapToProtobuff().serializedData(), try legacy.serializedData())
    }

    func testCodableWithoutResetKeyDecodesFalse() throws {
        let encoded = try JSONEncoder().encode(approve(reset: true))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object.removeValue(forKey: "resetAllowanceFirst") as? Bool, true)
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ERC20ApprovePayload.self, from: legacy)

        XCTAssertEqual(decoded, approve(reset: false))
    }

    func testCodableRoundTripKeepsResetFlag() throws {
        let encoded = try JSONEncoder().encode(approve(reset: true))

        XCTAssertEqual(try JSONDecoder().decode(ERC20ApprovePayload.self, from: encoded), approve(reset: true))
    }

    // MARK: - Signed transaction assembly

    func testSignedTransactionTypeFromEmptyListIsNil() {
        XCTAssertNil(SignedTransactionType(transactions: []))
    }

    func testSignedTransactionTypeFromOneResultIsRegular() throws {
        let type = try XCTUnwrap(SignedTransactionType(transactions: [signed("swap")]))

        guard case .regular(let transaction) = type else {
            return XCTFail("Expected .regular, got \(type)")
        }
        XCTAssertEqual(transaction.transactionHash, "0xswap")
        XCTAssertNil(type.approveTransactionHash)
    }

    func testSignedTransactionTypeFromTwoResultsIsOneApproveThenTransaction() throws {
        let type = try XCTUnwrap(SignedTransactionType(transactions: [signed("approve"), signed("swap")]))

        guard case .regularWithApprove(let approves, let transaction) = type else {
            return XCTFail("Expected .regularWithApprove, got \(type)")
        }
        XCTAssertEqual(approves.map(\.transactionHash), ["0xapprove"])
        XCTAssertEqual(transaction.transactionHash, "0xswap")
        XCTAssertEqual(type.transactionHash, "0xswap")
        XCTAssertEqual(type.approveTransactionHash, "0xapprove")
    }

    /// Three results used to return nil, which sent the dispatcher on to the
    /// per-chain helpers and re-built the swap as a plain token transfer.
    func testSignedTransactionTypeFromThreeResultsKeepsBothApproveLegsInOrder() throws {
        let type = try XCTUnwrap(SignedTransactionType(
            transactions: [signed("reset"), signed("approve"), signed("swap")]
        ))

        guard case .regularWithApprove(let approves, let transaction) = type else {
            return XCTFail("Expected .regularWithApprove, got \(type)")
        }
        XCTAssertEqual(approves.map(\.transactionHash), ["0xreset", "0xapprove"])
        XCTAssertEqual(transaction.transactionHash, "0xswap")
        // The approve the user is shown is the one that grants the allowance.
        XCTAssertEqual(type.approveTransactionHash, "0xapprove")
    }

    /// A co-signer that loses the broadcast race is told "already known" and
    /// takes its hashes from the signed legs instead of the node.
    @MainActor
    func testAlreadyKnownBroadcastReportsTheApproveAmountLeg() async {
        let viewModel = KeysignViewModel()
        viewModel.keysignPayload = oneInchApproveSwapPayload(reset: true)

        await viewModel.handleBroadcastError(
            error: RpcEvmServiceError.rpcError(code: -32000, message: "already known"),
            transactionType: threeLegType()
        )

        XCTAssertEqual(viewModel.txid, "0xswap")
        XCTAssertEqual(viewModel.approveTxid, "0xapprove")
    }

    @MainActor
    func testBroadcastConfirmedOnChainAfterCancellationReportsTheApproveAmountLeg() async {
        let viewModel = KeysignViewModel()
        viewModel.keysignPayload = oneInchApproveSwapPayload(reset: true)
        viewModel.transactionStatusChecker = ConfirmedStatusChecker()

        await viewModel.handleBroadcastError(error: CancellationError(), transactionType: threeLegType())

        XCTAssertEqual(viewModel.txid, "0xswap")
        XCTAssertEqual(viewModel.approveTxid, "0xapprove")
    }

    // MARK: - Fixtures

    private func signed(_ name: String) -> SignedTransactionResult {
        SignedTransactionResult(rawTransaction: "raw-\(name)", transactionHash: "0x\(name)")
    }

    private func threeLegType() -> SignedTransactionType {
        .regularWithApprove(approves: [signed("reset"), signed("approve")], transaction: signed("swap"))
    }

    private struct ConfirmedStatusChecker: TransactionStatusChecking {
        func checkTransactionStatus(txHash _: String, chain _: Chain) async throws -> TransactionStatusResult {
            await Task.yield()
            return TransactionStatusResult(status: .confirmed, blockNumber: 1, confirmations: 1)
        }
    }

    /// The SDK / Android reference vector: USDT to the 1inch v6 router,
    /// payload nonce 7.
    private static let usdt = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
    private static let spender = "0x111111125421ca6dc452d289314280a0f8842a65"
    private static let amount = BigInt(5_000_000)

    private func approve(reset: Bool) -> ERC20ApprovePayload {
        ERC20ApprovePayload(amount: Self.amount, spender: Self.spender, resetAllowanceFirst: reset)
    }

    /// Coins derive from the golden signer's key, so the golden signatures verify.
    private func oneInchApproveSwapPayload(reset: Bool, nonce: Int64 = 7) -> KeysignPayload {
        let usdt = SigningGoldenFactory.coin(
            chain: .ethereum, ticker: "USDT", decimals: 6,
            contractAddress: Self.usdt, isNativeToken: false, curve: .secp256k1
        )
        let eth = SigningGoldenFactory.coin(chain: .ethereum, ticker: "ETH", decimals: 18, curve: .secp256k1)
        let quote = EVMQuote(
            dstAmount: "1",
            tx: EVMQuote.Transaction(
                from: usdt.address, to: Self.spender, data: "0xabcdef",
                value: "0", gasPrice: "0", gas: 0
            )
        )
        let swap = GenericSwapPayload(
            fromCoin: usdt, toCoin: eth, fromAmount: Self.amount,
            toAmountDecimal: 0, quote: quote, provider: .oneInch
        )
        return SigningGoldenFactory.payload(
            coin: usdt,
            toAddress: Self.spender,
            toAmount: Self.amount,
            chainSpecific: .Ethereum(
                maxFeePerGasWei: BigInt(1_000_000_000),
                priorityFeeWei: BigInt(100_000_000),
                nonce: nonce,
                gasLimit: BigInt(210_000)
            ),
            swapPayload: .generic(swap),
            approvePayload: approve(reset: reset)
        )
    }

    private func fixturePayload(file: String, name: String) throws -> KeysignPayload {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(
            bundle.url(forResource: file, withExtension: "json", subdirectory: "TestData"),
            "Missing TestData/\(file).json in the test bundle"
        )
        let cases = try JSONDecoder().decode([ChainHelperTestCase].self, from: Data(contentsOf: url))
        let testCase = try XCTUnwrap(cases.first { $0.name == name }, "No case named \(name) in \(file).json")
        return try KeysignPayload(proto: testCase.keysignPayload)
    }
}
