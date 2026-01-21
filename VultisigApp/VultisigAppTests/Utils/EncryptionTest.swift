//
//  EncryptionTest.swift
//  VultisigAppTests
//
//  Created by Johnny Luo on 11/4/2024.
//

import XCTest
@testable import VultisigApp

final class EncryptionTest: XCTestCase {
    func testEncryptionRoundtrip() throws {
        let encryptionKey = Encryption.getEncryptionKey()
        XCTAssert(encryptionKey != nil)
        let result = "helloworld".aesEncrypt(key: encryptionKey!)
        print(result ?? "")
        let decrypted = result?.aesDecrypt(key: encryptionKey!)
        print(decrypted ?? "")
        XCTAssert(decrypted == "helloworld")
    }
    func testAndroidEncryption() throws {
        let encryptionKey = "b5890b4dfb218e9482b429fcbb8317467211102b5890c0edddb2facd40316434"
        let result = "gd95s9igrMv9pFqPrnQwSlwZbDGpvR1X7FFxpDXHtns=".aesDecrypt(key: encryptionKey)
        XCTAssert(result == "helloworld")
    }
}
