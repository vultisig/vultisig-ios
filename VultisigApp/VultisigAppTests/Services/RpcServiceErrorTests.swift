//
//  RpcServiceErrorTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class RpcServiceErrorTests: XCTestCase {
    private static let stubHost = "rpc-service-error-stub.local"

    override func setUp() {
        super.setUp()
        RpcServiceErrorStubProtocol.responseData = Data()
        URLProtocol.registerClass(RpcServiceErrorStubProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RpcServiceErrorStubProtocol.self)
        RpcServiceErrorStubProtocol.responseData = Data()
        super.tearDown()
    }

    func testCode1010ErrorSurfacesSpecificDataReason() async {
        RpcServiceErrorStubProtocol.responseData = Data(
            #"{"jsonrpc":"2.0","id":1,"error":{"code":1010,"message":"Invalid Transaction","data":"Transaction has a bad signature"}}"#.utf8
        )

        await assertRPCError(
            expectedCode: 1010,
            expectedMessage: "Transaction has a bad signature"
        )
    }

    func testRPCErrorFallsBackToMessageWhenDataIsMissing() async {
        RpcServiceErrorStubProtocol.responseData = Data(
            #"{"jsonrpc":"2.0","id":1,"error":{"code":1010,"message":"Invalid Transaction"}}"#.utf8
        )

        await assertRPCError(
            expectedCode: 1010,
            expectedMessage: "Invalid Transaction"
        )
    }

    private func assertRPCError(expectedCode: Int, expectedMessage: String) async {
        let service = RpcService("https://\(Self.stubHost)/rpc")

        do {
            let result = try await service.strRpcCall(method: "author_submitExtrinsic", params: ["0x00"])
            XCTFail("Expected RPC error, got \(result)")
        } catch let RpcServiceError.rpcError(code, message) {
            XCTAssertEqual(code, expectedCode)
            XCTAssertEqual(message, expectedMessage)
            XCTAssertEqual(
                RpcServiceError.rpcError(code: code, message: message).localizedDescription,
                "RPC Error \(expectedCode): \(expectedMessage)"
            )
        } catch {
            XCTFail("Expected RpcServiceError.rpcError, got \(error)")
        }
    }
}

private final class RpcServiceErrorStubProtocol: URLProtocol {
    static var responseData = Data()

    // These are required `URLProtocol` class-method overrides; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "rpc-service-error-stub.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
