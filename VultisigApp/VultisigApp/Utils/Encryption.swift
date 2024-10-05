//
//  Encryption.swift
//  VultisigApp
//
//  Created by Johnny Luo on 11/4/2024.
//

import Foundation
import CommonCrypto
import CryptoKit

enum AESError: Error {
    case keyGeneration
    case encryptionFailed
    case decryptionFailed
}

public extension String {
    func aesEncrypt(key: String) -> String? {
        guard
            let data = self.data(using: .utf8),
            let key = Data(hexString: key),
            let encrypt = data.encryptAES256(key: key)
        else { return nil }
        let base64Data = encrypt.base64EncodedData()
        return String(data: base64Data, encoding: .utf8)
    }
    func aesEncryptGCM(key: String) -> String? {
        guard
            let data = self.data(using: .utf8),
            let key = Data(hexString: key),
            let encrypt = try? data.aesGCMEncrypt(key: key)
        else { return nil }
        let base64Data = encrypt.base64EncodedData()
        return String(data: base64Data, encoding: .utf8)
    }
    
    func aesDecrypt(key: String) -> String? {
        guard
            let data = Data(base64Encoded: self),
            let key = Data(hexString: key)
        else { return nil }
        // try to decrypted with GCM
        let decrypt = data.decryptAES256(key: key)
        guard let decrypt else {
            return nil
        }
        return String(data: decrypt, encoding: .utf8)
    }
    func aesDecryptGCM(key: String) -> String? {
        guard
            let data = Data(base64Encoded: self),
            let key = Data(hexString: key)
        else { return nil }
        // try to decrypted with GCM
        let decrypt = try? data.aesGCMDecrypt(key: key)
        guard let decrypt else {
            return nil
        }
        return String(data: decrypt, encoding: .utf8)
    }
}

/// @see http://www.splinter.com.au/2019/06/09/pure-swift-common-crypto-aes-encryption/
public extension Data {
    /// Encrypts for you with all the good options turned on: CBC, an IV, PKCS7
    /// padding (so your input data doesn't have to be any particular length).
    /// Key can be 128, 192, or 256 bits.
    /// Generates a fresh IV for you each time, and prefixes it to the
    /// returned ciphertext.
    func encryptAES256(key: Data, options: Int = kCCOptionPKCS7Padding) -> Data? {
        guard let iv = randomGenerateBytes(count: kCCBlockSizeAES128) else {return nil}
        // No option is needed for CBC, it is on by default.
        guard let cliphertext = aesCrypt(operation: kCCEncrypt,
                                         algorithm: kCCAlgorithmAES,
                                         options: options,
                                         key: key,
                                         initializationVector: iv,
                                         dataIn: self) else {
            return nil
        }
        return iv + cliphertext
    }
    
    /// Decrypts self, where self is the IV then the ciphertext.
    /// Key can be 128/192/256 bits.
    func decryptAES256(key: Data,  options: Int = kCCOptionPKCS7Padding) -> Data? {
        guard count > kCCBlockSizeAES128 else { return nil }
        let iv = prefix(kCCBlockSizeAES128)
        let ciphertext = suffix(from: kCCBlockSizeAES128)
        return aesCrypt(operation: kCCDecrypt,
                        algorithm: kCCAlgorithmAES,
                        options: options,
                        key: key,
                        initializationVector: iv,
                        dataIn: ciphertext)
    }
    
    // swiftlint:disable:next function_parameter_count
    private func aesCrypt(operation: Int,
                          algorithm: Int,
                          options: Int,
                          key: Data,
                          initializationVector: Data,
                          dataIn: Data) -> Data? {
        return initializationVector.withUnsafeBytes { ivUnsafeRawBufferPointer in
            return key.withUnsafeBytes { keyUnsafeRawBufferPointer in
                return dataIn.withUnsafeBytes { dataInUnsafeRawBufferPointer in
                    // Give the data out some breathing room for PKCS7's padding.
                    let dataOutSize: Int = dataIn.count + kCCBlockSizeAES128 * 2
                    let dataOut = UnsafeMutableRawPointer.allocate(byteCount: dataOutSize, alignment: 1)
                    defer { dataOut.deallocate() }
                    var dataOutMoved: Int = 0
                    let status = CCCrypt(CCOperation(operation),
                                         CCAlgorithm(algorithm),
                                         CCOptions(options),
                                         keyUnsafeRawBufferPointer.baseAddress, key.count,
                                         ivUnsafeRawBufferPointer.baseAddress,
                                         dataInUnsafeRawBufferPointer.baseAddress, dataIn.count,
                                         dataOut, dataOutSize,
                                         &dataOutMoved)
                    guard status == kCCSuccess else { return nil }
                    return Data(bytes: dataOut, count: dataOutMoved)
                }
            }
        }
    }
    
    func aesGCMEncrypt(key: Data) throws -> Data? {
        let symmetricKey = SymmetricKey(data: SHA256.hash(data:key))
        let nonce = AES.GCM.Nonce()
        guard let sealedBox = try? AES.GCM.seal(self, using: symmetricKey, nonce: nonce) else {
            throw AESError.encryptionFailed
        }
        return sealedBox.combined
    }
    
    func aesGCMDecrypt(key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: SHA256.hash(data:key))
        let sealedBox = try AES.GCM.SealedBox(combined: self)
        guard let decryptedData = try? AES.GCM.open(sealedBox, using: symmetricKey) else {
            throw AESError.decryptionFailed
        }
        return decryptedData
    }
}

public func randomGenerateBytes(count: Int) -> Data? {
    let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
    defer { bytes.deallocate() }
    let status = CCRandomGenerateBytes(bytes, count)
    guard status == kCCSuccess else { return nil }
    return Data(bytes: bytes, count: count)
}

class Encryption {
    // getEncryptionKey generates a new private key and returns it as a hex string
    static func getEncryptionKey() -> String? {
        let keySize = kCCKeySizeAES256
        var keyData = Data(count: keySize)
        let result = keyData.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, keySize, $0.baseAddress!)
        }
        if result == errSecSuccess {
            return keyData.hexString
        } else {
            print("Problem generating random bytes")
            return nil
        }
    }
}
