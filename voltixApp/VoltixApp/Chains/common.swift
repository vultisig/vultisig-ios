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
