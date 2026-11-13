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

final class FyndServiceTests: XCTestCase {

    private let receiver = FyndService.feeReceiver

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
    private let receiver = FyndService.feeReceiver.lowercased()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let sell = BigInt("1000000000000000000")
    private let amountOut = BigInt(3_000_000_000)

    func testZeroFeeQuoteIsAccepted() throws {
        let quote = try FyndService.validate(order(), context: context(clientFeeBps: 0))
        XCTAssertEqual(quote.netAmountOut, amountOut - 300)
        XCTAssertEqual(quote.clientFee, 0)
        XCTAssertEqual(quote.value, String(sell))
    }

    func testSignedFeeQuoteIsAccepted() throws {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        let quote = try FyndService.validate(signedOrder(clientFee: fee), context: context(clientFeeBps: 63))
        XCTAssertEqual(quote.clientFee, fee)
        XCTAssertEqual(quote.netAmountOut, amountOut - 300 - fee)

        let (evmQuote, _) = FyndService.makeQuote(quote, sender: "0xa", tokenOut: "0xusdc")
        XCTAssertEqual(evmQuote.tx.swapFee, String(fee))
        XCTAssertEqual(evmQuote.tx.swapFeeTokenContract, "0xusdc")
        XCTAssertEqual(evmQuote.dstAmount, String(amountOut - 300 - fee))
    }

    func testRejectsAForeignRouter() {
        assertInvalid(order(to: "0x00000000000000000000000000000000deadbeef"), clientFeeBps: 0)
    }

    func testRejectsADifferentSellAmountOrValue() {
        assertInvalid(order(amountIn: "999"), clientFeeBps: 0)
        assertInvalid(order(value: "1"), clientFeeBps: 0)
    }

    func testRejectsAnOutputFloorLooserThanTheSlippage() {
        assertInvalid(order(minReceived: "1"), clientFeeBps: 0)
    }

    func testRejectsAClientFeeTheAppDidNotAskFor() {
        assertInvalid(order(clientFee: "5"), clientFeeBps: 0)
    }

    func testRejectsAClientFeeThatDiffersFromTheRequestedBps() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee + 10), clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee - 10), clientFeeBps: 63)
    }

    func testRejectsAQuoteForAnotherFeeReceiver() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, receiver: "0x00000000000000000000000000000000deadbeef"), clientFeeBps: 63)
    }

    func testRejectsTheUnsignedPlaceholder() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, signature: String(repeating: "0", count: 130)), clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, offset: nil), clientFeeBps: 63)
    }

    func testRejectsAMissingOrExpiredDeadline() {
        let fee = FyndService.expectedClientFee(amountOut: amountOut, clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, deadline: nil), clientFeeBps: 63)
        assertInvalid(signedOrder(clientFee: fee, deadline: Int(now.timeIntervalSince1970) - 1), clientFeeBps: 63)
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

private extension FyndQuoteValidationTests {
    func context(clientFeeBps: Int) -> FyndQuoteContext {
        FyndQuoteContext(
            router: router,
            sellAmount: sell,
            sellsNative: true,
            slippageBps: 100,
            clientFeeBps: clientFeeBps,
            feeReceiver: FyndService.feeReceiver,
            now: now
        )
    }

    func order(
        status: String = "success",
        to: String? = nil,
        amountIn: String? = nil,
        value: String? = nil,
        clientFee: String = "0",
        minReceived: String? = nil,
        data: String = "0xabcdef01",
        offset: Int? = nil,
        deadline: Int? = nil
    ) -> FyndOrderQuote {
        let fee = BigInt(clientFee) ?? 0
        let net = amountOut - 300 - fee
        return FyndOrderQuote(
            status: status,
            amountIn: amountIn ?? String(sell),
            amountOut: String(amountOut),
            gasEstimate: "200000",
            gasPrice: "1000000000",
            transaction: .init(to: to ?? router, value: value ?? String(sell), data: data, clientFeeSignatureOffset: offset),
            feeBreakdown: .init(
                routerFee: "300",
                clientFee: clientFee,
                maxSlippage: "0",
                minAmountReceived: minReceived ?? String(net * 9_900 / 10_000)
            ),
            clientFeeDeadline: deadline
        )
    }

    func signedOrder(
        clientFee: BigInt,
        receiver: String? = nil,
        signature: String = String(repeating: "ab", count: 65),
        offset: Int? = 36,
        deadline: Int? = 1_800_000_900
    ) -> FyndOrderQuote {
        let receiverWord = String(repeating: "0", count: 24) + (receiver ?? self.receiver).lowercased().stripHexPrefix()
        return order(
            clientFee: String(clientFee),
            data: "0xabcdef01" + receiverWord + signature,
            offset: offset,
            deadline: deadline
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
