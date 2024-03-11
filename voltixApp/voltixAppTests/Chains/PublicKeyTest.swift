//
//  PublicKeyTest.swift
//  VoltixAppTests
//

import XCTest
@testable import VoltixApp

final class PublicKeyTest: XCTestCase {

    func testGetDerivePublicKey() throws {
        let hexPublicKey = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
        let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"
        let result = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPublicKey, hexChainCode: hexChainCode, derivePath: "m/84'/0'/0'/0/0")
        XCTAssertEqual(result, "026724d27f668b88513c925360ba5c5888cc03641eccbe70e6d85023e7c511b969")
        let resultETH = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPublicKey, hexChainCode: hexChainCode, derivePath: "m/44'/60'/0'/0/0")
        XCTAssertEqual(resultETH, "03bb1adf8c0098258e4632af6c055c37135477e269b7e7eb4f600fe66d9ca9fd78")
        let resultTHORChain = PublicKeyHelper.getDerivedPubKey(hexPubKey: hexPublicKey, hexChainCode: hexChainCode, derivePath: "m/44'/931'/0'/0/0")
        XCTAssertEqual(resultTHORChain, "02a9ac9f7a97da41559e1684011b6a9b0b9c0445297d5f51dea0897fd4a39c31c7")
    }
}
