import BigInt
import XCTest
@testable import VultisigApp

final class WalletConnectTransactionRequestParserTests: XCTestCase {
    private let parser = WalletConnectTransactionRequestParser()

    func testParsesSendTransactionFirstParamObject() throws {
        let parsed = try parser.parse(request(paramsJSON: """
        [{
          "from":"0x1111111111111111111111111111111111111111",
          "to":"0x2222222222222222222222222222222222222222",
          "value":"0xde0b6b3a7640000",
          "data":"0xa9059cbb",
          "gas":"0x5208",
          "gasPrice":"0x3b9aca00",
          "maxFeePerGas":"0x59682f00",
          "maxPriorityFeePerGas":"0x3b9aca00",
          "nonce":"0x7"
        }]
        """))

        XCTAssertEqual(parsed.from, "0x1111111111111111111111111111111111111111")
        XCTAssertEqual(parsed.to, "0x2222222222222222222222222222222222222222")
        XCTAssertEqual(parsed.valueWei, BigInt("1000000000000000000"))
        XCTAssertEqual(parsed.data, "0xa9059cbb")
        XCTAssertEqual(parsed.overrides.gas, BigInt(21_000))
        XCTAssertEqual(parsed.overrides.nonce, BigInt(7))
    }

    func testMissingValueMeansZeroAndInputAliasesData() throws {
        let parsed = try parser.parse(request(paramsJSON: """
        [{
          "from":"0x1111111111111111111111111111111111111111",
          "to":"0x2222222222222222222222222222222222222222",
          "input":"0xabcdef"
        }]
        """))

        XCTAssertEqual(parsed.valueWei, .zero)
        XCTAssertEqual(parsed.data, "0xabcdef")
    }

    func testRejectsMalformedQuantityAddressAndCalldata() {
        XCTAssertThrowsError(try parser.parse(request(paramsJSON: "[{\"from\":\"0x123\",\"value\":\"0x1\"}]")))
        XCTAssertThrowsError(try parser.parse(request(paramsJSON: "[{\"from\":\"0x1111111111111111111111111111111111111111\",\"value\":\"1\"}]")))
        XCTAssertThrowsError(try parser.parse(request(paramsJSON: "[{\"from\":\"0x1111111111111111111111111111111111111111\",\"data\":\"0xabc\"}]")))
        XCTAssertThrowsError(try parser.parse(request(paramsJSON: "[{\"from\":\"0x1111111111111111111111111111111111111111\",\"data\":\"\"}]")))
    }

    func testRejectsNonCanonicalLeadingZeroQuantities() {
        XCTAssertThrowsError(try parser.parse(request(paramsJSON: "[{\"from\":\"0x1111111111111111111111111111111111111111\",\"value\":\"0x00\"}]")))
        XCTAssertThrowsError(try parser.parse(request(paramsJSON: "[{\"from\":\"0x1111111111111111111111111111111111111111\",\"gas\":\"0x01\"}]")))
    }

    func testRejectsUnsupportedMethod() {
        XCTAssertThrowsError(try parser.parse(request(method: "personal_sign", paramsJSON: "[]"))) { error in
            XCTAssertEqual(error as? WalletConnectTransactionRequestError, .unsupportedMethod("personal_sign"))
        }
    }

    private func request(method: String = "eth_sendTransaction", paramsJSON: String) -> WalletConnectIncomingRequest {
        WalletConnectIncomingRequest(
            topic: "topic",
            requestId: "1",
            method: method,
            chainId: "eip155:1",
            paramsJSON: paramsJSON,
            dappName: "Example",
            dappURL: "https://example.com",
            dappIcon: nil,
            verifyContext: nil
        )
    }
}
