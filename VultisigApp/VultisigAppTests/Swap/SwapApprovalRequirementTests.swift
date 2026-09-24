//
//  SwapApprovalRequirementTests.swift
//  VultisigAppTests
//
//  The approval is read once, on the way into Verify, and carried: Verify's
//  consent and the signed payload both come from that one decision, and the
//  payload builders never read the chain again. They refuse a decision made
//  for a different spend rather than sign or skip an approve on it.
//  `ERC20ApprovalResolverTests` covers how the decision is read.
//

import BigInt
import WalletCore
import XCTest
@testable import VultisigApp

@MainActor
final class SwapApprovalRequirementTests: XCTestCase {

    private static let usdtContract = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
    private static let router = "0x111111125421cA6dc452d289314280a0f8842A65"
    /// 2 USDT at 6 decimals.
    private static let amount = BigInt(2_000_000)

    // MARK: - Read once, carried

    /// The hand-off reads the approval; building the payload afterwards adds
    /// no read of its own.
    func testApprovalIsReadOnceAtTheHandOffAndCarriedIntoThePayload() async throws {
        let resolver = StubERC20ApprovalResolver(.resetThenApprove)
        let transaction = oneInchTransaction()

        let decision = try await makeInteractor(resolver).resolveApproval(for: transaction, vault: makeVault())
        let payload = try await build(transaction.with(approvalDecision: decision))

        XCTAssertEqual(resolver.queries, [ERC20ApprovalQuery(
            chain: .ethereum,
            token: Self.usdtContract,
            owner: transaction.fromCoin.address,
            spender: Self.router,
            amount: Self.amount
        )])
        XCTAssertEqual(
            payload.approvePayload,
            ERC20ApprovePayload(amount: Self.amount, spender: Self.router, resetAllowanceFirst: true)
        )
    }

    func testNativeSourceReadsNoAllowanceAndCarriesNoDecision() async throws {
        let eth = SigningGoldenFactory.coin(chain: .ethereum, ticker: "ETH", decimals: 18, curve: .secp256k1)
        let transaction = makeTransaction(from: eth, quote: .oneinch(oneInchQuote(from: eth), fee: nil))

        let decision = try await makeInteractor(UnexpectedERC20ApprovalResolver()).resolveApproval(for: transaction, vault: makeVault())
        let payload = try await build(transaction.with(approvalDecision: decision))

        XCTAssertNil(decision)
        XCTAssertFalse(transaction.with(approvalDecision: decision).signsApprove)
        XCTAssertNil(payload.approvePayload)
    }

    func testFailedReadAtTheHandOffPropagates() async {
        let failure = RpcServiceError.rpcError(code: -32005, message: "rate limit exceeded")

        do {
            _ = try await makeInteractor(StubERC20ApprovalResolver(error: failure)).resolveApproval(
                for: oneInchTransaction(),
                vault: makeVault()
            )
            XCTFail("A failed allowance read must not produce a decision")
        } catch let RpcServiceError.rpcError(code, message) {
            XCTAssertEqual(code, -32005)
            XCTAssertEqual(message, "rate limit exceeded")
        } catch {
            XCTFail("Expected the resolver's error, got \(error)")
        }
    }

    func testSwapKitDecisionIsReadForItsApprovalAddress() async throws {
        let resolver = StubERC20ApprovalResolver(.approve)
        let response = try SwapKitFixtureLoader.decode(SwapKitSwapResponse.self, from: "v3-erc20-erc20-swap")
        let transaction = makeTransaction(quote: .swapkit(response, fee: nil, subProvider: ""))

        let decision = try await makeInteractor(resolver).resolveApproval(for: transaction, vault: makeVault())
        let payload = try await build(transaction.with(approvalDecision: decision))

        XCTAssertEqual(resolver.queries.map(\.spender), ["0x6C0AD82f9721A6dc986381d19338601a2E6370e5"])
        XCTAssertEqual(payload.approvePayload?.spender, "0x6C0AD82f9721A6dc986381d19338601a2E6370e5")
    }

    // MARK: - The carried requirement becomes the payload

    func testCarriedNotRequiredBuildsTheSwapWithoutApprove() async throws {
        let payload = try await build(oneInchTransaction().withApprovalDecided(.notRequired))

        XCTAssertNil(payload.approvePayload)
        XCTAssertEqual(payload.approveNonceOffset, 0)
        guard case .generic = payload.swapPayload else {
            return XCTFail("The swap still has to be signed")
        }
    }

    func testCarriedApproveKeepsTheSingleApprove() async throws {
        let payload = try await build(oneInchTransaction().withApprovalDecided(.approve))

        XCTAssertEqual(payload.approvePayload, ERC20ApprovePayload(amount: Self.amount, spender: Self.router))
    }

    func testCarriedResetAsksEverySignerToResetFirst() async throws {
        let payload = try await build(oneInchTransaction().withApprovalDecided(.resetThenApprove))

        XCTAssertEqual(
            payload.approvePayload,
            ERC20ApprovePayload(amount: Self.amount, spender: Self.router, resetAllowanceFirst: true)
        )
    }

    /// A token swap through THORChain deposits via the router, so the router is
    /// the spender, and it still deposits through the router when no approve
    /// is needed.
    func testThorchainTokenSwapWithoutApproveStillDepositsThroughTheRouter() async throws {
        let thorRouter = "0xD37BbE5744D730a1d98d8DC97c42F0Ca46aD7146"
        let transaction = makeTransaction(quote: .thorchain(thorQuote(router: thorRouter))).withApprovalDecided(.notRequired)

        let payload = try await build(transaction)

        XCTAssertEqual(transaction.approvalDecision?.query.spender, thorRouter)
        XCTAssertNil(payload.approvePayload)
        XCTAssertEqual(payload.toAddress, thorRouter)
        guard case .thorchain = payload.swapPayload else {
            return XCTFail("The router deposit still rides the swap payload")
        }
    }

    // MARK: - Signing refuses a decision it cannot trust

    func testMissingDecisionIsRefused() async {
        await assertStale { _ = try await self.build(self.oneInchTransaction()) }
    }

    /// The quote now approves another contract (a refreshed route, a rotated
    /// router) than the one the allowance was read for.
    func testDecisionForAnotherSpenderIsRefused() async {
        let decidedForOldRouter = oneInchTransaction().withApprovalDecided(.notRequired)
        let otherRouterQuote = EVMQuote(
            dstAmount: "1",
            tx: EVMQuote.Transaction(
                from: decidedForOldRouter.fromCoin.address, to: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
                data: "0xabcdef", value: "0", gasPrice: "0", gas: 0
            )
        )
        let requoted = decidedForOldRouter.with(quote: .oneinch(otherRouterQuote, fee: nil))

        await assertStale { _ = try await self.build(requoted) }
    }

    // MARK: - End to end through the signers' factory

    /// Payload nonce 7 with the carried reset: `approve(0)`@7,
    /// `approve(amount)`@8, swap@9, which is what every co-signer derives from
    /// the same payload.
    func testCarriedResetSignsZeroApproveAmountApproveAndSwapOnConsecutiveNonces() async throws {
        let payload = try await build(oneInchTransaction().withApprovalDecided(.resetThenApprove), nonce: 7)
        let approve = try XCTUnwrap(payload.approvePayload)

        let messages = try KeysignMessageFactory(payload: payload).getKeysignMessages()

        let approveLegs = try THORChainSwaps()
            .getPreSignedApproveInputData(approvePayload: approve, keysignPayload: payload)
            .map { try EthereumSigningInput(serializedBytes: $0) }
        XCTAssertEqual(approveLegs.map { BigUInt($0.nonce) }, [7, 8])
        XCTAssertEqual(approveLegs.map { BigUInt($0.transaction.erc20Approve.amount) }, [0, BigUInt(Self.amount)])
        XCTAssertEqual(Set(approveLegs.map(\.transaction.erc20Approve.spender)), [Self.router])
        // The same swap built at payload nonce 9 with no approve ahead of it.
        let atNine = try await build(oneInchTransaction().withApprovalDecided(.notRequired), nonce: 9)
        guard case let .generic(swapAtNine) = atNine.swapPayload else {
            return XCTFail("Expected a generic swap payload")
        }
        let swapAtNineHashes = try OneInchSwaps().getPreSignedImageHash(payload: swapAtNine, keysignPayload: atNine, nonceOffset: 0)
        XCTAssertEqual(messages, try approveLegs.map(preImageHash) + swapAtNineHashes)
    }

    // MARK: - Verify consent follows the carried decision

    func testConsentIsNotAskedWhenNoApproveIsSigned() {
        let viewModel = SwapVerifyViewModel(transaction: oneInchTransaction().withApprovalDecided(.notRequired))
        viewModel.isAmountCorrect = true
        viewModel.isFeeCorrect = true

        XCTAssertFalse(viewModel.transaction.signsApprove)
        XCTAssertTrue(viewModel.canStartSigning, "No approve is signed, so there is nothing to consent to")
    }

    func testConsentGatesSigningWhenAnApproveIsSigned() {
        for requirement in [ERC20ApprovalRequirement.approve, .resetThenApprove] {
            let viewModel = SwapVerifyViewModel(transaction: oneInchTransaction().withApprovalDecided(requirement))
            viewModel.isAmountCorrect = true
            viewModel.isFeeCorrect = true

            XCTAssertTrue(viewModel.transaction.signsApprove, "\(requirement)")
            XCTAssertFalse(viewModel.canStartSigning, "\(requirement): consent is still missing")
            viewModel.isApproveCorrect = true
            XCTAssertTrue(viewModel.canStartSigning, "\(requirement)")
        }
    }

    // MARK: - A Verify refresh that moves the spender reads it again

    func testRefreshToAnotherSpenderReadsTheApprovalAgainAndResetsConsent() async {
        let otherRouter = "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5"
        let original = fundedOneInchTransaction().withApprovalDecided(.approve)
        let interactor = RefreshingApprovalStub(
            refreshed: .oneinch(oneInchQuote(from: original.fromCoin, router: otherRouter), fee: nil),
            requirement: .resetThenApprove
        )
        let viewModel = SwapVerifyViewModel(transaction: original, interactor: interactor)
        viewModel.isApproveCorrect = true

        await viewModel.refreshData(vault: makeVault())

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(interactor.resolveApprovalCallCount, 1)
        XCTAssertEqual(viewModel.transaction.approvalDecision?.query.spender, otherRouter)
        XCTAssertEqual(viewModel.transaction.approvalDecision?.requirement, .resetThenApprove)
        XCTAssertFalse(viewModel.isApproveCorrect, "Consent for the old spender's approve does not carry over")
    }

    func testRefreshToTheSameSpenderKeepsTheDecision() async {
        let original = fundedOneInchTransaction().withApprovalDecided(.approve)
        let interactor = RefreshingApprovalStub(
            refreshed: .oneinch(oneInchQuote(from: original.fromCoin, dstAmount: "2"), fee: nil),
            requirement: .notRequired
        )
        let viewModel = SwapVerifyViewModel(transaction: original, interactor: interactor)
        viewModel.isApproveCorrect = true

        await viewModel.refreshData(vault: makeVault())

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(interactor.resolveApprovalCallCount, 0, "The same spend is not read again")
        XCTAssertEqual(viewModel.transaction.approvalDecision, original.approvalDecision)
        XCTAssertTrue(viewModel.isApproveCorrect)
    }

    // MARK: - Router deposits (LP add, SECURE+ mint)

    func testRouterDepositWithoutApproveKeepsTheDeposit() async throws {
        let tx = usdcLPAdd()

        let (swapPayload, approvePayload) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
            tx: tx,
            approvalDecision: try lpDecision(tx, .notRequired),
            thorchainService: inboundService()
        )

        XCTAssertNotNil(swapPayload, "The deposit is still the router call")
        XCTAssertNil(approvePayload)
    }

    func testRouterDepositOverAStaleAllowanceResetsFirst() async throws {
        let tx = usdcLPAdd()

        let (_, approvePayload) = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
            tx: tx,
            approvalDecision: try lpDecision(tx, .resetThenApprove),
            thorchainService: inboundService()
        )

        XCTAssertEqual(
            approvePayload,
            ERC20ApprovePayload(amount: tx.amountInRaw, spender: AddLPFixture.ethRouter, resetAllowanceFirst: true)
        )
    }

    func testRouterDepositWithoutADecisionIsRefused() async {
        await assertStale {
            _ = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
                tx: self.usdcLPAdd(),
                approvalDecision: nil,
                thorchainService: self.inboundService()
            )
        }
    }

    /// The amount changed after the approval was read for it.
    func testRouterDepositDecidedForAnotherAmountIsRefused() async throws {
        let decided = try lpDecision(usdcLPAdd(), .notRequired)
        let larger = usdcLPAdd().copy(amount: "20")

        await assertStale {
            _ = try await ThorchainRouterDepositBuilder.synthesizeRouterDeposit(
                tx: larger,
                approvalDecision: decided,
                thorchainService: self.inboundService()
            )
        }
    }

    // MARK: - Helpers

    private func build(_ transaction: SwapTransaction, nonce: Int64 = 7) async throws -> KeysignPayload {
        try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: .Ethereum(
                maxFeePerGasWei: BigInt(1_000_000_000),
                priorityFeeWei: BigInt(100_000_000),
                nonce: nonce,
                gasLimit: BigInt(210_000)
            ),
            vault: makeVault(),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeInteractor(_ resolver: ERC20ApprovalResolving) -> DefaultSwapInteractor {
        DefaultSwapInteractor(
            quote: SwapService.shared,
            blockchain: BlockChainService.shared,
            balance: BalanceService.shared,
            fastVault: FastVaultService.shared,
            tierResolver: VultTierService(),
            approvalResolver: resolver
        )
    }

    private func lpDecision(_ tx: SendTransaction, _ requirement: ERC20ApprovalRequirement) throws -> ERC20ApprovalDecision {
        ERC20ApprovalDecision(query: try XCTUnwrap(ThorchainRouterDepositBuilder.approvalQuery(for: tx)), requirement: requirement)
    }

    private func usdt() -> Coin {
        SigningGoldenFactory.coin(
            chain: .ethereum, ticker: "USDT", decimals: 6,
            contractAddress: Self.usdtContract, isNativeToken: false, curve: .secp256k1
        )
    }

    private func oneInchTransaction() -> SwapTransaction {
        let source = usdt()
        return makeTransaction(from: source, quote: .oneinch(oneInchQuote(from: source), fee: nil))
    }

    private func oneInchQuote(from source: Coin, router: String? = nil, dstAmount: String = "1") -> EVMQuote {
        EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: source.address, to: router ?? Self.router, data: "0xabcdef",
                value: "0", gasPrice: "0", gas: 0
            )
        )
    }

    /// Enough USDT to send and ETH to pay for gas, so a refresh gets past its
    /// balance check.
    private func fundedOneInchTransaction() -> SwapTransaction {
        let source = usdt()
        source.rawBalance = "5000000"
        let eth = SigningGoldenFactory.coin(chain: .ethereum, ticker: "ETH", decimals: 18, curve: .secp256k1)
        eth.rawBalance = "1000000000000000000"
        return SwapTransaction(
            fromCoin: source,
            toCoin: eth,
            fromAmount: 2,
            kind: .market(.oneinch(oneInchQuote(from: source), fee: nil)),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,
            advancedSettings: .default
        )
    }

    private func makeTransaction(from source: Coin? = nil, quote: SwapQuote) -> SwapTransaction {
        let eth = SigningGoldenFactory.coin(chain: .ethereum, ticker: "ETH", decimals: 18, curve: .secp256k1)
        return SwapTransaction(
            fromCoin: source ?? usdt(),
            toCoin: eth,
            fromAmount: 2,
            kind: .market(quote),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: eth,
            advancedSettings: .default
        )
    }

    private func thorQuote(router: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "100000000",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "ETH.ETH", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: "0x6b175474e89094c44da98b954eedeac495271d0f",
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "=:ETH.ETH:0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF:0/1/0",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            totalSwapSeconds: nil,
            warning: "",
            router: router,
            maxStreamingQuantity: nil
        )
    }

    private func makeVault() -> Vault {
        Vault(
            name: "Approval Test Vault",
            signers: [],
            pubKeyECDSA: "approval-test-pub-ecdsa",
            pubKeyEdDSA: "approval-test-pub-eddsa",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func usdcLPAdd() -> SendTransaction {
        AddLPTransactionBuilder(
            coin: AddLPFixture.usdc(),
            amount: "10",
            poolName: AddLPFixture.usdcPool,
            pairedAddress: AddLPFixture.thorAddress,
            sendMaxAmount: false,
            toAddress: AddLPFixture.ethRouter
        ).buildSendTransaction(vault: .example)
    }

    private func inboundService() -> ThorchainService {
        let json = """
        [{"chain":"ETH","address":"\(AddLPFixture.ethVault)","router":"\(AddLPFixture.ethRouter)","halted":false,
          "global_trading_paused":false,"chain_trading_paused":false,"chain_lp_actions_paused":false,
          "gas_rate":"1","gas_rate_units":"gwei"}]
        """
        return ThorchainService(httpClient: ApprovalInboundStubClient(inboundBody: Data(json.utf8)))
    }

    private func assertStale(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected the decision to be refused", file: file, line: line)
        } catch ERC20ApprovalDecisionError.stale {
        } catch {
            XCTFail("Expected ERC20ApprovalDecisionError.stale, got \(error)", file: file, line: line)
        }
    }

    private func preImageHash(_ input: EthereumSigningInput) throws -> String {
        let hashes = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: try input.serializedData())
        let output = try TxCompilerPreSigningOutput(serializedBytes: hashes)
        XCTAssertTrue(output.errorMessage.isEmpty, output.errorMessage)
        return output.dataHash.hexString
    }
}

/// Serves one canned body on `/thorchain/inbound_addresses` and 501s anything else.
private actor ApprovalInboundStubClient: HTTPClientProtocol {
    private let inboundBody: Data

    init(inboundBody: Data) {
        self.inboundBody = inboundBody
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        guard target.path == "/thorchain/inbound_addresses" else {
            throw HTTPError.statusCode(501, nil)
        }
        let url = target.baseURL.appendingPathComponent(target.path)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw HTTPError.invalidResponse
        }
        return HTTPResponse(data: inboundBody, response: response)
    }
}

// swiftlint:disable async_without_await unused_parameter
/// Refreshes to one fixed quote and answers every approval read with one
/// requirement for the spend it is asked about.
private final class RefreshingApprovalStub: SwapInteractor {
    let refreshed: SwapQuote
    let requirement: ERC20ApprovalRequirement
    private(set) var resolveApprovalCallCount = 0

    init(refreshed: SwapQuote, requirement: ERC20ApprovalRequirement) {
        self.refreshed = refreshed
        self.requirement = requirement
    }

    func resolveApproval(for transaction: SwapTransaction, vault: Vault) async throws -> ERC20ApprovalDecision? {
        resolveApprovalCallCount += 1
        let query = SwapCryptoLogic.approvalQuery(
            fromCoin: transaction.fromCoin,
            amount: transaction.amountInCoinDecimal,
            quote: transaction.quote
        )
        return query.map { ERC20ApprovalDecision(query: $0, requirement: requirement) }
    }

    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        SwapQuoteResult(quote: refreshed, allQuotes: [refreshed], vultDiscountBps: 0, referralDiscountBps: 0)
    }

    func fetchChainSpecific(fromCoin: Coin, toCoin: Coin, fromAmount: Decimal, quote: SwapQuote?) async throws -> BlockChainSpecific {
        .Ethereum(maxFeePerGasWei: 1, priorityFeeWei: 1, nonce: 0, gasLimit: 1)
    }

    func computeThorchainFee(chainSpecific: BlockChainSpecific, fromCoin: Coin, fromAmount: Decimal, vault: Vault) async throws -> BigInt {
        .zero
    }

    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {}

    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        throw CancellationError()
    }

    func updateBalance(for coin: Coin) async {}

    func warmDiscountTier(for vault: Vault) async {}
}
// swiftlint:enable async_without_await unused_parameter
