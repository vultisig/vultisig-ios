//
//  TssExtensions.swift
//  VoltixApp
//

import Foundation
import Tss

extension TssKeysignResponse {
    func getDERSignature() -> Result<Data, Error> {
        guard let derSig = Data(hexString: derSignature) else {
            return .failure(HelperError.runtimeError("fail to get der signature"))
        }
        return .success(derSig)
    }

    func getSignatureWithRecoveryID() -> Result<Data, Error> {
        guard let rData = Data(hexString: r) else {
            return .failure(HelperError.runtimeError("fail to get r data"))
        }
        guard let sData = Data(hexString: s) else {
            return .failure(HelperError.runtimeError("fail to get s data"))
        }

        guard let v = UInt8(recoveryID, radix: 16) else {
            return .failure(HelperError.runtimeError("fail to get recovery data"))
        }

        var signature = Data()
        signature.append(rData)
        signature.append(sData)
        signature.append(Data([v]))
        return .success(signature)
    }
    // keep in mind EdDSA signature from TSS is in little endian format , need to convert it to bigendian
    func getSignature() -> Result<Data, Error> {
        guard var rData = Data(hexString: r) else {
            return .failure(HelperError.runtimeError("fail to get r data"))
        }
        rData.reverse()
        guard var sData = Data(hexString: s) else {
            return .failure(HelperError.runtimeError("fail to get s data"))
        }
        sData.reverse()
        var signature = Data()
        signature.append(rData)
        signature.append(sData)
        return .success(signature)
    }
}
