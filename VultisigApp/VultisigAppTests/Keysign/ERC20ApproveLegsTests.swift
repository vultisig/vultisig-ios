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
import WalletCore
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

    // MARK: - Approve legs

    func testWithoutResetBuildsOneApproveAtThePayloadNonce() throws {
        let legs = try THORChainSwaps().getPreSignedApproveInputData(
            approvePayload: approve(reset: false),
            keysignPayload: oneInchApproveSwapPayload(reset: false)
        )

        XCTAssertEqual(try legs.map(describe), [Leg(nonce: 7, amount: Self.amount)])
    }

    /// The SDK / Android vector: payload nonce 7 → `approve(0)`@7,
    /// `approve(amount)`@8, both to the same spender on the same token.
    func testResetBuildsZeroThenAmountOnConsecutiveNonces() throws {
        let legs = try THORChainSwaps().getPreSignedApproveInputData(
            approvePayload: approve(reset: true),
            keysignPayload: oneInchApproveSwapPayload(reset: true)
        )

        XCTAssertEqual(try legs.map(describe), [
            Leg(nonce: 7, amount: 0),
            Leg(nonce: 8, amount: Self.amount)
        ])
        let inputs = try legs.map { try EthereumSigningInput(serializedBytes: $0) }
        XCTAssertEqual(Set(inputs.map(\.toAddress)), [Self.usdt])
        XCTAssertEqual(Set(inputs.map(\.transaction.erc20Approve.spender)), [Self.spender])
    }

    /// Each leg pays with the payload's fee fields, exactly like the single
    /// approve did.
    func testEveryApproveLegUsesThePayloadFeeFields() throws {
        let single = try THORChainSwaps().getPreSignedApproveInputData(
            approvePayload: approve(reset: false),
            keysignPayload: oneInchApproveSwapPayload(reset: false)
        )
        let legs = try THORChainSwaps().getPreSignedApproveInputData(
            approvePayload: approve(reset: true),
            keysignPayload: oneInchApproveSwapPayload(reset: true)
        )
        let reference = try EthereumSigningInput(serializedBytes: XCTUnwrap(single.first))

        for leg in legs {
            let input = try EthereumSigningInput(serializedBytes: leg)
            XCTAssertEqual(input.chainID, reference.chainID)
            XCTAssertEqual(input.txMode, reference.txMode)
            XCTAssertEqual(input.gasLimit, reference.gasLimit)
            XCTAssertEqual(input.maxFeePerGas, reference.maxFeePerGas)
            XCTAssertEqual(input.maxInclusionFeePerGas, reference.maxInclusionFeePerGas)
        }
    }

    /// iOS writes the zero amount as empty bytes where Android writes `[0x00]`.
    /// Both have to hash to the same `approve(spender, 0)`: the calldata is the
    /// selector, the spender word and a zero word, built here by hand.
    func testZeroApproveHashesTheSameAsHandBuiltCalldata() throws {
        let legs = try THORChainSwaps().getPreSignedApproveInputData(
            approvePayload: approve(reset: true),
            keysignPayload: oneInchApproveSwapPayload(reset: true)
        )
        let reset = try EthereumSigningInput(serializedBytes: XCTUnwrap(legs.first))
        XCTAssertEqual(reset.transaction.erc20Approve.amount, Data())

        var androidEncoding = reset
        androidEncoding.transaction.erc20Approve.amount = Data([0x00])

        let spenderWord = Data(repeating: 0, count: 12) + (try XCTUnwrap(Data(hexString: Self.spender.stripHexPrefix())))
        let calldata = try XCTUnwrap(Data(hexString: "095ea7b3")) + spenderWord + Data(repeating: 0, count: 32)
        var handBuilt = reset
        handBuilt.transaction = .with {
            $0.contractGeneric = .with {
                $0.amount = Data()
                $0.data = calldata
            }
        }

        let resetHash = try preImageHash(reset)
        XCTAssertEqual(try preImageHash(androidEncoding), resetHash)
        XCTAssertEqual(try preImageHash(handBuilt), resetHash)
    }

    /// Control for the check above: the same hand-built calldata with the
    /// amount word filled in matches the `approve(amount)` leg, so the
    /// construction is sound rather than vacuously equal.
    func testAmountApproveHashesTheSameAsHandBuiltCalldata() throws {
        let legs = try THORChainSwaps().getPreSignedApproveInputData(
            approvePayload: approve(reset: true),
            keysignPayload: oneInchApproveSwapPayload(reset: true)
        )
        let amountLeg = try EthereumSigningInput(serializedBytes: XCTUnwrap(legs.last))

        let spenderWord = Data(repeating: 0, count: 12) + (try XCTUnwrap(Data(hexString: Self.spender.stripHexPrefix())))
        let amountBytes = Self.amount.magnitude.serialize()
        let amountWord = Data(repeating: 0, count: 32 - amountBytes.count) + amountBytes
        let calldata = try XCTUnwrap(Data(hexString: "095ea7b3")) + spenderWord + amountWord
        var handBuilt = amountLeg
        handBuilt.transaction = .with {
            $0.contractGeneric = .with {
                $0.amount = Data()
                $0.data = calldata
            }
        }

        XCTAssertEqual(try preImageHash(handBuilt), try preImageHash(amountLeg))
        XCTAssertNotEqual(try preImageHash(handBuilt), try preImageHash(
            EthereumSigningInput(serializedBytes: XCTUnwrap(legs.first))
        ))
    }

    /// A leg WalletCore cannot build has to fail with WalletCore's reason, not
    /// hand the ceremony an empty hash to sign.
    func testApproveLegThatFailsToBuildThrowsInsteadOfReturningAnEmptyHash() throws {
        let invalid = ERC20ApprovePayload(amount: Self.amount, spender: "not-an-address", resetAllowanceFirst: true)
        let payload = oneInchApproveSwapPayload(reset: true)

        // Precondition: WalletCore rejects this leg, and says so only in its output.
        let legs = try THORChainSwaps().getPreSignedApproveInputData(approvePayload: invalid, keysignPayload: payload)
        let output = try TxCompilerPreSigningOutput(
            serializedBytes: TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: XCTUnwrap(legs.first))
        )
        XCTAssertFalse(output.errorMessage.isEmpty)
        XCTAssertTrue(output.dataHash.isEmpty)

        XCTAssertThrowsError(
            try THORChainSwaps().getPreSignedApproveImageHash(approvePayload: invalid, keysignPayload: payload)
        ) { error in
            guard case HelperError.runtimeError(let message) = error else {
                return XCTFail("Expected HelperError.runtimeError, got \(error)")
            }
            XCTAssertEqual(message, output.errorMessage)
        }
    }

    // MARK: - The dependent transaction's nonce

    /// Generic route: the swap signs exactly as it would at payload nonce 9.
    func testResetMovesTheGenericSwapTwoNoncesOn() throws {
        let payload = oneInchApproveSwapPayload(reset: true)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(
            Array(messages.prefix(2)),
            try THORChainSwaps().getPreSignedApproveImageHash(approvePayload: approve(reset: true), keysignPayload: payload)
        )
        let atNine = oneInchApproveSwapPayload(reset: true, nonce: 9)
        XCTAssertEqual(
            messages.last,
            try OneInchSwaps().getPreSignedImageHash(payload: genericSwap(of: atNine), keysignPayload: atNine, nonceOffset: 0).first
        )
    }

    func testWithoutResetTheGenericSwapStaysOneNonceOn() throws {
        let payload = oneInchApproveSwapPayload(reset: false)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages.count, 2)
        let atEight = oneInchApproveSwapPayload(reset: false, nonce: 8)
        XCTAssertEqual(
            messages.last,
            try OneInchSwaps().getPreSignedImageHash(payload: genericSwap(of: atEight), keysignPayload: atEight, nonceOffset: 0).first
        )
    }

    /// THORChain-family route (Maya, ERC20 source through the router): the
    /// deposit signs exactly as it would at payload nonce 9.
    func testResetMovesTheRouterDepositTwoNoncesOn() throws {
        let payload = mayaRouterApproveSwapPayload(reset: true)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        XCTAssertEqual(messages.count, 3)
        let atNine = mayaRouterApproveSwapPayload(reset: true, nonce: 9)
        XCTAssertEqual(
            messages.last,
            try THORChainSwaps().getPreSignedImageHash(swapPayload: mayaSwap(of: atNine), keysignPayload: atNine, nonceOffset: 0).first
        )
        let depositInput = try EthereumSigningInput(serializedBytes: THORChainSwaps().getPreSignedInputData(
            swapPayload: mayaSwap(of: payload),
            keysignPayload: payload,
            nonceOffset: payload.approveNonceOffset
        ))
        XCTAssertEqual(BigUInt(depositInput.nonce), 9)
    }

    func testApproveNonceOffsetIsTheApproveLegCount() {
        XCTAssertEqual(oneInchApproveSwapPayload(reset: true).approveNonceOffset, 2)
        XCTAssertEqual(oneInchApproveSwapPayload(reset: false).approveNonceOffset, 1)
        XCTAssertEqual(mayaRouterApproveSwapPayload(reset: false, approve: false).approveNonceOffset, 0)
    }

    /// Regression: a three-leg swap once fell through the dispatcher to the
    /// per-chain helpers and came back as a plain ERC20 transfer.
    @MainActor
    func testThreeLegSwapSignsBothApproveLegsThenTheSwap() throws {
        let payload = oneInchApproveSwapPayload(reset: true)
        let signatures = try SigningGoldenSigner.signatures(
            forImageHashes: KeysignMessageFactory(payload: payload).getKeysignMessages(),
            curve: .secp256k1
        )
        let viewModel = KeysignViewModel()
        viewModel.signatures = signatures

        let signed = try viewModel.getSignedTransaction(keysignPayload: payload)

        guard case .regularWithApprove(let approves, let transaction) = signed else {
            return XCTFail("Expected approve legs then the swap, got \(signed)")
        }
        let expectedLegs = try THORChainSwaps().getSignedApproveTransactions(
            approvePayload: approve(reset: true),
            keysignPayload: payload,
            signatures: signatures
        )
        XCTAssertEqual(approves.map(\.rawTransaction), expectedLegs.map(\.rawTransaction))
        XCTAssertEqual(approves.count, 2)
        let expectedSwap = try OneInchSwaps().getSignedTransaction(
            payload: genericSwap(of: payload),
            keysignPayload: payload,
            signatures: signatures,
            nonceOffset: 2
        )
        XCTAssertEqual(transaction.rawTransaction, expectedSwap.rawTransaction)
        XCTAssertEqual(signed.approveTransactionHash, expectedLegs.last?.transactionHash)
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

    private static let mayaRouter = "0x700E97ef07219440487840Dc472E7120A7FF11F4"

    /// An ERC20 source swapped through the Maya router, which signs through
    /// the same `THORChainSwaps` leaf as a THORChain EVM swap without the
    /// factory's THORChain chain-id lookup.
    private func mayaRouterApproveSwapPayload(reset: Bool, nonce: Int64 = 7, approve withApprove: Bool = true) -> KeysignPayload {
        let usdt = SigningGoldenFactory.coin(
            chain: .ethereum, ticker: "USDT", decimals: 6,
            contractAddress: Self.usdt, isNativeToken: false, curve: .secp256k1
        )
        let cacao = SigningGoldenFactory.coin(chain: .mayaChain, ticker: "CACAO", decimals: 10, curve: .secp256k1)
        let swap = THORChainSwapPayload(
            fromAddress: usdt.address,
            fromCoin: usdt,
            toCoin: cacao,
            vaultAddress: SigningGoldenFactory.recipient(.ethereum),
            routerAddress: Self.mayaRouter,
            fromAmount: Self.amount,
            toAmountDecimal: 0,
            toAmountLimit: "0",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: 1_900_000_000,
            isAffiliate: false
        )
        return SigningGoldenFactory.payload(
            coin: usdt,
            toAddress: swap.vaultAddress,
            toAmount: Self.amount,
            chainSpecific: .Ethereum(
                maxFeePerGasWei: BigInt(1_000_000_000),
                priorityFeeWei: BigInt(100_000_000),
                nonce: nonce,
                gasLimit: BigInt(210_000)
            ),
            memo: "=:MAYA.CACAO:\(cacao.address)",
            swapPayload: .mayachain(swap),
            approvePayload: withApprove ? approve(reset: reset) : nil
        )
    }

    private enum FixtureError: Error {
        case unexpectedSwapPayload
    }

    private func genericSwap(of payload: KeysignPayload) throws -> GenericSwapPayload {
        guard case .generic(let swap) = payload.swapPayload else {
            throw FixtureError.unexpectedSwapPayload
        }
        return swap
    }

    private func mayaSwap(of payload: KeysignPayload) throws -> THORChainSwapPayload {
        guard case .mayachain(let swap) = payload.swapPayload else {
            throw FixtureError.unexpectedSwapPayload
        }
        return swap
    }

    private struct Leg: Equatable {
        let nonce: BigUInt
        let amount: BigInt
    }

    private func describe(_ inputData: Data) throws -> Leg {
        let input = try EthereumSigningInput(serializedBytes: inputData)
        return Leg(
            nonce: BigUInt(input.nonce),
            amount: BigInt(BigUInt(input.transaction.erc20Approve.amount))
        )
    }

    private func preImageHash(_ input: EthereumSigningInput) throws -> String {
        let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: try input.serializedData())
        let output = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(output.errorMessage.isEmpty, output.errorMessage)
        return output.dataHash.hexString
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
