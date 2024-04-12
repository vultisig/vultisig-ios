//
//  EncryptionTest.swift
//  VoltixAppTests
//
//  Created by Johnny Luo on 11/4/2024.
//

import XCTest
@testable import VoltixApp

final class EncryptionTest: XCTestCase {
    func testEncryptionRoundtrip() throws {
        let encryptionKey = Encryption.getEncryptionKey()
        XCTAssert(encryptionKey != nil)
        let result = "helloworld".aesEncrypt(key: encryptionKey!)
        let decrypted = result?.aesDecrypt(key: encryptionKey!)
        XCTAssert(decrypted == "helloworld")
    }
    
}
