//
//  DataExntension.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import OSLog
import CommonCrypto
import Security

extension Data{
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        
        return Data(hash)
    }
    func toSecKey(isPublic: Bool) -> SecKey? {
        let options: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                      kSecAttrKeyClass as String: isPublic ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate,
                                      kSecAttrKeySizeInBits as String: 2048,
                                      kSecReturnPersistentRef as String: true]
        let cfdata = self as CFData
        return SecKeyCreateWithData(cfdata, options as CFDictionary, nil)
    }
}
