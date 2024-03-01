//
//  common.swift
//  VoltixApp
//

import Foundation
import OSLog
import Tss
import CommonCrypto

enum HelperError: Error {
    case runtimeError(String)
}

struct SignatureProvider {
    let logger = Logger(subsystem: "chains", category: "tss")
    let signatures: [String: TssKeysignResponse]

    func getDerSignature(preHash: Data) -> Data {
        let hex = preHash.hexString
        if let sig = signatures[hex] {
            let sigResult = sig.getDERSignature()
            switch sigResult {
            case .success(let sigData):
                return sigData
            case .failure(let err):
                switch err {
                case HelperError.runtimeError(let errDetail):
                    logger.error("fail to get signature from TssResponse,error:\(errDetail)")
                default:
                    logger.error("fail to get signature from TssResponse,error:\(err.localizedDescription)")
                }
            }
        }
        return Data()
    }

    func getSignatureWithRecoveryID(preHash: Data) -> Data {
        let hex = preHash.hexString
        if let sig = signatures[hex] {
            let sigResult = sig.getSignatureWithRecoveryID()
            switch sigResult {
            case .success(let sigData):
                logger.info("successfully get signature")
                return sigData
            case .failure(let err):
                switch err {
                case HelperError.runtimeError(let errDetail):
                    logger.error("fail to get signature from TssResponse,error:\(errDetail)")
                default:
                    logger.error("fail to get signature from TssResponse,error:\(err.localizedDescription)")
                }
            }
        }
        return Data()
    }
    func getSignature(preHash: Data) -> Data {
        let hex = preHash.hexString
        if let sig = signatures[hex] {
            let sigResult = sig.getSignature()
            switch sigResult {
            case .success(let sigData):
                logger.info("successfully get signature")
                return sigData
            case .failure(let err):
                switch err {
                case HelperError.runtimeError(let errDetail):
                    logger.error("fail to get signature from TssResponse,error:\(errDetail)")
                default:
                    logger.error("fail to get signature from TssResponse,error:\(err.localizedDescription)")
                }
            }
        }
        return Data()
    }
}

extension Int64 {
    func hexString() -> String {
        var hexStr = String(format: "%02x", self)
        if hexStr.count % 2 != 0 {
            hexStr = "0" + hexStr
        }
        return hexStr
    }
}

extension Data{
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
}
