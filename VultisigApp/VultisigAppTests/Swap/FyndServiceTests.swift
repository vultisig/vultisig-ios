//
//  FyndServiceTests.swift
//  VultisigAppTests
//
//  Fee math and quote validation for the Fynd swap provider. Mirrors the
//  Android `FyndApi` tests so both platforms charge and refuse the same quotes.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class FyndServiceTests: XCTestCase {

    private let receiver = "0x2222222222222222222222222222222222222222"

    // MARK: - Fee math

    func testAffiliateBpsFollowsTheVultTierDiscount() {
        XCTAssertEqual(FyndService.affiliateBps(vultTierDiscount: 0), 50)
        XCTAssertEqual(FyndService.affiliateBps(vultTierDiscount: 10), 40)
        XCTAssertEqual(FyndService.affiliateBps(vultTierDiscount: 35), 15)
        XCTAssertEqual(FyndService.affiliateBps(vultTierDiscount: 50), 0)
        XCTAssertEqual(FyndService.affiliateBps(vultTierDiscount: 60), 0)
    }

    func testClientFeeIsGrossedUpForFyndsShare() {
        XCTAssertEqual(FyndService.clientFeeBps(affiliateBps: 0), 0)
        XCTAssertEqual(FyndService.clientFeeBps(affiliateBps: 50), 63)
        XCTAssertEqual(FyndService.clientFeeBps(affiliateBps: 40), 50)
        XCTAssertEqual(FyndService.clientFeeBps(affiliateBps: 15), 19)
        XCTAssertEqual(FyndService.clientFeeBps(affiliateBps: 1), 2)
    }

    func testExpectedClientFeeMatchesFyndsWorkedExample() {
        // Fynd docs: 1,000,000 out at 50 bps leaves the integrator 4,000.
        XCTAssertEqual(FyndService.expectedClientFee(amountOut: 1_000_000, clientFeeBps: 50), 4_000)
    }

    func testGrossedUpFeeNetsAtLeastTheAffiliateBps() {
        let amountOut = BigInt(10_000_000_000)
        for discount in [0, 10, 20, 35, 49] {
            let affiliate = FyndService.affiliateBps(vultTierDiscount: discount)
            let net = FyndService.expectedClientFee(
                amountOut: amountOut,
                clientFeeBps: FyndService.clientFeeBps(affiliateBps: affiliate)
            )
            XCTAssertGreaterThanOrEqual(net, amountOut * BigInt(affiliate) / 10_000, "discount \(discount)")
        }
    }

    func testSlippageIsSentAsADecimalFraction() {
        XCTAssertEqual(FyndService.slippageString(bps: 100), "0.01")
        XCTAssertEqual(FyndService.slippageString(bps: 50), "0.005")
    }

    // MARK: - Request encoding

    func testRequestCarriesClientFeeParamsOnlyWhenCharging() throws {
        let charged = try encode(request(clientFee: .init(bps: 63, receiver: receiver)))
        let encoding = try XCTUnwrap(options(charged)["encoding_options"] as? [String: Any])
        let fee = try XCTUnwrap(encoding["client_fee_params"] as? [String: Any])
        XCTAssertEqual(fee["bps"] as? Int, 63)
        XCTAssertEqual(fee["receiver"] as? String, receiver)
        XCTAssertEqual(encoding["transfer_type"] as? String, "transfer_from")

        let free = try encode(request(clientFee: nil))
        let freeEncoding = try XCTUnwrap(options(free)["encoding_options"] as? [String: Any])
        XCTAssertNil(freeEncoding["client_fee_params"])
    }

    func testGateStaysClosedWithoutAKeyOrFeeReceiver() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: FyndService.remoteFlagDefaultsKey)
        defer { defaults.set(saved, forKey: FyndService.remoteFlagDefaultsKey) }
        defaults.set(true, forKey: FyndService.remoteFlagDefaultsKey)
        // No FYND_API_KEY in the test environment and no receiver configured yet:
        // the proxy path cannot charge the fee, so Fynd must not be quoted.
        XCTAssertNil(FyndService.feeReceiver)
        XCTAssertFalse(FyndService.isEnabled)
        XCTAssertFalse(makeCoin(chain: .ethereum).swapProviders.contains(.fynd(.ethereum)))
    }

    func testRemoteFlagNameMatchesAndroid() {
        XCTAssertEqual(FeatureFlag.fyndSwap.name, "fynd-swap")
    }

    func testFyndOnlyServesItsThreePinnedChains() {
        for chain in [Chain.ethereum, .base, .arbitrum] {
            XCTAssertNotNil(FyndService.chainName(for: chain))
            XCTAssertNotNil(EVMSwapTxGuard.fyndRouter(for: chain))
        }
        XCTAssertNil(FyndService.chainName(for: .polygon))
        XCTAssertNil(EVMSwapTxGuard.fyndRouter(for: .polygon))
    }

    // MARK: - Helpers

    private func request(clientFee: FyndQuoteRequest.ClientFeeParams?) -> FyndQuoteRequest {
        FyndQuoteRequest(
            orders: [.init(tokenIn: "0x0", tokenOut: "0x1", amount: "1", side: "sell", sender: "0xa", receiver: "0xa")],
            options: .init(
                timeoutMs: 5000,
                minResponses: 1,
                encodingOptions: .init(slippage: "0.01", transferType: "transfer_from", clientFeeParams: clientFee)
            )
        )
    }

    private func makeCoin(chain: Chain) -> Coin {
        Coin(
            asset: CoinMeta(chain: chain, ticker: "ETH", logo: "logo", decimals: 18, priceProviderId: "fynd-gate", contractAddress: "", isNativeToken: true),
            address: "0xFrom",
            hexPublicKey: ""
        )
    }

    private func encode(_ request: FyndQuoteRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func options(_ json: [String: Any]) -> [String: Any] {
        json["options"] as? [String: Any] ?? [:]
    }
}

// MARK: - Quote validation

final class FyndQuoteValidationTests: XCTestCase {

    private let router = "0x1644d2477f809cc2c71bccfd6dc9497e3f83210d"
    private let usdc = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
    private let attacker = "0x00000000000000000000000000000000deadbeef"
    private let feeReceiver = "0x2222222222222222222222222222222222222222"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let sell = BigInt("1000000000000000000")
    private let amountOut = BigInt(3_000_000_000)

    func testZeroFeeQuoteIsAccepted() throws {
        let quote = try FyndService.validate(order(), context: context(clientFeeBps: 0))
        XCTAssertEqual(quote.netAmountOut, amountOut - 300)
        XCTAssertEqual(quote.clientFee, 0)
        XCTAssertEqual(quote.value, String(sell))
    }

    func testEveryTransferFromEntrypointDecodes() throws {
        for selector in [FyndRouterCall.splitSwapSelector, FyndRouterCall.sequentialSwapSelector, FyndRouterCall.singleSwapSelector] {
            XCTAssertNoThrow(try FyndService.validate(order(call: call(selector: selector)), context: context(clientFeeBps: 0)), selector)
        }
    }

    func testRejectsTheZeroAddressAsTheRoutersNativeToken() {
        // TychoRouterV3 takes 0xEeee… for the native side and reverts on address(0).
        assertInvalid(order(call: call(tokenIn: FyndService.nativeTokenAddress)), clientFeeBps: 0)
    }

    func testRejectsASignatureOffsetThatDisagreesWithTheCalldata() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, reportedOffset: 4), clientFeeBps: 63)
        XCTAssertNoThrow(try FyndService.validate(signedOrder(clientFee: fee, reportedOffset: signatureOffset), context: context(clientFeeBps: 63)))
    }

    func testSignedFeeQuoteIsAccepted() throws {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        let quote = try FyndService.validate(signedOrder(clientFee: fee), context: context(clientFeeBps: 63))
        XCTAssertEqual(quote.clientFee, fee)
        XCTAssertEqual(quote.netAmountOut, amountOut - 300 - fee)

        let (evmQuote, _) = FyndService.makeQuote(quote, sender: recipient, tokenOut: usdc)
        XCTAssertEqual(evmQuote.tx.swapFee, String(fee))
        XCTAssertEqual(evmQuote.tx.swapFeeTokenContract, usdc)
        XCTAssertEqual(evmQuote.dstAmount, String(amountOut - 300 - fee))
    }

    func testRejectsAForeignRouter() {
        assertInvalid(order(to: attacker), clientFeeBps: 0)
    }

    func testRejectsUnknownSelectorsAndVaultEntrypoints() {
        assertInvalid(order(data: "0xabcdef01"), clientFeeBps: 0)
        // singleSwapUsingVault: same head, but spends the sender's router vault.
        assertInvalid(order(call: call(selector: "ef7008ea")), clientFeeBps: 0)
    }

    func testRejectsCalldataThatSwapsSomethingElse() {
        assertInvalid(order(call: call(amountIn: sell - 1)), clientFeeBps: 0)
        assertInvalid(order(call: call(tokenOut: attacker)), clientFeeBps: 0)
        assertInvalid(order(call: call(tokenIn: usdc)), clientFeeBps: 0)
        assertInvalid(order(call: call(receiver: attacker)), clientFeeBps: 0)
        assertInvalid(order(call: call(minAmountOut: minOut(clientFee: 0) - 1)), clientFeeBps: 0)
        assertInvalid(order(call: call(expectedAmountOut: amountOut + 1)), clientFeeBps: 0)
    }

    func testExpectedWordsInTrailingDataDoNotSatisfyTheDecoder() {
        let honestWords = FyndRouterCallEncoder.word(sell) + FyndRouterCallEncoder.address(recipient)
        let data = "0x" + call(receiver: attacker) + honestWords
        assertInvalid(order(data: data), clientFeeBps: 0)
    }

    func testRejectsADifferentSellAmountOrValue() {
        assertInvalid(order(amountIn: "999"), clientFeeBps: 0)
        assertInvalid(order(value: "1"), clientFeeBps: 0)
    }

    func testRejectsAnInflatedRouterFee() {
        // A huge router fee would make a near-zero minimum look within slippage.
        let inflated = amountOut - 2
        assertInvalid(order(routerFee: String(inflated)), clientFeeBps: 0)
        let cap = FyndService.maxRouterFee(amountOut: amountOut, clientFeeBps: 0)
        XCTAssertEqual(cap, amountOut * 10 / 10_000)
        XCTAssertNoThrow(try FyndService.validate(order(routerFee: String(cap)), context: context(clientFeeBps: 0)))
        assertInvalid(order(routerFee: String(cap + 1)), clientFeeBps: 0)
    }

    func testRouterFeeCapIncludesFyndsShareOfTheClientFee() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        let share = amountOut * 63 / 10_000 - fee
        XCTAssertEqual(FyndService.maxRouterFee(amountOut: amountOut, clientFeeBps: 63), share + amountOut * 10 / 10_000)
        XCTAssertNoThrow(try FyndService.validate(signedOrder(clientFee: fee, routerFee: share + 300), context: context(clientFeeBps: 63)))
    }

    func testRejectsAnOutputFloorLooserThanTheSlippage() {
        assertInvalid(order(minReceived: "1"), clientFeeBps: 0)
    }

    func testRejectsAClientFeeTheAppDidNotAskFor() {
        assertInvalid(order(clientFee: "5"), clientFeeBps: 0)
        assertInvalid(order(call: call(feeUnits: 630_000)), clientFeeBps: 0)
    }

    func testRejectsAClientFeeThatDiffersFromTheRequestedBps() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee + 1), clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, feeUnits: 640_000), clientFeeBps: 63)
    }

    func testRejectsAQuoteForAnotherFeeReceiver() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, feeReceiver: attacker), clientFeeBps: 63)
    }

    func testRejectsASubsidizedFee() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, maxContribution: 1), clientFeeBps: 63)
    }

    func testRejectsTheUnsignedPlaceholder() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, signature: String(repeating: "0", count: 130)), clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, signature: ""), clientFeeBps: 63)
    }

    func testRejectsAMissingMismatchedOrShortDeadline() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, deadline: nil), clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, deadline: 1_800_003_600, calldataDeadline: 1_800_003_601), clientFeeBps: 63)
        // Must outlive multi-device keysign: at least 15 minutes out.
        let tooSoon = Int(now.timeIntervalSince1970) + 15 * 60 - 1
        assertInvalid(signedOrder(clientFee: fee, deadline: tooSoon, calldataDeadline: tooSoon), clientFeeBps: 63)
    }

    func testMapsFailedStatuses() {
        XCTAssertThrowsError(try FyndService.validate(order(status: "no_route_found"), context: context(clientFeeBps: 0))) {
            XCTAssertEqual($0 as? FyndError, .noRoute)
        }
        XCTAssertThrowsError(try FyndService.validate(order(status: "timeout"), context: context(clientFeeBps: 0))) {
            XCTAssertEqual($0 as? FyndError, .timeout)
        }
        XCTAssertEqual(FyndService.mapHTTPError(statusCode: 429, body: nil) as? FyndError, .rateLimited)
    }
}

/// ABI-encodes TychoRouterV3 swap calls for the validator tests.
enum FyndRouterCallEncoder {
    static func word(_ value: BigInt) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 64 - hex.count) + hex
    }

    static func address(_ address: String) -> String {
        String(repeating: "0", count: 24) + address.lowercased().stripHexPrefix()
    }

    static func bytes(_ hex: String) -> String {
        let padding = (64 - hex.count % 64) % 64
        return word(BigInt(hex.count / 2)) + hex + String(repeating: "0", count: padding)
    }

    // swiftlint:disable:next function_parameter_count
    static func encode(
        selector: String,
        amountIn: BigInt,
        tokenIn: String,
        tokenOut: String,
        expectedAmountOut: BigInt,
        minAmountOut: BigInt,
        receiver: String,
        feeUnits: BigInt,
        feeReceiver: String,
        maxContribution: BigInt,
        deadline: BigInt,
        signature: String
    ) -> String {
        var head = [word(amountIn), address(tokenIn), address(tokenOut), word(expectedAmountOut), word(minAmountOut)]
        if selector == FyndRouterCall.splitSwapSelector { head.append(word(2)) }
        head.append(address(receiver))
        let headSize = (head.count + 2) * 32
        let tuple = word(feeUnits) + address(feeReceiver) + word(maxContribution) + word(deadline) + word(5 * 32) + bytes(signature)
        head.append(word(BigInt(headSize)))
        head.append(word(BigInt(headSize + tuple.count / 2)))
        return selector + head.joined() + tuple + bytes("")
    }
}

private extension FyndQuoteValidationTests {
    var recipient: String { "0x1111111111111111111111111111111111111111" }
    var zeroAddress: String { FyndService.nativeTokenAddress }
    /// selector (4) + 8 head words + 5 tuple words + signature length word.
    var signatureOffset: Int { 4 + 8 * 32 + 5 * 32 + 32 }

    func context(clientFeeBps: Int) -> FyndQuoteContext {
        FyndQuoteContext(
            router: router,
            recipient: recipient,
            tokenIn: zeroAddress,
            tokenOut: usdc,
            sellAmount: sell,
            slippageBps: 100,
            clientFeeBps: clientFeeBps,
            feeReceiver: feeReceiver,
            now: now
        )
    }

    func netOut(clientFee: BigInt, routerFee: BigInt = 300) -> BigInt { amountOut - routerFee - clientFee }
    func minOut(clientFee: BigInt, routerFee: BigInt = 300) -> BigInt {
        netOut(clientFee: clientFee, routerFee: routerFee) * 9_900 / 10_000
    }

    func call(
        selector: String = FyndRouterCall.singleSwapSelector,
        amountIn: BigInt? = nil,
        tokenIn: String? = nil,
        tokenOut: String? = nil,
        expectedAmountOut: BigInt? = nil,
        minAmountOut: BigInt? = nil,
        receiver: String? = nil,
        feeUnits: BigInt = 0,
        feeReceiver: String? = nil,
        maxContribution: BigInt = 0,
        deadline: BigInt = 0,
        signature: String = ""
    ) -> String {
        FyndRouterCallEncoder.encode(
            selector: selector,
            amountIn: amountIn ?? sell,
            tokenIn: tokenIn ?? FyndService.routerNativeAddress,
            tokenOut: tokenOut ?? usdc,
            expectedAmountOut: expectedAmountOut ?? amountOut,
            minAmountOut: minAmountOut ?? minOut(clientFee: 0),
            receiver: receiver ?? recipient,
            feeUnits: feeUnits,
            feeReceiver: feeReceiver ?? zeroAddress,
            maxContribution: maxContribution,
            deadline: deadline,
            signature: signature
        )
    }

    func order(
        status: String = "success",
        to: String? = nil,
        amountIn: String? = nil,
        value: String? = nil,
        clientFee: String = "0",
        routerFee: String = "300",
        minReceived: String? = nil,
        call: String? = nil,
        data: String? = nil,
        deadline: Int? = nil,
        reportedOffset: Int? = nil
    ) -> FyndOrderQuote {
        let fee = BigInt(clientFee) ?? 0
        let min = minReceived ?? String(minOut(clientFee: fee, routerFee: BigInt(routerFee) ?? 0))
        return FyndOrderQuote(
            status: status,
            amountIn: amountIn ?? String(sell),
            amountOut: String(amountOut),
            gasEstimate: "200000",
            gasPrice: "1000000000",
            transaction: .init(
                to: to ?? router,
                value: value ?? String(sell),
                data: data ?? ("0x" + (call ?? self.call(minAmountOut: BigInt(min)))),
                clientFeeSignatureOffset: reportedOffset
            ),
            feeBreakdown: .init(routerFee: routerFee, clientFee: clientFee, maxSlippage: "0", minAmountReceived: min),
            clientFeeDeadline: deadline
        )
    }

    func signedOrder(
        clientFee: BigInt,
        feeUnits: BigInt = 630_000,
        feeReceiver: String? = nil,
        maxContribution: BigInt = 0,
        signature: String = String(repeating: "ab", count: 65),
        deadline: Int? = 1_800_003_600,
        calldataDeadline: Int? = nil,
        reportedOffset: Int? = nil,
        routerFee: BigInt = 300
    ) -> FyndOrderQuote {
        let signed = call(
            minAmountOut: minOut(clientFee: clientFee, routerFee: routerFee),
            feeUnits: feeUnits,
            feeReceiver: feeReceiver ?? self.feeReceiver,
            maxContribution: maxContribution,
            deadline: BigInt(calldataDeadline ?? deadline ?? 0),
            signature: signature
        )
        return order(
            clientFee: String(clientFee),
            routerFee: String(routerFee),
            call: signed,
            deadline: deadline,
            reportedOffset: reportedOffset
        )
    }

    func assertInvalid(_ order: FyndOrderQuote, clientFeeBps: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try FyndService.validate(order, context: context(clientFeeBps: clientFeeBps)), file: file, line: line) {
            guard case .invalidResponse = $0 as? FyndError else {
                return XCTFail("Expected invalidResponse, got \($0)", file: file, line: line)
            }
        }
    }
}
