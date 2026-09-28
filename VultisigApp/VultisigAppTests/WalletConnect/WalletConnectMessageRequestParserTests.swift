import XCTest
@testable import VultisigApp

final class WalletConnectMessageRequestParserTests: XCTestCase {
    private let parser = WalletConnectMessageRequestParser()

    func testParsesPersonalSignMessageAddressOrderAndDecodesDisplayMessage() throws {
        let parsed = try parser.parse(request(method: "personal_sign", paramsJSON: "[\"0x68656c6c6f\",\"0x1111111111111111111111111111111111111111\"]"))

        XCTAssertEqual(parsed.address, "0x1111111111111111111111111111111111111111")
        XCTAssertEqual(parsed.message, "0x68656c6c6f")
        XCTAssertEqual(parsed.displayMessage, "hello")
    }

    func testParsesPersonalSignAddressMessageOrder() throws {
        let parsed = try parser.parse(request(method: "personal_sign", paramsJSON: "[\"0x2222222222222222222222222222222222222222\",\"hello\"]"))

        XCTAssertEqual(parsed.address, "0x2222222222222222222222222222222222222222")
        XCTAssertEqual(parsed.message, "hello")
        XCTAssertEqual(parsed.displayMessage, "hello")
    }

    func testParsesTypedDataV4PreservingRawTypedDataJSON() throws {
        let typedData = "{\"domain\":{\"name\":\"Example\"},\"message\":{\"contents\":\"Hi\"},\"primaryType\":\"Mail\",\"types\":{}}"
        let parsed = try parser.parse(request(
            method: "eth_signTypedData_v4",
            paramsJSON: "[\"0x3333333333333333333333333333333333333333\",\(typedData)]"
        ))

        XCTAssertEqual(parsed.address, "0x3333333333333333333333333333333333333333")
        XCTAssertEqual(parsed.message, typedData)
        XCTAssertTrue(parsed.displayMessage.contains("Example"))
    }

    func testRejectsUnsupportedMethod() {
        XCTAssertThrowsError(try parser.parse(request(method: "eth_sendTransaction", paramsJSON: "[]"))) { error in
            XCTAssertEqual(error as? WalletConnectMessageRequestError, .unsupportedMethod("eth_sendTransaction"))
        }
    }

    private func request(method: String, paramsJSON: String) -> WalletConnectIncomingRequest {
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
